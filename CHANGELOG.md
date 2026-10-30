# Changelog

All notable changes to this project. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/). The release workflow copies the section of the
tagged version into the GitHub Release notes.

## [Unreleased]

## [0.1.0]

First public release.

### Added

- Overview dashboard with CPU, GPU, memory, network, disk and sensor cards above a live process list.
- Process table (NSTableView) with sorting, search (plain or regex), scopes, tree view with collapsible subtrees,
  signals, renice (asking for admin rights when needed) and an inspector.
- CPU screen with per-core P/E graphs, load averages and CPU temperature.
- Memory screen with app / wired / compressed / cached breakdown, pressure and swap.
- Network screen with per-interface throughput, plus Connections, Listening and Log pages built on `nettop`.
- Disks, GPU & sensors (SMC temperatures and fans) and battery screens.
- Menu bar extra with CPU, memory and network readouts.
- Themes (System, btop, Nord, Dracula, …), graph styles and Liquid Glass on macOS 26.
