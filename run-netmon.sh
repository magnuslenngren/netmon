#!/usr/bin/env zsh
set -euo pipefail

cd "$(dirname "$0")"

swift build
mkdir -p NetMon.app/Contents/MacOS
cp -f .build/debug/NetMon NetMon.app/Contents/MacOS/NetMon
ditto NetMon.app /Applications/NetMon.app
pkill -f "/Applications/NetMon.app/Contents/MacOS/NetMon" || true
open /Applications/NetMon.app

echo "NetMon rebuilt, installed to /Applications, and launched."
