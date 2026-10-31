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
[Contributing](docs/CONTRIBUTING.md)

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
- **Light on resources**: sampling is budgeted and benchmarked (see [CONTRIBUTING.md](docs/CONTRIBUTING.md)), so leaving
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

More on the build, tests and tooling in [CONTRIBUTING.md](docs/CONTRIBUTING.md).

## Permissions and limitations

- Without root, the kernel refuses per-process CPU and memory figures for other users' processes. These show "—".
  Signals and renice on such processes ask for an administrator password.
- Temperatures and fans come from the SMC (`AppleSMC`). The keys vary by Mac model, so some sensors may be
  missing on yours. Please [report it](https://github.com/lukasketzer/BetterActivityMonitor/issues/new).
- Connection data comes from the system's `nettop` tool, which runs only while a Network page that needs it is open.

## Roadmap

- [x] Network connections, listening sockets and connection log
- [ ] Desktop and Notification Center widgets
- [ ] More settings
- [ ] Notarized builds

Ideas and requests: [open an issue](https://github.com/lukasketzer/BetterActivityMonitor/issues/new).

## Contributing

Bug reports, ideas and pull requests are welcome. [CONTRIBUTING.md](docs/CONTRIBUTING.md) covers the project layout,
the tests and benchmarks to run before a pull request, the developer tooling and how releases are cut.

## License

[MIT](LICENSE) © Lukas Ketzer. BetterActivityMonitor isn't affiliated with Apple. Activity Monitor is a
trademark of Apple Inc.
