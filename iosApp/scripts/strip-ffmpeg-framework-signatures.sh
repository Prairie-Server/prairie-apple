#!/usr/bin/env bash
set -euo pipefail

case "${PLATFORM_NAME:-}" in
  iphoneos|appletvos)
    ;;
  *)
    exit 0
    ;;
esac

roots=()

if [[ -n "${BUILD_DIR:-}" && "${BUILD_DIR}" == *"/Build/"* ]]; then
  derived_data_root="${BUILD_DIR%%/Build/*}"
  roots+=("${derived_data_root}/SourcePackages/artifacts/ffmpeg-build")
fi

if [[ -n "${SRCROOT:-}" ]]; then
  roots+=("${SRCROOT}/build/SourcePackages/artifacts/ffmpeg-build")
fi

if [[ -n "${TARGET_BUILD_DIR:-}" && -n "${FRAMEWORKS_FOLDER_PATH:-}" ]]; then
  roots+=("${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}")
fi

for root in "${roots[@]}"; do
  [[ -d "${root}" ]] || continue
  find "${root}" -type d -name _CodeSignature -prune -exec rm -rf {} +
done
