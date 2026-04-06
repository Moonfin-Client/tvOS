#!/bin/bash
# Patches MPVKit's Libavutil module map to exclude hwcontext_amf.h
# which references AMF/core/Factory.h (AMD only, unavailable on Apple platforms).
# This runs as a pre-build script phase so the modules can be imported from Swift.

set -euo pipefail

DERIVED_DATA="${BUILD_DIR%/Build/Products}"
if [ "$DERIVED_DATA" = "$BUILD_DIR" ]; then
    # Fallback: try stripping with trailing slash or subdirectory
    DERIVED_DATA="${BUILD_DIR%/Build/*}"
fi
ARTIFACTS_DIR="${DERIVED_DATA}/SourcePackages/artifacts/mpvkit"

patch_modulemap() {
    local modulemap="$1"
    if [ ! -f "$modulemap" ]; then
        return 0
    fi
    if grep -q 'exclude header "hwcontext_amf.h"' "$modulemap"; then
        return 0  # Already patched
    fi
    if grep -q 'exclude header "hwcontext_cuda.h"' "$modulemap"; then
        sed -i '' 's/exclude header "hwcontext_cuda.h"/exclude header "hwcontext_cuda.h"\
    exclude header "hwcontext_amf.h"/' "$modulemap"
    elif grep -q 'umbrella' "$modulemap"; then
        sed -i '' 's/umbrella "\."/umbrella "."\
    exclude header "hwcontext_amf.h"/' "$modulemap"
    fi
    return 0
}

if [ -d "$ARTIFACTS_DIR" ]; then
    find "$ARTIFACTS_DIR" -path "*/Libavutil*/module.modulemap" 2>/dev/null | while read -r modulemap; do
        patch_modulemap "$modulemap"
    done || true
fi

if [ -d "${BUILD_DIR}" ]; then
    find "${BUILD_DIR}" -path "*/Libavutil.framework/Modules/module.modulemap" 2>/dev/null | while read -r modulemap; do
        patch_modulemap "$modulemap"
    done || true
fi

echo "MPVKit module maps patched successfully"
