# Resource impact: BetterActivityMonitor vs btop, top, Activity Monitor

Date: 2026-11-04 · Machine: Apple M4 Pro, 14 cores · macOS 27.0.1 (26A434) · App: 0.4.0 dev build in /Applications
Method: `bench.sh` (this folder) snapshots `ps` cumulative CPU time at the start and end of a 60 s window; CPU % = delta CPU time / wall time, as a percentage of ONE core. RSS taken at the end. Tools ran one at a time, all at about a 1 s refresh.
tmux tools ran in a private tmux server (`tmux -L bambench`).

## Results (60 s windows)

| Process | CPU (% of one core) | Memory (RSS) | Notes |
|---|---|---|---|
| **BetterActivityMonitor app** | **56-57%** | 150-170 MB | 6 clean runs: 56.95, 56.15, 57.22, 56.18, 57.28, 56.50 (+ 55.2 / 56.5 / 56.8 during AM runs) |
| BAMWidgets.appex (widget extension) | 0.7-0.8% | 37 MB | whatever widgets were placed at the time (count/speeds unknown, see Gaps) |
| chronod (WidgetKit host) | 0.2-0.4% | 56-75 MB | shared by ALL widgets on the system |
| btop, `-u 1000` (1 s) | 3.0% | 15 MB | |
| btop, config default | 22-26% | 16 MB | `~/.config/btop/btop.conf` has `update_ms = 100` (10 Hz) |
| top, 1 s default | 8.3% | 12 MB | |
| Activity Monitor | 4.5-4.6% | 105 MB | 5 s and 1 s runs equal; see Gaps |

Widgets total (extension + chronod): about 1% of a core.

## Why the app costs 57%

1. **Sampling is cheap.** `sysbench 40` (release): median 4.90 ms per tick total (processes 4.31, sensors 0 idle / 3.0 active, network 0.25, disks 0.20, gpu 0.07, others ~0). About 0.5% of a core at 1 s.
2. **UI work is not.** `sample` on the app: on-CPU samples were about 58% of wall samples, matching the measured CPU. Dominant stacks: `NSHostingView.layout` -> `ViewGraphRootValueUpdater.render` -> `ViewGraph.updateOutputs` -> `StackLayout.sizeThatFits` (AttributeGraph update/propagate_dirty, swift_retain/release). `-[NSStatusItem _updateReplicants]` and `MenuBarRenderer.image` also show up.
3. **It does not depend on the visible window.**

| State | App CPU |
|---|---|
| Window open | 57% |
| App hidden (System Events visible=false) | 56.2% |
| Main window closed, menu-bar item on | 57.2% (display cycle = 1966 of 3760 main-thread samples, 52%) |

   A SwiftUI view tree that isn't on screen is laid out every tick. Prime suspect (UNCONFIRMED): `MenuBarExtra(...).menuBarExtraStyle(.window)` in `Sources/BetterActivityMonitor/App.swift`; SwiftUI keeps the popover content alive while closed.
4. Inconclusive toggle test: with the menu-bar item off and the window open, two instances were running (a `build/BetterActivityMonitor.app` instance appeared, not started by the benchmark) at about 36-42% each, so no conclusion.

## Gaps / caveats

- Idle wakeups and energy impact NOT measured (`top` capture empty; `powermetrics` needs sudo). Suggested: `sudo powermetrics --samplers tasks --show-process-energy -i 5000 -n 12`.
- Widget count and update speeds unknown: App Group plist is sandboxed (permission denied). Widget numbers are for the placed-widget set at test time; widgets could not be toggled on/off.
- Activity Monitor: I set View > Update Frequency to 1 s; `UpdatePeriod` was 1 afterwards. Prior value unknown, so the "5 s" run may not have been 5 s.
- Side effects: app was quit once (closing the window with the menu-bar item off terminates it) and relaunched with `open -a`; user's tmux server untouched.
- Single machine, single session, other apps running (Xcode tooling, vite preview). CPU time from `ps` has 10 ms resolution.

## Next steps

- Inspect `MenuBarView` / `MenuBarLabel` and per-tick store invalidation; check whether the popover view tree can be torn down while closed.
- Re-measure with no other BetterActivityMonitor instance running, and with the menu-bar item off + window open.

## Files

- `bench.sh`: harness (`./bench.sh <label> <seconds> <pid:NNN or ps substring>`)
- `profiles/*.sample.txt.gz`: `sample` output, 8-10 s each (window open / app hidden / window closed)
