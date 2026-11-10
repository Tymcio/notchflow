# Performance budget

NotchFlow targets near-zero resource usage when collapsed and idle.

## Targets

| Metric | Target | Verification |
|--------|--------|--------------|
| CPU (idle, collapsed) | ~0% | Instruments Time Profiler, 5 min |
| RAM (idle) | < 50 MB | Instruments Allocations |
| Energy | No persistent timers | Energy Log |
| Wakeups | Event-driven only | Points of Interest |

## Checklist before release

1. Collapse island and pause media for 5 minutes — confirm no timer wakeups in Time Profiler.
2. Drag file to shelf — confirm APFS hard link created (no duplicate bytes).
3. Hot-plug external display — island follows cursor screen.
4. Compare battery drain over 1h idle vs baseline (no NotchFlow).

## Profiling commands

```bash
# Build release
swift build -c release
Scripts/package_app.sh

# Sample CPU while idle (replace PID)
sample $(pgrep NotchFlow) 5 -file /tmp/notchflow-sample.txt
```

## Architecture rules

- No unconditional polling loops for media, HUD, calendar or license checks
- Never block the main thread on IPC: Accessibility, AppleScript, EventKit and AVCaptureSession calls run on background queues
- AppleScript (`NSAppleScript`) runs only on `AppleScriptExecutor`'s serial queue — never concurrently, never on the main thread; poll scripts are compiled once and wrapped in `with timeout`
- AppleScript media polling (one compiled script per *running* player, 0.75 s) runs only while the island is expanded on the media module and playback is active
- Media monitor uses distributed notifications as the primary source and publishes immediately; artwork and lyrics are fetched afterwards per track (cancellable, results and misses cached, 5 s network timeout) and artwork is downsampled to 104 px
- Menu bar overlap layout is event-driven (`didActivateApplicationNotification` + delayed refresh)
- On displays without a notch, the menu bar hit-test scan and the full-screen window check run on a background serial queue, debounced and cached for 2 s; Accessibility timeouts are set per element, never on the system-wide element (that would change the process-wide default)
- Mouse tracking coalesced on `mouseMoved` (no Accessibility polling for menu layout)
- Notification Center banners (premium notifications) are detected by an `AXObserver` (a short burst of scans per UI change) plus a 1.5 s safety poll (0.5 s tolerance) while notifications are enabled; the tree walk runs off the main thread with a 0.25 s AX messaging timeout per element and node / 1.5 s time budgets per scan. Quick replies and banner dismissal use the same background queue
  - Why the poll is short: on Tahoe toasts are children of a persistent full-screen `AXSystemDialog`, and Notification Center does not reliably post created/layout events for them, so with a 5 s poll a banner could reach the island up to 5 s late. Idle scans stop after a cheap top-level check, so the poll costs a few AX reads per tick. Relax it once event delivery is verified on hardware
  - The observer's run-loop source is added in `.commonModes`; `.defaultMode` drops events while a menu is being tracked
- Looping indicators (equalizer, agent typing dots, attention / finished-timer glow) are Core Animation layer animations: they run in the render server, stop when off screen and are static with Reduce Motion — no SwiftUI `repeatForever`
- Volume / brightness HUD (only while "Show volume and brightness in the notch" is on; off installs nothing): CoreAudio property listeners on the default output device's volume and mute (re-attached when the default device changes, bursts coalesced into one read per run-loop turn) plus `.systemDefined` NSEvent monitors for the brightness keys. Brightness is read from the built-in display only after a brightness key press (60 ms later, once per burst, and once more when the keys settle) — no polling. The level hides itself 1.5 s after the last change
- Focus timer: one timer per phase end; views redraw once per displayed second only while a timer runs; muted-alert detection uses a CoreAudio property listener
- Calendar refreshes on `EKEventStoreChanged`, day change, wake, and a one-shot timer at the next event start/end (at most hourly otherwise)
- Agent stale-session watchdog (5 s) runs only while an agent session is running or waiting
