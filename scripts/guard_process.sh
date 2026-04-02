#!/bin/bash
# Ensures raw Process() calls do not re-enter the codebase.
# The only allowed usage is inside ProcessAdapter implementations.

VIOLATIONS=$(grep -rnw -E "\bProcess\(\)" Sources/OracleOS/ | grep \.swift | grep -v "ProcessAdapter.swift" | grep -v "DefaultProcessAdapter.swift")

if [ -n "$VIOLATIONS" ]; then
    echo "🚨 ARCHITECTURE VIOLATION: Raw Process() instantiation found outside of ProcessAdapter!"
    echo "$VIOLATIONS"
    echo "Please use ProcessAdapter (e.g. adapter.spawnBackground() or adapter.runSync()) instead."
    exit 1
else
    echo "✅ No naked Process() invocations found."
    exit 0
fi
