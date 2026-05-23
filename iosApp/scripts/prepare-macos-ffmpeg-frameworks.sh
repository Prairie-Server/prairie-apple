#!/usr/bin/env bash
set -euo pipefail

if [[ "${PLATFORM_NAME:-}" != macosx ]]; then
  exit 0
fi

artifact_roots=()
framework_roots=()

if [[ -n "${BUILD_DIR:-}" && "${BUILD_DIR}" == *"/Build/"* ]]; then
  derived_data_root="${BUILD_DIR%%/Build/*}"
  artifact_roots+=("${derived_data_root}/SourcePackages/artifacts/ffmpeg-build")
fi

if [[ -n "${SRCROOT:-}" ]]; then
  artifact_roots+=("${SRCROOT}/build/SourcePackages/artifacts/ffmpeg-build")
fi

if [[ -n "${TARGET_BUILD_DIR:-}" && -n "${FRAMEWORKS_FOLDER_PATH:-}" ]]; then
  framework_roots+=("${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}")
fi

normalize_framework() {
  local framework="$1"

  [[ -d "${framework}/Versions" ]] && return 0

  local name version_dir resources_dir
  name="$(basename "${framework}" .framework)"
  version_dir="${framework}/Versions/A"
  resources_dir="${version_dir}/Resources"

  mkdir -p "${resources_dir}"

  shopt -s nullglob dotglob
  for item in "${framework}"/*; do
    local item_name
    item_name="$(basename "${item}")"
    case "${item_name}" in
      Versions)
        ;;
      Info.plist)
        mv "${item}" "${resources_dir}/Info.plist"
        ;;
      _CodeSignature)
        rm -rf "${item}"
        ;;
      *)
        mv "${item}" "${version_dir}/${item_name}"
        ;;
    esac
  done
  shopt -u nullglob dotglob

  ln -s A "${framework}/Versions/Current"

  [[ -e "${version_dir}/${name}" ]] && ln -s "Versions/Current/${name}" "${framework}/${name}"
  [[ -d "${version_dir}/Headers" ]] && ln -s "Versions/Current/Headers" "${framework}/Headers"
  [[ -d "${version_dir}/PrivateHeaders" ]] && ln -s "Versions/Current/PrivateHeaders" "${framework}/PrivateHeaders"
  [[ -d "${version_dir}/Modules" ]] && ln -s "Versions/Current/Modules" "${framework}/Modules"
  ln -s "Versions/Current/Resources" "${framework}/Resources"
}

for root in "${artifact_roots[@]}"; do
  [[ -d "${root}" ]] || continue
  find "${root}" -path "*/macos-*/*.framework" -type d -maxdepth 5 -print0 | while IFS= read -r -d '' framework; do
    normalize_framework "${framework}"
  done
done

for root in "${framework_roots[@]}"; do
  [[ -d "${root}" ]] || continue
  find "${root}" -name "*.framework" -type d -maxdepth 1 -print0 | while IFS= read -r -d '' framework; do
    normalize_framework "${framework}"
  done
done
