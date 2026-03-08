#!/usr/bin/env zsh
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  VERSION="$(date +%Y.%m.%d)-$(git rev-parse --short HEAD)"
fi

APP_NAME="NetMon.app"
DMG_NAME="NetMon-${VERSION}.dmg"
DIST_DIR="dist"
STAGE_DIR="${DIST_DIR}/dmg-stage"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"

mkdir -p "${DIST_DIR}"
rm -rf "${STAGE_DIR}" "${DMG_PATH}"
mkdir -p "${STAGE_DIR}"

swift build
cp -f .build/debug/NetMon "${APP_NAME}/Contents/MacOS/NetMon"
cp -R "${APP_NAME}" "${STAGE_DIR}/"
ln -s /Applications "${STAGE_DIR}/Applications"

hdiutil create \
  -volname "NetMon" \
  -srcfolder "${STAGE_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}" >/dev/null

rm -rf "${STAGE_DIR}"
echo "${DMG_PATH}"
