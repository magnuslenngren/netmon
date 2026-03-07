# NetMon

A minimal macOS network monitor widget that lives in the top-right corner of your screen.

![NetMon widget showing real-time latency graph](https://github.com/magnuslenngren/netmon/raw/master/screenshot.png)

## Features

- **Real-time ICMP ping** — pings Cloudflare (`1.1.1.1`) every 1 second using standard 56-byte packets
- **Live dual graph**:
  - latency (foreground) with segment-based color transitions
  - traffic bytes down/up (background) in mirrored blue series around a center baseline
  - smooth scrolling, interpolation and clipping at both edges
- **Dual Y-axes**:
  - left axis for latency (10-step labeling, adaptive density)
  - right axis for bytes (adaptive labels and spacing for small sizes)
- **Glass design** — semi-transparent widget with lightweight border
- **Window state persistence** — remembers size and position across restarts
- **Always on top toggle** — can be changed at runtime from context menu
- **Full-window interactions**:
  - double-click anywhere to collapse/expand
  - right-click anywhere for context menu
- **Context menu controls**:
  - Always on Top
  - Minimize / Full
  - Expand / Restore Size
  - Reset View
  - Show/Hide Latency Graph
  - Show/Hide Traffic Graph
- **Keyboard shortcuts**:
  - `Cmd+E` Expand / Restore Size
  - `Cmd+M` Minimize / Full
  - `Cmd+R` Reset View
- No Dock icon, no menu bar clutter

## Requirements

- macOS 14 (Sonoma) or later
- Xcode Command Line Tools (`xcode-select --install`)

## Build & Run

```bash
git clone https://github.com/magnuslenngren/netmon
cd netmon
swift build
cp .build/debug/NetMon NetMon.app/Contents/MacOS/NetMon
ditto NetMon.app /Applications/NetMon.app
open /Applications/NetMon.app
```

## Fast Run Script

Use the included script to rebuild, install to `/Applications`, and relaunch:

```bash
./run-netmon.sh
```

## Auto-launch at Login

Drag `NetMon.app` to **System Settings → General → Login Items**.
