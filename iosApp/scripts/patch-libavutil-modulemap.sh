#!/usr/bin/env bash
# Patch Libavutil's modulemap to exclude hwcontext_amf.h.
#
# Background:
#   The Libavutil.xcframework shipped by mpvkit/ffmpeg-build declares
#   `umbrella "." ; export *` in its module.modulemap, which pulls in every
#   header in the framework. The umbrella list includes hwcontext_amf.h, which
#   unconditionally `#include`s <AMF/core/Factory.h> from AMD's AMF SDK. That
#   SDK is not shipped with the framework (AMD-only, not applicable to Apple
#   platforms), so Swift / Clang module validation fails with:
#
#     fatal error: 'AMF/core/Factory.h' file not found
#
#   The existing modulemap already excludes other hw-backend headers
#   (hwcontext_vulkan.h, hwcontext_vaapi.h, hwcontext_cuda.h, etc.) — it just
#   misses hwcontext_amf.h. This is the same upstream bug that affected MPVKit
#   before the FFmpeg source was switched to mpvkit/ffmpeg-build.
#
# What this does:
#   Finds every module.modulemap under any Libavutil.xcframework in DerivedData
#   and adds `exclude header "hwcontext_amf.h"` next to the other excludes.
#   Idempotent — files that already contain the exclusion are skipped.
#
#   The search is path-agnostic: it does not assume which SPM artifact directory
#   name Xcode assigns to the package (e.g. "ffmpeg-build", "ffmpeg", "FFmpeg",
#   …). It simply finds all Libavutil.xcframework module.modulemaps anywhere
#   under DerivedData.
#
# When to run:
#   - After a clean build / DerivedData reset.
#   - After a package version bump that still ships the broken xcframework.
#
# Upstream fix:
#   A one-line PR to https://github.com/mpvkit/libavutil-build would resolve
#   this permanently. Until then we patch locally.

set -euo pipefail

derived_data="${HOME}/Library/Developer/Xcode/DerivedData"
patched=0
skipped=0

while IFS= read -r -d '' modulemap; do
    if grep -q 'hwcontext_amf.h' "${modulemap}"; then
        skipped=$((skipped + 1))
        continue
    fi
    # Insert exclude line after the hwcontext_cuda.h exclusion.
    sed -i '' 's|exclude header "hwcontext_cuda.h"|exclude header "hwcontext_cuda.h"\
    exclude header "hwcontext_amf.h"|' "${modulemap}"
    echo "patched: ${modulemap}"
    patched=$((patched + 1))
done < <(find "${derived_data}" -path '*/Libavutil.xcframework/*/module.modulemap' -print0 2>/dev/null)

echo
echo "patched ${patched} modulemap(s); ${skipped} already patched"
