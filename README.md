<div align="center">

<img src="docs/icon.png" width="128" height="128" alt="BetterActivityMonitor icon">

# BetterActivityMonitor

**A native macOS system monitor with btop's depth and Activity Monitor's polish.**

CPU per core (P/E), GPU, memory, network connections, disks, temperatures, fans and battery, plus a fast
process table with a tree view, signals, renice and an inspector. Built with SwiftUI, AppKit and Liquid Glass.

[![CI](https://github.com/lukasketzer/BetterActivityMonitor/actions/workflows/ci.yml/badge.svg)](https://github.com/lukasketzer/BetterActivityMonitor/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/lukasketzer/BetterActivityMonitor?sort=semver)](https://github.com/lukasketzer/BetterActivityMonitor/releases/latest)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

[**Download**](https://github.com/lukasketzer/BetterActivityMonitor/releases/latest) ·
[Features](#features) ·
[Build from source](#build-from-source) ·
[Development](#development)

<br>

<img src="docs/screenshots/overview.png" alt="Overview: CPU, GPU, memory, network, disk and sensor cards above the process list">

</div>

## Screenshots

| | |
|:---:|:---:|
| <img src="docs/screenshots/processes.png" alt="Processes"><br>**Processes** | <img src="docs/screenshots/cpu.png" alt="CPU"><br>**CPU** |
| <img src="docs/screenshots/memory.png" alt="Memory"><br>**Memory** | <img src="docs/screenshots/network.png" alt="Network"><br>**Network** |
| <img src="docs/screenshots/disks.png" alt="Disks"><br>**Disks** | <img src="docs/screenshots/sensors.png" alt="GPU & Sensors"><br>**GPU & Sensors** |

## Features

- **Overview**: one dashboard with CPU, GPU, memory, network, disk and sensor cards above a live process list.
  You choose which cards show.
- **Processes**: a native `NSTableView` that stays smooth with 1000+ processes.
  - Sort by any column. Filter as you type, with plain text or regular expressions.
  - Scopes: all, mine, apps, system, active.
  - Tree view with collapsible subtrees; a collapsed parent shows its subtree's CPU and memory, like btop.
  - Send any signal, renice, and open an inspector per process. Asks for admin rights only when the target belongs to another user.
- **CPU**: total, user and system load, with a graph per core labelled performance or efficiency, plus load
  averages, top CPU consumers and CPU temperature.
- **Memory**: app, wired, compressed and cached memory, memory pressure and swap.
- **Network**: throughput per interface. The **Connections**, **Listening** and **Log** pages show every
  TCP/UDP/QUIC flow per process, with service names, address scope, RTT and retransmits. Filter them with tokens like
  `proc:safari port:443 scope:internet`.
- **Disks**: per-volume usage and read/write throughput.
- **GPU & Sensors**: GPU renderer, tiler and memory use; SMC temperatures and fan speeds.
- **Battery**: charge, health, cycle count, power draw and time remaining.
- **Menu bar**: optional CPU, memory and network readouts in the menu bar.
- **Looks**: Liquid Glass on macOS 26, plus themes (System, btop, Nord, Dracula, …), graph styles (area, line,
  bars) and °C/°F.
- **Light on resources**: sampling is budgeted and benchmarked (see [Development](#development)), so leaving
  the app open costs little.

## Install

1. Download `BetterActivityMonitor-<version>.dmg` from the
   [latest release](https://github.com/lukasketzer/BetterActivityMonitor/releases/latest).
2. Open it and drag **BetterActivityMonitor** to **Applications**.
3. **First launch:** releases without notarization are ad-hoc signed, so Gatekeeper blocks a plain double-click.
   Right-click the app → **Open** (on macOS 15+: *System Settings → Privacy & Security → Open Anyway*), or run:

   ```sh
   xattr -dr com.apple.quarantine /Applications/BetterActivityMonitor.app
   ```

Requires macOS 14 Sonoma or later on Apple Silicon. Liquid Glass needs macOS 26; older systems get standard
materials. Each release lists its `SHA256SUMS`.

## Build from source

You need Xcode 26 or later (for the macOS 26 SDK).

```sh
git clone https://github.com/lukasketzer/BetterActivityMonitor.git
cd BetterActivityMonitor
scripts/bundle.sh                     # release build → build/BetterActivityMonitor.app (ad-hoc signed)
open build/BetterActivityMonitor.app
```

`bundle.sh` restamps the binary with the installed SDK version (`vtool`). SwiftPM otherwise stamps
SDK 14.0, which makes macOS fall back to the legacy window chrome.

`VERSION=0.1.0 scripts/package.sh` also builds the release DMG and zip, plus `SHA256SUMS`, in `build/`.

## Permissions and limitations

- Without root, the kernel refuses per-process CPU and memory figures for other users' processes. These show "—".
  Signals and renice on such processes ask for an administrator password.
- Temperatures and fans come from the SMC (`AppleSMC`). The keys vary by Mac model, so some sensors may be
  missing on yours. Please [report it](https://github.com/lukasketzer/BetterActivityMonitor/issues/new?template=bug_report.yml).
- Connection data comes from the system's `nettop` tool, which runs only while a Network page that needs it is open.

## Roadmap

- [x] Network connections, listening sockets and connection log
- [ ] Desktop and Notification Center widgets
- [ ] More settings
- [ ] Notarized builds

Ideas and requests: [open an issue](https://github.com/lukasketzer/BetterActivityMonitor/issues/new/choose).

## Development

Layout:
- `Sources/SystemKit` holds the data samplers, with no UI code.
- `Sources/BetterActivityMonitor` is the app.
- `Sources/sysbench` benchmarks the samplers.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow and how to cut a release.

### Tests

| Command | What it checks |
|---|---|
| `swift test -c release --skip AppPerformanceTests` | Everything below except the opt-in app tests. CI runs it without `SamplerPerformanceTests` |
| `swift test -c release --filter AppModelTests` | App logic: formatting, graph history, process tree and filters, connection rows and filter syntax |
| `swift test -c release --filter SamplerTests` | Sanity checks: values in range, own PID visible, counters monotonic |
| `swift test -c release --filter NettopParserTests` | `nettop` output parsing, address scopes, service names |
| `swift test -c release --filter SamplerPerformanceTests` | Sampler budgets: CPU ms per tick, per-sampler medians, sensor throttling |
| `scripts/bundle.sh && BAM_APP_PERF=1 swift test -c release --filter AppCPUTests` | Launches the bundled app on each screen and asserts its CPU % stays under a budget (opt-in, about 2 min) |
| `scripts/bundle.sh && BAM_APP_LAYOUT=1 swift test -c release --filter AppLayoutTests` | Renders every screen at 900×560, 1100×700 and 1400×900 and fails on overlapping cards, content spilling out of a card or horizontal clipping |

Run the performance tests in release mode. Debug builds are several times slower.

### Profiling & benchmarking tools

| Tool | Use |
|---|---|
| `swift run -c release sysbench` | Median/max time of every sampler and CPU ms per tick |
| `swift run -c release sysbench nettop [seconds]` | CPU cost of the Network tab's connection data: one `nettop` run per tick vs. its streaming mode, and `SystemMonitor` per tick in each `ConnectionMode` (own + nettop CPU) |
| `scripts/measure-screens.sh [seconds] [screen …]` | App CPU % per screen with its window frontmost (`APP_ENV="K=V"` passes env to the app). Network pages as `network:connections`, `network:listening`, `network:log` (or `BAM_NETWORK_PAGE=…`); nettop's own CPU isn't included, see `sysbench nettop` |
| `scripts/hot-frames.sh [seconds] [regex]` | `sample`s the newest running instance (`PID=` to pick one) and prints the heaviest app/UI frames |
| `scripts/check-layout.sh [out-dir] [sizes] [sections]` | Same layout audit by hand; PNGs + `layout-report.txt` land in `build/layout` |
| `scripts/resize-bench.sh [screens] [frames]` | Times every window-resize frame (layout + display) per screen: median / p95 / max ms, frames over the 16.7 ms 60 fps budget. Freezing during resize is on by default; `APP_ARGS="-freezeDuringResize NO"` measures live relayout. `APP_ARGS="-overview.cpu NO"` / `APP_ENV="BAM_NO_GLASS=1"` for A/B runs |
| `scripts/screenshots.sh [out-dir] [sections]` | Captures the README screenshots (real window with Liquid Glass and shadow) into `docs/screenshots`. `SETTLE` = seconds per screen before capture (default 90, so graphs fill), `SIZE` = window size (default 1280x820). Needs Screen Recording permission for the terminal |
| `scripts/package.sh` | Release DMG + zip + `SHA256SUMS`; Developer ID signing and notarization when `DEVELOPER_ID` / `NOTARY_*` are set |
| `scripts/make-icon.sh` | Regenerates the app icon (`Resources/AppIcon.icns` + `Resources/AppIcon.icon`) from `scripts/make-icon.swift` |
| `scripts/cputime.sh <pid>` | Total CPU seconds a process has used |

Developer environment variables:

- `BAM_START_SECTION=<overview|processes|cpu|memory|disks|network|sensors|battery>` opens the app on that screen.
- `BAM_RESIZE_BENCH=<report>` runs the resize benchmark and quits (`BAM_RESIZE_FRAMES`, `BAM_SNAPSHOT_SECTIONS`).
- `BAM_NO_GLASS=1` uses plain materials instead of Liquid Glass, for A/B profiling.
- `BAM_SNAPSHOT_DIR=<dir>` renders every screen to `<dir>/<section>-<w>x<h>.png`, writes `layout-report.txt` and quits. `BAM_SNAPSHOT_SIZES=900x560,1280x820` and `BAM_SNAPSHOT_SECTIONS=overview,cpu` narrow the run.

### Releasing

Pushing a `v*` tag runs [`release.yml`](.github/workflows/release.yml). It tests, packages and publishes a
GitHub Release with the DMG, zip and checksums. The notes come from that version's `CHANGELOG.md` section, followed
by auto-generated notes. A tag with a suffix, like `v0.2.0-beta.1`, becomes a pre-release.

Builds are ad-hoc signed by default. To ship signed and notarized builds, add these repository secrets:

| Secret | Value |
|---|---|
| `DEVELOPER_ID_CERT_P12` | `base64 -i cert.p12` of your *Developer ID Application* certificate |
| `DEVELOPER_ID_CERT_PASSWORD` | Password of that `.p12` |
| `NOTARY_APPLE_ID` | Apple ID email used for notarization |
| `NOTARY_TEAM_ID` | Your 10-character team ID |
| `NOTARY_PASSWORD` | An [app-specific password](https://support.apple.com/102654) for that Apple ID |

## License

[MIT](LICENSE) © Lukas Ketzer. BetterActivityMonitor isn't affiliated with Apple. Activity Monitor is a
trademark of Apple Inc.
