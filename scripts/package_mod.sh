#!/usr/bin/env bash
# Package SpidertronHunter for Factorio Mod Portal upload.
# Produces: SpidertronHunter_<version>.zip containing SpidertronHunter_<version>/...
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NAME="$(python3 -c "import json; print(json.load(open('info.json'))['name'])")"
VERSION="$(python3 -c "import json; print(json.load(open('info.json'))['version'])")"
FOLDER="${NAME}_${VERSION}"
ZIP="${FOLDER}.zip"
OUT_DIR="${1:-dist}"

rm -rf "${OUT_DIR}/${FOLDER}" "${OUT_DIR}/${ZIP}"
mkdir -p "${OUT_DIR}/${FOLDER}"

should_exclude() {
  local rel="$1"
  case "${rel}" in
    .git|.git/*|.github|.github/*|tests|tests/*|docs|docs/*|dist|dist/*) return 0 ;;
    .gitattributes|.gitignore|CONTRIBUTING.md) return 0 ;;
    # Maintainer scripts / binaries — Mod Portal rejects executables; not needed in-game
    *.sh|*.ps1|*.py|scripts/package_mod.sh) return 0 ;;
    graphics/shortcut/hunter-source.png) return 0 ;;
    *.zip|*.exe|*.dll|*.so|*.dylib|*.bat|*.cmd|*.com) return 0 ;;
  esac
  return 1
}

while IFS= read -r -d '' path; do
  rel="${path#./}"
  if should_exclude "${rel}"; then
    continue
  fi
  dest="${OUT_DIR}/${FOLDER}/${rel}"
  mkdir -p "$(dirname "${dest}")"
  # Copy without preserving mode so the execute bit never lands in the portal zip
  cp --no-preserve=mode "${path}" "${dest}"
  chmod a-x "${dest}"
done < <(find . -type f -print0)

(
  cd "${OUT_DIR}"
  rm -f "${ZIP}"
  # -X omits extra Unix fields; files are already non-executable above
  zip -qrX "${ZIP}" "${FOLDER}"
)

echo "Created ${OUT_DIR}/${ZIP}"
unzip -l "${OUT_DIR}/${ZIP}" | head -40 || true
