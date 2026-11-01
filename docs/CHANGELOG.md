# Changelog

All notable changes to this project. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/). The release workflow copies the section of the
tagged version into the GitHub Release notes; nightly builds show the `Unreleased` section.

## [Unreleased]

### Added

- Desktop and Notification Center widgets: System Overview, System Stats, System Rings, History Graph and
  Activity Graphs (the last day), Activity Stats, Memory, Storage, Uptime and Battery (the medium size adds
  charger and power details). Edit a widget to choose its metrics; click it to open that screen in the app.
- A new menu bar item that looks like the system's own icons. Show your metrics as rings, percentages or absolute
  values (load, memory and disk in use, battery time left), pick which ones and their order, and preview it in
  Settings. CPU, memory, GPU, startup disk, battery, CPU temperature and network are available.
- History: turn on Settings → History and a small background agent records a summary of every minute (CPU,
  memory, GPU, network, disk, power, temperatures and the busiest apps), also while the app is closed. The CPU,
  Memory, Disks, Network, GPU & Sensors, Battery and Energy pages get a Live / 1h / 24h / 7d / 30d switch for their
  graphs and top lists. Keeps 1, 7 or 30 days on this Mac; the agent uses under 0.1% of one core.
- Energy page: power per app (helpers count toward their app), what keeps the Mac awake, and Power and Energy
  columns in the process list.
- Network columns in the process list (received and sent per second and in total) and a Top Apps card on the
  Network page.
- Set the update interval in milliseconds from the toolbar, like btop: click − / + or type a value (100–10 000 ms).
- Nightly builds of the latest changes on the [nightly release](https://github.com/lukasketzer/BetterActivityMonitor/releases/tag/nightly).

### Changed

- The menu bar item no longer changes width as its numbers change, and stays monochrome unless you turn on theme
  colors. Your earlier CPU, memory and network choices carry over.
- A new app icon: a graphite chip whose screen shows the CPU Load graph, in Activity Monitor's red and blue.

## [0.1.0]

First public release.

### Added

- Overview with CPU, GPU, memory, network, disk and temperature cards above a live list of what's running.
- Process list: sort, search, show just your apps, a tree view, and quit, pause or reprioritize any process.
- CPU screen with a graph for every core and the CPU temperature.
- Memory screen showing what uses your memory and whether your Mac is running low.
- Network screen with download and upload speeds, the connections each app has open, apps waiting for
  connections, and a connection log.
- Disks, temperatures and fans, and battery screens.
- Optional CPU, memory and network readouts in the menu bar.
- The glassy macOS 26 look, color themes and several graph styles.
