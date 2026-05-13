# AGENTS.md

This file is for coding agents working in this repository. It captures implementation details and invariants that are easy to break during UI/behavior changes.

## Code Map (What Lives Where)
- `Sources/NetMon/NetMonApp.swift`
  - App lifecycle + global keyboard monitor (`Cmd+E`, `Cmd+M`, `Cmd+R`) via `NotificationCenter`.
- `Sources/NetMon/NetMonWindowController.swift`
  - Window creation, style/level, frame restore/save, default positioning, screen selection helpers, reset behavior.
- `Sources/NetMon/ContentView.swift`
  - Root composition, header layout behavior, click hit-testing, context menu building, compact/expand/reset transitions, glass/tint rendering.
- `Sources/NetMon/LatencyGraphView.swift`
  - Time-window clipping, smoothing/interpolation, latency + traffic graph rendering, left/right axis labels, live dot.
- `Sources/NetMon/PingStore.swift`
  - App state, persistence (`netmon.config`), engine lifecycle, always-on-top propagation.
- `Sources/NetMon/PingEngine.swift`
  - ICMP sampling (`/sbin/ping`), network byte deltas from `getifaddrs`, result history.

## Persistence Keys and Their Meaning
- `netmon.config` (dictionary): main persisted runtime config.
  - Keys: `alwaysOnTop`, `pingInterval`, `isCompact`, `showLatencyGraph`, `showTrafficGraph`, `tintLevel`.
- `netmon.windowFrame`: serialized `NSWindow.frame` used for restore on launch.
- `netmon.lastExpandedHeight`: last non-compact height used when toggling compact/full.
- `netmon.isExpandedWindow`: whether current mode is expanded (x4/full-frame state).
- `netmon.preExpandFrame`: frame to restore after leaving expanded mode.

If changing key names, provide migration logic or preserve backward compatibility.

## Windowing and Screen Invariants
- Primary screen fallback is derived from screen containing `.zero` (`NSScreen.main` is intentionally avoided).
- On launch:
  - Restore `netmon.windowFrame` if it intersects a visible screen.
  - Else place at top-right of current/primary visible frame.
- Reset behavior:
  - Clears saved frame + `netmon.lastExpandedHeight`.
  - Resets size to default width and mode-dependent height.
  - Snaps flush to top-right of the current/primary visible frame.
- Compact mode must remove `.resizable`; full mode must restore `.resizable`.

## Interaction Contract (Double-click + Context Menu)
- Right-click is available on the full window via overlay click handler.
- Double-click routing is area-based:
  - Header zone: toggle `Minimize`/`Full`.
  - Graph zone: toggle `Expand (x4)`/`Restore Size`.
- Header hit zone is intentionally small in normal mode; avoid broadening it unless asked.
- In compact mode, `Expand` action is hidden from the menu.

## Graph Rendering Invariants
- All graph series use a 60s scrolling window and smooth reveal of the newest segment.
- Traffic series:
  - `bytesIn` is mirrored upward from center baseline.
  - `bytesOut` is mirrored downward.
  - Right axis is symmetric around zero.
- Latency series:
  - Foreground prominence over traffic background.
  - Segment-level coloring (not whole-line recolor).
  - Packet loss (`latencyMs == nil`) rendered as red segment with value treated as `0` for plotting.
- Axis behavior:
  - Left axis snaps to 10-step values.
  - Left axis should never exceed 5 labels in larger sizes; in small heights show top+bottom only.
  - Right axis can drop mid labels when space is constrained.
- Keep chart area clean: no dashed grid overlays.

## Header/Badge Layout Rules
- Left badge = latency.
- Right group = bytes down + bytes up.
- Center title (`NetMon`) only when width threshold allows.
- Label modes by width:
  - narrow: no label
  - medium: short labels
  - wide: full labels
- Compact mode uses reduced vertical padding; when width is tight, prioritize fitting value text over labels.
- Loss badge state: latency badge turns red and displays `∞`.

## Tint/Blur Behavior
- Tint level range is clamped to `0...4`.
- Menu label is `Tint/Blur` and controls both dark overlay and blur opacity.
- Current tint selection is persisted and should survive reset/restart.
- Reset view must keep current tint level (do not revert tint).

## Data Pipeline Notes
- Ping command: `/sbin/ping -c 1 -W 1000 -s 56 <host>`.
- Byte throughput is derived from delta of aggregate non-loopback `AF_LINK` counters.
- First sample after launch/restart can show near-zero byte deltas due to baseline snapshot initialization.
- History length is capped (`maxHistory = 60`); keep this consistent with graph window assumptions unless intentionally changing time horizon.

## Agent Workflow Tips
- For iterative app testing, prefer `./run-netmon.sh` (rebuilds, copies to `/Applications`, relaunches).
- If a UI behavior appears stale, verify the binary actually running is `/Applications/NetMon.app/Contents/MacOS/NetMon`.
- After modifying README screenshot layout, keep image+caption pairs grouped (HTML blocks are currently used for reliable sizing/caption positioning on GitHub).

## High-Risk Changes (Double-check)
- Any edits to frame persistence/reset/expand logic (`ContentView` + `NetMonWindowController`) can regress multi-screen placement.
- Any edits to hit-testing math can swap title/graph double-click behavior.
- Any edits to graph coordinate mapping can misalign left/right axis labels or invert traffic direction.
- Any edits to loss handling can accidentally recolor entire latency path instead of only loss segments.
