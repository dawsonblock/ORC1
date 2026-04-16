#!/bin/bash
set -euo pipefail

usage() {
    echo "Usage: $0 <app|dmg|notarized> <path-to-artifact>" >&2
}

if [[ $# -lt 2 ]]; then
    usage
    exit 1
fi

MODE="$1"
TARGET_PATH="$2"
PROOF_DIR="${ORACLE_CONTROLLER_PROOF_DIR:-$(dirname "$TARGET_PATH")/controller-release-proof}"

mkdir -p "$PROOF_DIR"

run_and_capture() {
    local label="$1"
    shift
    local log_path="$PROOF_DIR/$label.txt"

    echo "==> $label"
    "$@" 2>&1 | tee "$log_path"
}

write_note() {
    local label="$1"
    shift
    local log_path="$PROOF_DIR/$label.txt"
    printf '%s\n' "$@" | tee "$log_path"
}

verify_app_bundle() {
    local app_bundle="$1"
    local info_plist="$app_bundle/Contents/Info.plist"
    local main_binary="$app_bundle/Contents/MacOS/OracleController"
    local helper_binary="$app_bundle/Contents/Helpers/OracleControllerHost"

    if [[ ! -d "$app_bundle" ]]; then
        echo "Missing app bundle: $app_bundle" >&2
        exit 1
    fi

    if [[ ! -f "$info_plist" ]]; then
        echo "Missing Info.plist at $info_plist" >&2
        exit 1
    fi

    if [[ ! -x "$main_binary" || ! -x "$helper_binary" ]]; then
        echo "Signed controller binaries are missing from $app_bundle" >&2
        exit 1
    fi

    run_and_capture "app-info-plist-lint" plutil -lint "$info_plist"

    if grep -q "__ORACLE_" "$info_plist"; then
        write_note "app-info-plist-placeholder-check" "Unresolved Oracle version placeholders remain in $info_plist"
        exit 1
    fi
    write_note "app-info-plist-placeholder-check" "Info.plist placeholders resolved for $app_bundle"

    run_and_capture "app-main-codesign-verify" codesign --verify --verbose=2 --strict "$main_binary"
    run_and_capture "app-helper-codesign-verify" codesign --verify --verbose=2 --strict "$helper_binary"
    run_and_capture "app-bundle-codesign-verify" codesign --verify --deep --verbose=2 --strict "$app_bundle"
    run_and_capture "app-bundle-codesign-details" codesign -d --verbose=4 "$app_bundle"
}

verify_dmg() {
    local dmg_path="$1"
    local require_signature="${ORACLE_REQUIRE_SIGNED_DMG:-0}"

    if [[ ! -f "$dmg_path" ]]; then
        echo "Missing DMG: $dmg_path" >&2
        exit 1
    fi

    if [[ "$require_signature" == "1" ]]; then
        run_and_capture "dmg-codesign-verify" codesign --verify --verbose=2 --strict "$dmg_path"
        run_and_capture "dmg-codesign-details" codesign -d --verbose=4 "$dmg_path"
    else
        write_note "dmg-signature-check" "Skipping DMG signature verification because ORACLE_REQUIRE_SIGNED_DMG is not set."
    fi

    run_and_capture "dmg-sha256" shasum -a 256 "$dmg_path"
}

verify_notarized_target() {
    local target_path="$1"
    local assess_type="open"

    if [[ ! -e "$target_path" ]]; then
        echo "Missing notarized target: $target_path" >&2
        exit 1
    fi

    if [[ "$target_path" == *.app ]]; then
        assess_type="execute"
    fi

    run_and_capture "notarized-stapler-validate" xcrun stapler validate "$target_path"
    run_and_capture "notarized-spctl-assess" spctl --assess --verbose=4 --type "$assess_type" --context context:primary-signature "$target_path"
}

case "$MODE" in
    app)
        verify_app_bundle "$TARGET_PATH"
        ;;
    dmg)
        verify_dmg "$TARGET_PATH"
        ;;
    notarized)
        verify_notarized_target "$TARGET_PATH"
        ;;
    *)
        usage
        exit 1
        ;;
esac