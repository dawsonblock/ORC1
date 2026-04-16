#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <path-to-app-or-dmg>" >&2
    exit 1
fi

TARGET_PATH="$1"
if [[ ! -e "$TARGET_PATH" ]]; then
    echo "Missing target: $TARGET_PATH" >&2
    exit 1
fi

PROOF_DIR="${ORACLE_CONTROLLER_PROOF_DIR:-$(dirname "$TARGET_PATH")/controller-release-proof}"

if [[ "$TARGET_PATH" == *.app ]]; then
    ORACLE_CONTROLLER_PROOF_DIR="$PROOF_DIR" "$SCRIPT_DIR/verify-controller-release-artifact.sh" app "$TARGET_PATH"
elif [[ "$TARGET_PATH" == *.dmg ]]; then
    ORACLE_CONTROLLER_PROOF_DIR="$PROOF_DIR" ORACLE_REQUIRE_SIGNED_DMG="1" "$SCRIPT_DIR/verify-controller-release-artifact.sh" dmg "$TARGET_PATH"
fi

if [[ -n "${APPLE_NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$TARGET_PATH" --keychain-profile "$APPLE_NOTARY_PROFILE" --wait
elif [[ -n "${APPLE_NOTARY_KEY_PATH:-}" && -n "${APPLE_NOTARY_KEY_ID:-}" && -n "${APPLE_NOTARY_ISSUER_ID:-}" ]]; then
    xcrun notarytool submit \
        "$TARGET_PATH" \
        --key "$APPLE_NOTARY_KEY_PATH" \
        --key-id "$APPLE_NOTARY_KEY_ID" \
        --issuer "$APPLE_NOTARY_ISSUER_ID" \
        --wait
else
    echo "Missing notarytool credentials. Set APPLE_NOTARY_PROFILE or APPLE_NOTARY_KEY_PATH/APPLE_NOTARY_KEY_ID/APPLE_NOTARY_ISSUER_ID." >&2
    exit 1
fi

xcrun stapler staple "$TARGET_PATH"
ORACLE_CONTROLLER_PROOF_DIR="$PROOF_DIR" "$SCRIPT_DIR/verify-controller-release-artifact.sh" notarized "$TARGET_PATH"

echo "Notarized and stapled:"
echo "  $TARGET_PATH"
echo "Release proof logs:"
echo "  $PROOF_DIR"
