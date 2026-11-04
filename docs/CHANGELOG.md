# Changelog

All notable changes to this project. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/). The release workflow copies the section of the
tagged version into the GitHub Release notes.

## [Unreleased]

## [0.4.1] - 2026-11-04

0.4.0 was never published, because its release build failed. 0.4.1 is the first release with the 0.4.0 changes
listed below: the menu bar without the window, Open at login, GPU use by process, the System page details and the
network log inspector.

### Fixed

- GPU by Process no longer lists processes that opened the GPU but never used it. On virtual Macs, where every
  process reports no GPU time, the list stays empty.

## [0.4.0] - 2026-11-04

### Added

- The app can run from the menu bar alone. With Settings ▸ Menu Bar ▸ Show in menu bar on, closing the window keeps
  the menu bar item running without a Dock icon; Open Monitor in its popover brings the window back.
- Settings ▸ Menu Bar ▸ Open at login. Opened at login, the app starts with only the menu bar item.
- The GPU page lists the processes that use the GPU, busiest first, with their share of the GPU and total GPU time.
- The System page shows the Mac's model name, boot and last wake times, thermal state and Low Power Mode, and has a
  Copy System Info button.
- Selecting an event in the network log opens an inspector with both endpoints, reverse DNS, traffic, lifetime and
  the matching open or close event, with shortcuts to filter the log or reveal the process.

### Changed

- Every desktop widget now has an update speed (right-click ▸ Edit Widget), from every 2 seconds to every 15 minutes.
- With the menu bar item on, ⌘Q closes the windows to the menu bar; ⌥⌘Q, or Quit in the popover, quits.

### Removed

- The Memory Pressure stat, from the Memory page and the menu bar.

## [0.3.0] - 2026-11-02

### Added

- Settings ▸ General ▸ Sidebar lets you choose which pages appear in the sidebar. The Temperatures page is off by default.

- Press `/` in the process list to jump into the search field.
- New System page in the style of About This Mac: the Mac's name and macOS version above its hardware and
  software details (chip, memory, disk, display, battery, kernel, uptime, address). The CPU temperature chart and fans moved there from the CPU and Temperatures pages.
- The Cores panel on the CPU page, the Virtual Memory panel on the Memory page and each sensor list on the Temperatures page are now
  collapsed by default and sit at the bottom of their page as compact rows. Click the header to expand one; the app remembers which are open.

### Changed

- "GPU & Sensors" is split into a GPU page (load, renderer, tiler, memory, temperature) and a Temperatures page (all sensors, grouped by component).

- A calmer Overview: rings show CPU, GPU, memory, storage (startup disk) and battery, and two cards graph network and disk activity. Click any of them for the details. The
  process list moved off the Overview; it stays on the Processes page.
- Battery and Energy are one page, Battery & Energy. Links to the old Battery page open it.
- Lists keep their height while their contents change: Top Apps, Top CPU, Top Memory, Top Disk Activity, Power by App,
  Preventing Sleep, Interfaces, Volumes and Devices reserve room for a fixed number of
  rows and scroll past it, so the panels below no longer jump.

### Removed

- The menu bar popover no longer lists top processes. Their per-core CPU percentages didn't match the total above them.
- Widget history: the History Graph and Activity Graphs widgets are gone, System Overview shows level bars instead of
  charts (it replaces System Stats), and the app no longer writes history to the shared App Group container.

## [0.2.0] - 2026-11-01

### Added

- Desktop and Notification Center widgets: System Overview, System Stats, System Rings, History Graph and
  Activity Graphs (the last day), Activity Stats, Memory, Storage, Uptime and Battery (the medium size adds
  charger and power details). Edit a widget to choose its metrics; click it to open that screen in the app.
- A new menu bar item that looks like the system's own icons. Show your metrics as rings, percentages or absolute
  values (load, memory and disk in use, battery time left), pick which ones and their order, and preview it in
  Settings. CPU, memory, GPU, startup disk, battery, CPU temperature and network are available.
- Nightly builds of the latest changes on the [nightly release](https://github.com/lukasketzer/BetterActivityMonitor/releases/tag/nightly).
- Network use per process: download and upload speed and totals as optional columns in the process list, a Top Apps
  card on the Network screen, and network details in the process inspector.
- An Energy screen: how much power each app uses (helpers counted under their app), and which apps keep your Mac
  awake.
- Choose how often the app updates, from 500 ms to 1 min, in Settings, the View menu or with ⌘+ / ⌘−.

### Changed

- The menu bar item no longer changes width as its numbers change, and stays monochrome unless you turn on theme
  colors. Your earlier CPU, memory and network choices carry over.
- A new app icon: a graphite chip whose screen shows the CPU Load graph, in Activity Monitor's red and blue.
- Graph tooltips float above the window instead of inside their card, so they're never cut off or covered.

### Fixed

- Hovering a small graph no longer makes it jump sideways.

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
