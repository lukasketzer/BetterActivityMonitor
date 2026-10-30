# Contributing

Thanks for helping out! Bug reports, feature ideas and pull requests are all welcome.

## Setup

You need macOS 14 or later and Xcode 26 or later (the Liquid Glass APIs need the macOS 26 SDK).

```sh
git clone https://github.com/lukasketzer/BetterActivityMonitor.git
cd BetterActivityMonitor
scripts/bundle.sh && open build/BetterActivityMonitor.app
```

`swift run BetterActivityMonitor` works too, but only the bundled app gets the right icon and window chrome.

## Layout

- `Sources/SystemKit`: the data samplers (CPU, memory, processes, network, SMC, …). No UI code.
- `Sources/BetterActivityMonitor`: the SwiftUI/AppKit app.
- `Sources/sysbench`: a benchmark CLI for the samplers.
- `Tests/SystemKitTests`, `Tests/AppModelTests`: unit tests. `Tests/AppPerformanceTests`: opt-in tests that launch
  the bundled app.

## Before opening a pull request

```sh
swift test -c release --skip AppPerformanceTests   # unit tests + sampler budgets
scripts/check-layout.sh                            # UI changes: no overlapping or clipped cards
swift run -c release sysbench                      # sampler changes: compare against main
scripts/measure-screens.sh                         # UI hot paths: app CPU % per screen
```

The app has to stay cheap to leave running, so changes to samplers or per-tick UI code should come with
before/after numbers from `sysbench` or `measure-screens.sh`. When you add a check, make it a script or test in the
repo rather than a one-off command.

Keep to the style of the surrounding code, and keep pull requests focused: one change per PR.

## Releasing

1. Move the `Unreleased` entries in `CHANGELOG.md` under a new version heading.
2. Bump `CFBundleShortVersionString` in `Resources/Info.plist`.
3. Tag and push: `git tag v0.2.0 && git push origin v0.2.0`. The Release workflow tests, packages and publishes
   the DMG and zip.
