<div align="center">

<img src="docs/icon.png" width="128" height="128" alt="BetterActivityMonitor icon">

# BetterActivityMonitor

**A native macOS system monitor with btop's depth and Activity Monitor's polish.**

See what your Mac is doing at a glance: CPU, GPU, memory, network, disks, temperatures, fans and battery,
plus a fast process list that lets you find, inspect and stop any app.

[![CI](https://github.com/lukasketzer/BetterActivityMonitor/actions/workflows/ci.yml/badge.svg)](https://github.com/lukasketzer/BetterActivityMonitor/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/lukasketzer/BetterActivityMonitor?sort=semver)](https://github.com/lukasketzer/BetterActivityMonitor/releases/latest)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

[**Download**](https://github.com/lukasketzer/BetterActivityMonitor/releases/latest) ·
[Features](#features) ·
[Build from source](#build-from-source) ·
[Contributing](docs/CONTRIBUTING.md)

<br>

<img src="docs/screenshots/overview.png" alt="Overview: CPU, GPU, memory, network, disk and sensor cards above the process list">

</div>

## Screenshots

| | |
|:---:|:---:|
| <img src="docs/screenshots/processes.png" alt="Processes"><br>**Processes** | <img src="docs/screenshots/cpu.png" alt="CPU"><br>**CPU** |
| <img src="docs/screenshots/memory.png" alt="Memory"><br>**Memory** | <img src="docs/screenshots/network.png" alt="Network: apps listening for connections"><br>**Network: listening apps** |

## Features

- **Everything on one screen**: the Overview puts CPU, GPU, memory, network, disks and temperatures above a live
  list of what's running. Pick the cards you want to see.
- **Find and control any process**: sort by what's using the most, search as you type, or show just your apps.
  See which process started which in a tree view. Quit, force quit or pause a process, change its priority,
  or open it for a closer look.
- **CPU in detail**: overall load, a graph for every core, and the CPU temperature, so you see what's slowing
  your Mac down.
- **Memory at a glance**: how much is in use, by what, and whether your Mac is running out.
- **See who's online**: live download and upload speeds, which apps are connected to where, which apps are
  waiting for connections, and a log of connections as they come and go.
- **Disks**: free space on each drive, and how fast data is being read and written.
- **Temperatures and fans**: CPU, GPU, battery and SSD temperatures, plus fan speeds.
- **Battery**: charge, health, charge cycles, power use and time remaining.
- **Desktop widgets**: put live CPU, GPU, memory, disk, battery and uptime widgets on your desktop or in
  Notification Center: rings, bars, or graphs of the last day. Edit a widget to choose its metrics; click it to
  jump to that screen.
- **Menu bar**: a compact menu bar item that looks like the system's own. Show the metrics you pick as rings,
  percentages or absolute values (like memory in use or battery time left), in the order you like.
- **Make it yours**: the glassy macOS 26 look, color themes (including btop, Nord and Dracula), several graph
  styles, and °C or °F.
- **Light on your Mac**: built to stay cheap to leave open all day.

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

### Nightly builds

`main` is built every night it has new changes and published as the
[nightly release](https://github.com/lukasketzer/BetterActivityMonitor/releases/tag/nightly), versioned like
`0.2.0-nightly.20261031`. Nightlies have the newest features before they are released, and may be rough. What's new
since the last release is in the [changelog](docs/CHANGELOG.md) under *Unreleased*.

## Build from source

You need Xcode 26 or later (for the macOS 26 SDK).

```sh
git clone https://github.com/lukasketzer/BetterActivityMonitor.git
cd BetterActivityMonitor
scripts/build-app.sh                  # release build with widgets → build/xcode/Release/BetterActivityMonitor.app
open build/xcode/Release/BetterActivityMonitor.app
```

You can also open `BetterActivityMonitor.xcodeproj` in Xcode. `scripts/bundle.sh` makes a quicker SwiftPM build
without the widgets.

More on the build, tests and tooling in [CONTRIBUTING.md](docs/CONTRIBUTING.md).

## Permissions and limitations

- Without root, the kernel refuses per-process CPU and memory figures for other users' processes. These show "—".
  Signals and renice on such processes ask for an administrator password.
- Temperatures and fans come from the SMC (`AppleSMC`). The keys vary by Mac model, so some sensors may be
  missing on yours. Please [report it](https://github.com/lukasketzer/BetterActivityMonitor/issues/new).
- Connection data comes from the system's `nettop` tool, which runs only while a Network page that needs it is open.

## Roadmap

- [x] Network connections, listening sockets and connection log
- [x] Desktop and Notification Center widgets
- [x] Customizable menu bar item
- [ ] More settings
- [ ] Notarized builds

Ideas and requests: [open an issue](https://github.com/lukasketzer/BetterActivityMonitor/issues/new).

## Contributing

Bug reports, ideas and pull requests are welcome. [CONTRIBUTING.md](docs/CONTRIBUTING.md) covers the project layout,
the tests and benchmarks to run before a pull request, the developer tooling and how releases are cut.

## License

[MIT](LICENSE) © Lukas Ketzer. BetterActivityMonitor isn't affiliated with Apple. Activity Monitor is a
trademark of Apple Inc.
