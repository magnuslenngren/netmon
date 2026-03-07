# NetMon

A minimal, always-on-top macOS network latency monitor that lives in the top-right corner of your screen.

![NetMon widget showing real-time latency graph](https://github.com/magnuslenngren/netmon/raw/master/screenshot.png)

## Features

- **Real-time ICMP ping** — pings Cloudflare (`1.1.1.1`) every 1 second using standard 56-byte packets
- **Live latency graph** — continuous smooth scrolling with progressive segment drawing
  - one-sample delayed rendering for smoother motion
  - smooth left-edge clipping when old segments leave the view
  - dynamic y-axis that rescales smoothly as visible peaks/valleys change
  - 🟢 Green — under 50ms
  - 🟡 Yellow — 50–100ms
  - 🔴 Red — over 100ms
- **Host-aware title** — window/header title shows the current ping host (`1.1.1.1`)
- **Glass design** — semi-transparent widget with lightweight border
- **Always on top** — floats above all windows, never gets in the way
- **Double-click** the title bar to collapse to a slim bar, double-click again to expand
- **Right-click** for a quick-quit menu
- No Dock icon, no menu bar clutter

## Requirements

- macOS 14 (Sonoma) or later
- Xcode Command Line Tools (`xcode-select --install`)

## Build & Run

```bash
git clone https://github.com/magnuslenngren/netmon
cd netmon
swift build -c release
cp .build/release/NetMon NetMon.app/Contents/MacOS/NetMon
ditto NetMon.app /Applications/NetMon.app
open /Applications/NetMon.app
```

## Auto-launch at Login

Drag `NetMon.app` to **System Settings → General → Login Items**.
