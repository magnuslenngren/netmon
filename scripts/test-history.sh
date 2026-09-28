#!/usr/bin/env zsh
set -euo pipefail
cd "$(dirname "$0")/.."
developer_dir="$(xcode-select -p)"
if [[ -z "${SDKROOT:-}" ]]; then
  if [[ -d "${developer_dir}/SDKs/MacOSX.sdk" ]]; then
    SDKROOT="${developer_dir}/SDKs/MacOSX.sdk"
  else
    SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
  fi
fi
mkdir -p .build/module-cache
xcrun swiftc -swift-version 5 -sdk "$SDKROOT" \
  -module-cache-path .build/module-cache -o .build/graph-history-tests \
  Sources/NetMon/GraphHistory.swift Sources/NetMon/PingEngine.swift \
  Sources/NetMon/PingStore.swift Sources/NetMon/LatencyGraphView.swift \
  Sources/NetMon/NetworkStatus.swift Tests/GraphHistory/main.swift
.build/graph-history-tests
