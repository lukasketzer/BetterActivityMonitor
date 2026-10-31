# Contributing to BetterActivityMonitor

Thanks for helping out! Bug reports, feature ideas and pull requests are all welcome. This page covers how to
report problems, set up the project, find your way around the code, and check a change before you send it.

- [Reporting bugs and requesting features](#reporting-bugs-and-requesting-features)
- [Setting up](#setting-up)
- [Project layout](#project-layout)
- [Making a change](#making-a-change)
- [Tests](#tests)
- [Profiling and benchmarking](#profiling-and-benchmarking)
- [Developer environment variables](#developer-environment-variables)
- [Releasing](#releasing)

## Reporting bugs and requesting features

[Open an issue](https://github.com/lukasketzer/BetterActivityMonitor/issues/new). For a bug, please include:

- what you saw and what you expected, with steps to reproduce it and a screenshot if it's visual;
- the app version (*BetterActivityMonitor → About*);
- your Mac model and chip, and the macOS version. Sensor keys differ between models, so this matters for
  temperature, fan and GPU readings;
- for a crash, the report from *Console.app → Crash Reports*.

For a feature request, describe the problem it solves and how you picture it working. Check the
[roadmap](README.md#roadmap) and the open issues first, in case it's already planned.

## Setting up

You need macOS 14 or later and Xcode 26 or later (the Liquid Glass APIs need the macOS 26 SDK).

```sh
git clone https://github.com/lukasketzer/BetterActivityMonitor.git
cd BetterActivityMonitor
scripts/bundle.sh                     # release build → build/BetterActivityMonitor.app (ad-hoc signed)
open build/BetterActivityMonitor.app
```

`bundle.sh` restamps the binary with the installed SDK version (`vtool`). SwiftPM otherwise stamps SDK 14.0,
which makes macOS fall back to the legacy window chrome. `swift run BetterActivityMonitor` works for quick
iterations, but only the bundled app gets the right icon and window chrome. `scripts/bundle.sh debug` builds a
debug bundle.

## Project layout

| Path | What's in it |
|---|---|
| `Sources/SystemKit` | Data samplers: CPU, memory, processes, disks, network, `nettop` connections, GPU, SMC sensors, battery. No UI code; usable as a library |
| `Sources/BetterActivityMonitor` | The SwiftUI/AppKit app: `Model/` (store, settings, formatting, row building), `Views/` (one file per screen), `Components/` (cards, charts, glass) |
| `Sources/sysbench` | CLI that benchmarks the samplers |
| `Tests/SystemKitTests` | Sampler sanity checks, `nettop` parsing, sampler performance budgets |
| `Tests/AppModelTests` | The app's pure logic, via `@testable import BetterActivityMonitor` |
| `Tests/AppPerformanceTests` | Opt-in tests that launch the bundled app (CPU budget per screen, layout audit) |
| `scripts/` | Bundling, packaging, screenshots, profiling and layout tools (see below) |
| `Resources/` | `Info.plist` and the app icon |

## Making a change

1. Fork the repo and create a branch from `main`.
2. Keep to the style of the surrounding code, and keep the pull request focused: one change per PR.
3. Add or update tests for logic changes. Pure logic belongs in `SystemKit` or in the app's `Model/`, where
   `SystemKitTests` / `AppModelTests` can reach it.
4. Run the checks below, and add a line under `Unreleased` in [CHANGELOG.md](CHANGELOG.md) for user-visible changes.
5. Open the pull request. The template has a checklist; attach screenshots for visible changes.

The app has to stay cheap to leave running, so changes to samplers or per-tick UI code should come with
before/after numbers from `sysbench` or `measure-screens.sh`. When you add a check, make it a script or test in
the repo rather than a one-off command.

Before you open the pull request:

```sh
swift test -c release --skip AppPerformanceTests   # unit tests + sampler budgets
scripts/check-layout.sh                            # UI changes: no overlapping or clipped cards
swift run -c release sysbench                      # sampler changes: compare against main
scripts/measure-screens.sh                         # UI hot paths: app CPU % per screen
```

CI runs the build, the unit tests (without the timing budgets, which are too noisy on shared runners) and
`bundle.sh` on every push and pull request.

## Tests

| Command | What it checks |
|---|---|
| `swift test -c release --skip AppPerformanceTests` | Everything below except the opt-in app tests |
| `swift test -c release --filter AppModelTests` | App logic: formatting, graph history, process tree and filters, connection rows and filter syntax |
| `swift test -c release --filter SamplerTests` | Sanity checks: values in range, own PID visible, counters monotonic |
| `swift test -c release --filter NettopParserTests` | `nettop` output parsing, address scopes, service names |
| `swift test -c release --filter SamplerPerformanceTests` | Sampler budgets: CPU ms per tick, per-sampler medians, sensor throttling |
| `scripts/bundle.sh && BAM_APP_PERF=1 swift test -c release --filter AppCPUTests` | Launches the bundled app on each screen and asserts its CPU % stays under a budget (opt-in, about 2 min) |
| `scripts/bundle.sh && BAM_APP_LAYOUT=1 swift test -c release --filter AppLayoutTests` | Renders every screen at 900×560, 1100×700 and 1400×900 and fails on overlapping cards, content spilling out of a card or horizontal clipping |

Run the performance tests in release mode. Debug builds are several times slower.

## Profiling and benchmarking

| Tool | Use |
|---|---|
| `swift run -c release sysbench` | Median/max time of every sampler and CPU ms per tick |
| `swift run -c release sysbench nettop [seconds]` | CPU cost of the Network tab's connection data: one `nettop` run per tick vs. its streaming mode, and `SystemMonitor` per tick in each `ConnectionMode` (own + nettop CPU) |
| `scripts/measure-screens.sh [seconds] [screen …]` | App CPU % per screen with its window frontmost (`APP_ENV="K=V"` passes env to the app). Network pages as `network:connections`, `network:listening`, `network:log` (or `BAM_NETWORK_PAGE=…`); nettop's own CPU isn't included, see `sysbench nettop` |
| `scripts/hot-frames.sh [seconds] [regex]` | `sample`s the newest running instance (`PID=` to pick one) and prints the heaviest app/UI frames |
| `scripts/check-layout.sh [out-dir] [sizes] [sections]` | Same layout audit by hand; PNGs + `layout-report.txt` land in `build/layout` |
| `scripts/resize-bench.sh [screens] [frames]` | Times every window-resize frame (layout + display) per screen: median / p95 / max ms, frames over the 16.7 ms 60 fps budget. Freezing during resize is on by default; `APP_ARGS="-freezeDuringResize NO"` measures live relayout. `APP_ARGS="-overview.cpu NO"` / `APP_ENV="BAM_NO_GLASS=1"` for A/B runs |
| `scripts/screenshots.sh [out-dir] [sections]` | Captures the README screenshots (real window with Liquid Glass and shadow) into `docs/screenshots`. `SETTLE` = seconds per screen before capture (default 90, so graphs fill), `SIZE` = window size (default 1280x820), `APP_ARGS` / `APP_ENV` for launch args and env. Needs Screen Recording permission for the terminal and the desktop Space to stay visible |
| `scripts/package.sh` | Release DMG + zip + `SHA256SUMS` in `build/`; Developer ID signing and notarization when `DEVELOPER_ID` / `NOTARY_*` are set |
| `scripts/make-icon.sh` | Regenerates the app icon (`Resources/AppIcon.icns` + `Resources/AppIcon.icon`) from `scripts/make-icon.swift` |
| `scripts/cputime.sh <pid>` | Total CPU seconds a process has used |

## Developer environment variables

- `BAM_START_SECTION=<overview|processes|cpu|memory|disks|network|sensors|battery>` opens the app on that screen.
- `BAM_NETWORK_PAGE=<overview|connections|listening|log>` opens the Network screen on that page.
- `BAM_RESIZE_BENCH=<report>` runs the resize benchmark and quits (`BAM_RESIZE_FRAMES`, `BAM_SNAPSHOT_SECTIONS`).
- `BAM_NO_GLASS=1` uses plain materials instead of Liquid Glass, for A/B profiling.
- `BAM_SNAPSHOT_DIR=<dir>` renders every screen to `<dir>/<section>-<w>x<h>.png`, writes `layout-report.txt` and
  quits. `BAM_SNAPSHOT_SIZES=900x560,1280x820` and `BAM_SNAPSHOT_SECTIONS=overview,cpu` narrow the run.

## Releasing

1. Move the `Unreleased` entries in `CHANGELOG.md` under a new version heading.
2. Bump `CFBundleShortVersionString` in `Resources/Info.plist`.
3. Tag and push: `git tag v0.2.0 && git push origin v0.2.0`.

The tag runs [`release.yml`](.github/workflows/release.yml). It tests, packages and publishes a GitHub Release
with the DMG, zip and checksums. The notes come from that version's `CHANGELOG.md` section, followed by
auto-generated notes. A tag with a suffix, like `v0.2.0-beta.1`, becomes a pre-release.
`VERSION=0.2.0 scripts/package.sh` builds the same artifacts locally.

Builds are ad-hoc signed by default. To ship signed and notarized builds, add these repository secrets:

| Secret | Value |
|---|---|
| `DEVELOPER_ID_CERT_P12` | `base64 -i cert.p12` of your *Developer ID Application* certificate |
| `DEVELOPER_ID_CERT_PASSWORD` | Password of that `.p12` |
| `NOTARY_APPLE_ID` | Apple ID email used for notarization |
| `NOTARY_TEAM_ID` | Your 10-character team ID |
| `NOTARY_PASSWORD` | An [app-specific password](https://support.apple.com/102654) for that Apple ID |
