import AppKit
import SwiftUI
import Observation
import SystemKit

enum AppSection: String, CaseIterable, Identifiable {
    case overview, processes, cpu, memory, disks, network, sensors, battery, energy, system
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .processes: "Processes"
        case .cpu: "CPU"
        case .memory: "Memory"
        case .disks: "Disks"
        case .network: "Network"
        case .sensors: "GPU & Sensors"
        case .battery: "Battery"
        case .energy: "Energy"
        case .system: "System"
        }
    }

    /// ⌘1…⌘9, then ⌘0 for the tenth section. A two-digit `Character` would trap.
    static func shortcut(index: Int) -> KeyEquivalent {
        KeyEquivalent(Character(String((index + 1) % 10)))
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .processes: "list.bullet.rectangle"
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disks: "internaldrive"
        case .network: "network"
        case .sensors: "thermometer.medium"
        case .battery: "battery.75percent"
        case .energy: "bolt.fill"
        case .system: "desktopcomputer"
        }
    }
}

/// Parts of the app that need `nettop` data.
enum ConnectionConsumer: Hashable {
    case networkPage, processTable
}

/// Combines what each consumer asks for into one connection mode.
struct ConnectionDemand {
    private(set) var modes: [ConnectionConsumer: ConnectionMode] = [:]

    var effective: ConnectionMode { modes.values.max() ?? .off }

    /// Returns whether the effective mode changed.
    mutating func set(_ mode: ConnectionMode, for consumer: ConnectionConsumer) -> Bool {
        let before = effective
        modes[consumer] = mode == .off ? nil : mode
        return effective != before
    }
}

struct PendingSignal: Identifiable {
    let id = UUID()
    let signal: ProcessControl.Signal
    let pids: [pid_t]
    let names: [String]
}

struct ControlError: Identifiable {
    let id = UUID()
    let message: String
    let retry: PendingSignal?
}

@MainActor
@Observable
final class SystemStore {
    private(set) var snapshot: SystemSnapshot?

    // Histories for graphs.
    private(set) var cpuUser = History(capacity: 120)
    private(set) var cpuSystem = History(capacity: 120)
    private(set) var cpuTotal = History(capacity: 120)
    private(set) var cores: [History] = []
    private(set) var memUsed = History(capacity: 120)
    private(set) var memApp = History(capacity: 120)
    private(set) var memWired = History(capacity: 120)
    private(set) var memCompressed = History(capacity: 120)
    private(set) var swapUsed = History(capacity: 120)
    private(set) var netIn = History(capacity: 120)
    private(set) var netOut = History(capacity: 120)
    private(set) var interfaceIn: [String: History] = [:]
    private(set) var interfaceOut: [String: History] = [:]
    private(set) var diskRead = History(capacity: 120)
    private(set) var diskWrite = History(capacity: 120)
    private(set) var gpu = History(capacity: 120)
    private(set) var cpuTemperature = History(capacity: 120)
    private(set) var batteryCharge = History(capacity: 120)
    private(set) var batteryPower = History(capacity: 120)
    /// Sum of per-process power, which works on desktops too (no battery telemetry there).
    private(set) var processPower = History(capacity: 120)
    private(set) var sensorMax: [String: Double] = [:]
    private(set) var processCPU: [pid_t: History] = [:]
    private(set) var processMemory: [pid_t: History] = [:]
    /// Opened/closed connections, newest first; only recorded while connection tracking is on.
    private(set) var connectionLog: [ConnectionEvent] = []
    var connectionLogPaused = false

    /// Processes as shown in tables; frozen while `paused`.
    private(set) var processes: [ProcessEntry] = []
    /// Bumped whenever `processes` changes; tables recompute rows only then.
    private(set) var processGeneration = 0
    private(set) var apps: [pid_t: AppInfo] = [:]

    // UI state shared between views and menu commands.
    var section: AppSection? = .overview
    var selection: Set<pid_t> = []
    var showInspector = false
    var paused = false
    /// True while the user drags the window edge; the detail area freezes and sampling pauses meanwhile.
    var isLiveResizing = false
    /// Set by ResizeBench to get the same behaviour without a real drag.
    var simulatedLiveResize = false
    var filterText = ""
    var collapsed: Set<pid_t> = []
    var pendingSignal: PendingSignal?
    var controlError: ControlError?

    @ObservationIgnored private let monitor = SystemMonitor()
    @ObservationIgnored private var connectionDemand = ConnectionDemand()
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var tickSleep: Task<Void, Error>?
    @ObservationIgnored private var intervalObserver: NSKeyValueObservation?
    @ObservationIgnored private var iconCache: [String: NSImage] = [:]
    /// Querying runningApplications is costly (KVO setup), so only refresh on launch/quit.
    @ObservationIgnored private var appsDirty = true
    let myUID = getuid()

    init() {
        Defaults.register()
        start()
        DebugSnapshot.store = self
        if let start = ProcessInfo.processInfo.environment["BAM_START_SECTION"].flatMap(AppSection.init(rawValue:)) {
            section = start  // developer aid for per-screen profiling
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.appsDirty = true }
            }
        }
        for (name, resizing) in [(NSWindow.willStartLiveResizeNotification, true), (NSWindow.didEndLiveResizeNotification, false)] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isLiveResizing = resizing }
            }
        }
    }

    func start() {
        guard loop == nil else { return }
        // A new interval takes effect at once instead of after the current (possibly 10 s) wait.
        intervalObserver = UserDefaults.standard.observe(\.refreshInterval) { [weak self] _, _ in
            Task { @MainActor in self?.tickSleep?.cancel() }
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                let started = ContinuousClock.now
                guard let monitor = self?.monitor else { return }
                let snapshot = await monitor.sample()
                // During a live resize only layout should run on the main thread; resume afterwards.
                if self?.simulatedLiveResize == true || NSApp.windows.contains(where: \.inLiveResize) {
                    try? await Task.sleep(for: .milliseconds(200))
                    continue
                }
                self?.apply(snapshot)
                // Fixed cadence: the time spent sampling counts toward the interval.
                await self?.sleepUntilNextTick(after: started)
            }
        }
    }

    /// Sleeps until `started + interval`. An interval change cancels the sleep, and the deadline is
    /// recomputed with the new value (sampling right away if it has already passed).
    private func sleepUntilNextTick(after started: ContinuousClock.Instant) async {
        while !Task.isCancelled {
            let deadline = started.advanced(by: .seconds(Defaults.refreshInterval))
            guard ContinuousClock.now < deadline else { return }
            let sleep = Task { try await Task.sleep(until: deadline, clock: .continuous) }
            tickSleep = sleep
            let finished = (try? await sleep.value) != nil
            tickSleep = nil
            if finished { return }
        }
    }

    /// The Sensors page needs every SMC key; elsewhere a cheap representative subset is read.
    func setDetailedSensors(_ on: Bool) {
        let monitor = monitor
        Task { await monitor.setDetailedSensors(on) }
    }

    /// Connection data spawns `nettop` every tick, so each consumer asks for it only while it needs it;
    /// the monitor runs the costliest mode any of them asks for.
    func requestConnections(_ mode: ConnectionMode, for consumer: ConnectionConsumer) {
        guard connectionDemand.set(mode, for: consumer) else { return }
        let effective = connectionDemand.effective
        let monitor = monitor
        Task { await monitor.setConnectionMode(effective) }
    }

    func releaseConnections(for consumer: ConnectionConsumer) { requestConnections(.off, for: consumer) }

    /// Number of process tables on screen; the Overview and Processes pages each show one.
    @ObservationIgnored private var visibleProcessTables = 0

    func processTableAppeared() {
        visibleProcessTables += 1
        processTableColumnsChanged()
    }

    func processTableDisappeared() {
        visibleProcessTables = max(visibleProcessTables - 1, 0)
        processTableColumnsChanged()
    }

    /// Per-process network columns need `nettop -P`, but only while a table shows one of them.
    func processTableColumnsChanged() {
        let needed = visibleProcessTables > 0 && ProcessTableController.showsNetworkColumns
        requestConnections(needed ? .processes : .off, for: .processTable)
    }

    func clearConnectionLog() { connectionLog = [] }

    var coreCount: Int { max(snapshot?.cpu.cores.count ?? 1, 1) }
    var cpuTemperatureNow: Double? { cpuTemperature.points.isEmpty ? nil : cpuTemperature.last }

    func process(_ pid: pid_t) -> ProcessEntry? {
        snapshot?.processes.first { $0.pid == pid } ?? processes.first { $0.pid == pid }
    }

    func icon(for row: ProcessRow) -> NSImage? {
        if let icon = apps[row.pid]?.icon { return icon }
        // Helpers inside an app bundle get the bundle's icon.
        guard let bundle = AppBundle.path(forExecutable: row.path) else { return nil }
        if let cached = iconCache[bundle] { return cached }
        let icon = Self.rasterize(NSWorkspace.shared.icon(forFile: bundle))
        iconCache[bundle] = icon
        return icon
    }

    /// Icons from NSWorkspace are multi-representation IconServices images; assigning one to an image view
    /// re-resolves a representation every time (it showed up as the table's top cost). A 32 px bitmap is free to assign.
    static func rasterize(_ image: NSImage?, side: CGFloat = 16) -> NSImage? {
        guard let image else { return nil }
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side * scale), pixelsHigh: Int(side * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return image }
        rep.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        let result = NSImage(size: rep.size)
        result.addRepresentation(rep)
        return result
    }

    // MARK: Sampling

    private func apply(_ s: SystemSnapshot) {
        let date = s.timestamp
        let capacity = Defaults.historyLength
        func push(_ history: inout History, _ value: Double) {
            history.capacity = capacity
            history.append(value, at: date)
        }

        // The very first sample has no previous tick to diff against.
        if snapshot != nil {
            push(&cpuUser, s.cpu.user)
            push(&cpuSystem, s.cpu.system)
            push(&cpuTotal, s.cpu.total)
            if cores.count != s.cpu.cores.count { cores = s.cpu.cores.map { _ in History(capacity: capacity) } }
            for (i, core) in s.cpu.cores.enumerated() { push(&cores[i], core.total) }
            push(&netIn, s.network.rateIn)
            push(&netOut, s.network.rateOut)
            for iface in s.network.interfaces {
                push(&interfaceIn[iface.name, default: History(capacity: capacity)], iface.rateIn)
                push(&interfaceOut[iface.name, default: History(capacity: capacity)], iface.rateOut)
            }
            push(&diskRead, s.disks.readRate)
            push(&diskWrite, s.disks.writeRate)
            push(&processPower, s.processes.reduce(0) { $0 + $1.power })
            #if WIDGETS
            WidgetFeed.record(s, cpuHistory: cpuTotal, gpuHistory: gpu)
            #endif
        }

        let m = s.memory
        push(&memUsed, m.usedFraction)
        push(&memApp, Double(m.app))
        push(&memWired, Double(m.wired))
        push(&memCompressed, Double(m.compressed))
        push(&swapUsed, Double(m.swapUsed))
        if let g = s.gpu { push(&gpu, g.utilization) }
        if let b = s.battery {
            push(&batteryCharge, b.charge)
            if let w = b.watts { push(&batteryPower, abs(w)) }
        }
        let cpuSensors = s.sensors.filter { $0.category == .cpu }
        if let hottest = cpuSensors.map(\.celsius).max() { push(&cpuTemperature, hottest) }
        for sensor in s.sensors { sensorMax[sensor.name] = max(sensorMax[sensor.name] ?? 0, sensor.celsius) }

        if snapshot != nil {
            var nextCPU: [pid_t: History] = [:]
            var nextMem: [pid_t: History] = [:]
            nextCPU.reserveCapacity(s.processes.count)
            for p in s.processes {
                var c = processCPU[p.pid] ?? History(capacity: 60)
                c.append(p.cpu, at: date)
                nextCPU[p.pid] = c
                var mem = processMemory[p.pid] ?? History(capacity: 60)
                mem.append(Double(p.memory), at: date)
                nextMem[p.pid] = mem
            }
            processCPU = nextCPU
            processMemory = nextMem
        }

        // Only diff samples taken in the same mode; switching modes changes which flows are visible.
        if let new = s.connections, let old = snapshot?.connections, old.mode == new.mode, !connectionLogPaused {
            let events = ConnectionLog.events(from: old.flows, to: new.flows, at: date)
            if !events.isEmpty {
                connectionLog.insert(contentsOf: events, at: 0)
                if connectionLog.count > ConnectionLog.capacity { connectionLog.removeLast(connectionLog.count - ConnectionLog.capacity) }
            }
        }

        if appsDirty {
            appsDirty = false
            refreshApps()
        }
        if !paused {
            processes = s.processes
            processGeneration &+= 1
        }
        snapshot = s
        let alive = Set(s.processes.map(\.pid))
        if !selection.isSubset(of: alive) && !paused { selection = selection.intersection(alive) }
    }

    private func refreshApps() {
        var next: [pid_t: AppInfo] = [:]
        for app in NSWorkspace.shared.runningApplications {
            let pid = app.processIdentifier
            if let existing = apps[pid] {
                next[pid] = existing
            } else {
                next[pid] = AppInfo(name: app.localizedName ?? "", icon: Self.rasterize(app.icon, side: 40),
                                    bundleIdentifier: app.bundleIdentifier, isRegular: app.activationPolicy == .regular)
            }
        }
        apps = next
    }

    // MARK: Table rows

    func rows(scope: ProcessScope, sort: [KeyPathComparator<ProcessRow>], tree: Bool, regex: Bool) -> [ProcessRow] {
        let total = snapshot?.memory.total ?? 0
        let divisor = UserDefaults.standard.bool(forKey: SettingsKey.cpuPerCore) ? 1 : Double(coreCount)
        let assertions = snapshot?.powerAssertions ?? [:]
        let all = processes.map {
            ProcessRow.build(from: $0, app: apps[$0.pid], totalMemory: total, cpuDivisor: divisor,
                             preventsSleep: assertions[$0.pid]?.contains(where: \.preventsSleep) ?? false)
        }
        let query = filterText.trimmingCharacters(in: .whitespaces)
        let compiled = regex && !query.isEmpty ? try? Regex(query).ignoresCase() : nil
        let uid = myUID
        return ProcessRowBuilder.rows(all, matching: {
            ProcessRowBuilder.inScope($0, scope: scope, myUID: uid)
                && ProcessRowBuilder.matches($0, query: query, regex: compiled)
        }, sort: sort, tree: tree, collapsed: collapsed)
    }

    func top(by key: KeyPath<ProcessEntry, Double>, count: Int = 5) -> [ProcessEntry] {
        Array((snapshot?.processes ?? []).sorted { $0[keyPath: key] > $1[keyPath: key] }.prefix(count))
    }

    func topMemory(count: Int = 5) -> [ProcessEntry] {
        Array((snapshot?.processes ?? []).sorted { $0.memory > $1.memory }.prefix(count))
    }

    func displayName(_ entry: ProcessEntry) -> String { apps[entry.pid]?.name ?? entry.name }

    /// What the whole Mac draws right now: battery telemetry when there is one, else the sum over processes.
    var systemPower: Double? { snapshot.map(systemPower(of:)) }

    func systemPower(of s: SystemSnapshot) -> Double {
        if let load = s.battery?.systemLoad, load > 0 { return load }
        if let w = s.battery?.watts, !(s.battery?.isPluggedIn ?? true) { return abs(w) }
        return s.processes.reduce(0) { $0 + $1.power }
    }

    func energyGroups(sort: EnergySort) -> [EnergyGroup] {
        EnergyRows.sorted(EnergyRows.groups(snapshot?.processes ?? [], apps: apps, displayName: displayName), by: sort)
    }

    func reveal(_ pid: pid_t) {
        section = .processes
        selection = [pid]
        showInspector = true
    }

    // MARK: Process control

    func request(_ signal: ProcessControl.Signal, for pids: some Collection<pid_t>) {
        let pids = Array(pids)
        guard !pids.isEmpty else { return }
        let names = pids.map { pid in process(pid).map(displayName) ?? "PID \(pid)" }
        let pending = PendingSignal(signal: signal, pids: pids, names: names)
        if UserDefaults.standard.bool(forKey: SettingsKey.confirmKill) {
            pendingSignal = pending
        } else {
            perform(pending)
        }
    }

    func requestQuit(_ pids: some Collection<pid_t>) { request(Self.signal(SIGTERM), for: pids) }
    func requestForceQuit(_ pids: some Collection<pid_t>) { request(Self.signal(SIGKILL), for: pids) }

    static func signal(_ number: Int32) -> ProcessControl.Signal {
        ProcessControl.signals.first { $0.number == number }!
    }

    func perform(_ pending: PendingSignal, asAdmin: Bool = false) {
        if asAdmin {
            let list = pending.pids.map(String.init).joined(separator: " ")
            if case .failure = ProcessControl.runAsAdmin("kill -\(pending.signal.number) \(list)") {
                controlError = ControlError(message: "The administrator command failed or was cancelled.", retry: nil)
            }
            return
        }
        var denied: [pid_t] = []
        var messages: [String] = []
        for pid in pending.pids {
            if case .failure(let failure) = ProcessControl.send(pending.signal.number, to: pid) {
                if case .permissionDenied = failure { denied.append(pid) } else { messages.append(failure.message) }
            }
        }
        if !denied.isEmpty {
            let retry = PendingSignal(signal: pending.signal, pids: denied,
                                      names: denied.map { pid in process(pid).map(displayName) ?? "PID \(pid)" })
            controlError = ControlError(
                message: "You don't have permission to send \(pending.signal.name) to \(retry.names.joined(separator: ", ")).",
                retry: retry)
        } else if let first = messages.first {
            controlError = ControlError(message: first, retry: nil)
        }
    }

    func renice(_ pid: pid_t, to value: Int) {
        if case .failure(let failure) = ProcessControl.setPriority(value, of: pid) {
            if case .permissionDenied = failure {
                if case .failure = ProcessControl.runAsAdmin("renice \(value) -p \(pid)") {
                    controlError = ControlError(message: "Changing priority requires administrator rights.", retry: nil)
                }
            } else {
                controlError = ControlError(message: failure.message, retry: nil)
            }
        }
    }

    func adjustRefresh(faster: Bool) {
        RefreshInterval.set(RefreshInterval.step(RefreshInterval.milliseconds, faster: faster))
    }
}
