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

- No unconditional polling loops for media, HUD, or license checks
- AppleScript media polling runs only while the island is visible and playback is active
- Menu bar overlap layout is event-driven (`didActivateApplicationNotification` + delayed refresh)
- Mouse tracking coalesced on `mouseMoved` (no Accessibility polling for menu layout)
- Media monitor uses distributed notifications as the primary source; scripting bridge is a timing supplement only when needed
- Notification AX scan backs off to 1.5 s after eight empty scans (premium calls/notifications)
