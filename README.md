# ActivityManagerReloaded

A native macOS system monitor with btop's feature set: CPU (per core, P/E), memory, GPU, network, disks,
temperatures, fans and battery, plus a fast, sortable process table with a tree view, signals, renice and
an inspector. It's built with SwiftUI, AppKit's NSTableView and Liquid Glass.

## Build & run

```sh
scripts/bundle.sh                     # release build → build/ActivityManagerReloaded.app (ad-hoc signed)
open build/ActivityManagerReloaded.app
```

`bundle.sh` restamps the binary with the installed SDK version (`vtool`). SwiftPM otherwise stamps
SDK 14.0, which makes macOS fall back to the legacy window chrome.

Layout: `Sources/SystemKit` holds the data samplers (no UI). `Sources/ActivityManagerReloaded` is the app.

## Tests

| Command | What it checks |
|---|---|
| `swift test -c release --filter SamplerTests` | Sanity checks: values in range, own PID visible, counters monotonic |
| `swift test -c release --filter SamplerPerformanceTests` | Sampler budgets: CPU ms per tick, per-sampler medians, sensor throttling |
| `scripts/bundle.sh && BAM_APP_PERF=1 swift test -c release --filter AppCPUTests` | Launches the bundled app on each screen and asserts its CPU % stays under a budget (opt-in, about 2 min) |
| `scripts/bundle.sh && BAM_APP_LAYOUT=1 swift test -c release --filter AppLayoutTests` | Renders every screen at 900×560, 1100×700 and 1400×900 and fails on overlapping cards, content spilling out of a card or horizontal clipping |

Run the performance tests in release mode. Debug builds are several times slower.

## Profiling & benchmarking tools

| Tool | Use |
|---|---|
| `swift run -c release sysbench` | Median/max time of every sampler and CPU ms per tick |
| `swift run -c release sysbench nettop [seconds]` | CPU cost of the Network tab's connection data: one `nettop` run per tick vs. its streaming mode, and `SystemMonitor` per tick in each `ConnectionMode` (own + nettop CPU) |
| `scripts/measure-screens.sh [seconds] [screen …]` | App CPU % per screen with its window frontmost (`APP_ENV="K=V"` passes env to the app). Network pages as `network:connections`, `network:listening`, `network:log` (or `BAM_NETWORK_PAGE=…`); nettop's own CPU isn't included, see `sysbench nettop` |
| `scripts/hot-frames.sh [seconds] [regex]` | `sample`s the newest running instance (`PID=` to pick one) and prints the heaviest app/UI frames |
| `scripts/check-layout.sh [out-dir] [sizes] [sections]` | Same layout audit by hand; PNGs + `layout-report.txt` land in `build/layout` |
| `scripts/resize-bench.sh [screens] [frames]` | Times every window-resize frame (layout + display) per screen: median / p95 / max ms, frames over the 16.7 ms 60 fps budget. Freezing during resize is on by default; `APP_ARGS="-freezeDuringResize NO"` measures live relayout. `APP_ARGS="-overview.cpu NO"` / `APP_ENV="BAM_NO_GLASS=1"` for A/B runs |
| `scripts/make-icon.sh` | Regenerates the app icon (`Resources/AppIcon.icns` + `Resources/AppIcon.icon`) from `scripts/make-icon.swift` |
| `scripts/cputime.sh <pid>` | Total CPU seconds a process has used |

Developer environment variables:

- `BAM_START_SECTION=<overview|processes|cpu|memory|disks|network|sensors|battery>` opens the app on that screen.
- `BAM_RESIZE_BENCH=<report>` runs the resize benchmark and quits (`BAM_RESIZE_FRAMES`, `BAM_SNAPSHOT_SECTIONS`).
- `BAM_NO_GLASS=1` uses plain materials instead of Liquid Glass, for A/B profiling.
- `BAM_SNAPSHOT_DIR=<dir>` renders every screen to `<dir>/<section>-<w>x<h>.png`, writes `layout-report.txt` and quits. `BAM_SNAPSHOT_SIZES=900x560,1280x820` and `BAM_SNAPSHOT_SECTIONS=overview,cpu` narrow the run.

## Known limitations

- Without root, the kernel refuses per-process CPU/memory for other users' processes. These show "—".
- Temperatures and fans come from the SMC (`AppleSMC`). The keys vary by Mac model.
