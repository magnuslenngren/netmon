#!/usr/bin/env zsh
# Build without Swift Package Manager (NetMon has no external dependencies).
set -euo pipefail
cd "$(dirname "$0")/.."

# Prefer the Command Line Tools' selected SDK over a leftover newer SDK.
developer_dir="$(xcode-select -p)"
if [[ -z "${SDKROOT:-}" ]]; then
  if [[ -d "${developer_dir}/SDKs/MacOSX.sdk" ]]; then
    SDKROOT="${developer_dir}/SDKs/MacOSX.sdk"
  else
    SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
  fi
fi

mkdir -p .build/release .build/module-cache NetMon.app/Contents/MacOS
xcrun swiftc -O -swift-version 5 \
  -sdk "$SDKROOT" -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path .build/module-cache -module-name NetMon \
  -o .build/release/NetMon Sources/NetMon/*.swift
cp .build/release/NetMon NetMon.app/Contents/MacOS/NetMon
codesign --force --sign - NetMon.app
echo "Built NetMon.app for $(uname -m)."
