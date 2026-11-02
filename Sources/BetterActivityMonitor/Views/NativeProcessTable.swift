import AppKit
import SwiftUI
import SystemKit

/// Columns of the process table. Order here is the default on-screen order.
enum ProcessColumn: String, CaseIterable {
    case name, cpu, memory, memPercent, cpuTime, threads, pid, user, state
    case power, readRate, writeRate, netIn, netOut, resident, readTotal, writeTotal, netInTotal, netOutTotal
    case energy, wakeups, preventsSleep, ppid, nice, started, path

    /// Columns filled from `nettop`; it only runs while one of them is visible.
    static let network: Set<ProcessColumn> = [.netIn, .netOut, .netInTotal, .netOutTotal]

    var title: String {
        switch self {
        case .name: "Process Name"
        case .cpu: "% CPU"
        case .memory: "Memory"
        case .memPercent: "% Mem"
        case .cpuTime: "CPU Time"
        case .threads: "Threads"
        case .pid: "PID"
        case .user: "User"
        case .state: "State"
        case .readRate: "Read/s"
        case .writeRate: "Write/s"
        case .power: "Power"
        case .energy: "Energy"
        case .preventsSleep: "Sleep"
        case .netIn: "Rcvd/s"
        case .netOut: "Sent/s"
        case .netInTotal: "Bytes Rcvd"
        case .netOutTotal: "Bytes Sent"
        case .resident: "Real Mem"
        case .readTotal: "Bytes Read"
        case .writeTotal: "Bytes Written"
        case .wakeups: "Idle Wake Ups"
        case .ppid: "PPID"
        case .nice: "Nice"
        case .started: "Started"
        case .path: "Path"
        }
    }

    var width: CGFloat {
        switch self {
        case .name: 240
        case .path: 320
        case .started: 130
        case .cpu: 90
        case .memory, .cpuTime, .readRate, .writeRate, .resident, .readTotal, .writeTotal, .wakeups,
             .netIn, .netOut, .netInTotal, .netOutTotal, .power, .energy: 90
        case .user, .state: 80
        default: 60
        }
    }

    /// The network columns are off by default: showing one runs `nettop -P` every tick, about 12 ms of CPU
    /// (`sysbench nettop`), which would double the Overview's baseline cost.
    var hiddenByDefault: Bool {
        [.resident, .readTotal, .writeTotal, .energy, .wakeups, .preventsSleep, .ppid, .nice, .started, .path].contains(self)
            || Self.network.contains(self)
    }

    var isNumeric: Bool { ![.name, .user, .state, .path, .started, .preventsSleep].contains(self) }

    /// Values for other users' processes are withheld by the kernel; these columns stay meaningful anyway.
    /// nettop sees every user's processes, so the network columns count too.
    private var alwaysAvailable: Bool {
        [.name, .pid, .ppid, .user, .state, .nice, .started, .path, .preventsSleep].contains(self)
            || Self.network.contains(self)
    }

    func comparator(ascending: Bool) -> KeyPathComparator<ProcessRow> {
        let order: SortOrder = ascending ? .forward : .reverse
        switch self {
        case .name: return KeyPathComparator(\.name, order: order)
        case .cpu: return KeyPathComparator(\.cpu, order: order)
        case .memory: return KeyPathComparator(\.memory, order: order)
        case .memPercent: return KeyPathComparator(\.memoryFraction, order: order)
        case .cpuTime: return KeyPathComparator(\.cpuTime, order: order)
        case .threads: return KeyPathComparator(\.threads, order: order)
        case .pid: return KeyPathComparator(\.pid, order: order)
        case .user: return KeyPathComparator(\.user, order: order)
        case .state: return KeyPathComparator(\.state, order: order)
        case .readRate: return KeyPathComparator(\.diskReadRate, order: order)
        case .writeRate: return KeyPathComparator(\.diskWriteRate, order: order)
        case .power: return KeyPathComparator(\.power, order: order)
        case .energy: return KeyPathComparator(\.energyTotal, order: order)
        case .preventsSleep: return KeyPathComparator(\.preventsSleepRank, order: order)
        case .netIn: return KeyPathComparator(\.netRateIn, order: order)
        case .netOut: return KeyPathComparator(\.netRateOut, order: order)
        case .netInTotal: return KeyPathComparator(\.netTotalIn, order: order)
        case .netOutTotal: return KeyPathComparator(\.netTotalOut, order: order)
        case .resident: return KeyPathComparator(\.resident, order: order)
        case .readTotal: return KeyPathComparator(\.diskReadTotal, order: order)
        case .writeTotal: return KeyPathComparator(\.diskWriteTotal, order: order)
        case .wakeups: return KeyPathComparator(\.wakeups, order: order)
        case .ppid: return KeyPathComparator(\.ppid, order: order)
        case .nice: return KeyPathComparator(\.nice, order: order)
        case .started: return KeyPathComparator(\.startTime, order: order)
        case .path: return KeyPathComparator(\.path, order: order)
        }
    }

    func text(_ row: ProcessRow) -> String {
        if !alwaysAvailable && !row.hasTaskInfo { return "—" }
        switch self {
        case .name: return row.name
        case .cpu: return Fmt.number(row.isCollapsed ? row.subtreeCPU : row.cpu)
        case .memory: return Fmt.bytes(row.isCollapsed ? row.subtreeMemory : row.memory)
        case .memPercent: return Fmt.percent(row.memoryFraction)
        case .cpuTime: return Fmt.cpuTime(row.cpuTime)
        case .threads: return "\(row.threads)"
        case .pid: return "\(row.pid)"
        case .user: return row.user
        case .state: return row.state.rawValue
        case .readRate: return row.diskReadRate > 0 ? Fmt.rate(row.diskReadRate) : "0"
        case .writeRate: return row.diskWriteRate > 0 ? Fmt.rate(row.diskWriteRate) : "0"
        case .power: return Fmt.watts(row.isCollapsed ? row.subtreePower : row.power)
        case .energy: return Fmt.energy(row.energyTotal)
        case .preventsSleep: return row.preventsSleep ? "Preventing" : ""
        case .netIn:
            let value = row.isCollapsed ? row.subtreeNetIn : row.netRateIn
            return value > 0 ? Fmt.rate(value) : "0"
        case .netOut:
            let value = row.isCollapsed ? row.subtreeNetOut : row.netRateOut
            return value > 0 ? Fmt.rate(value) : "0"
        case .netInTotal: return Fmt.bytes(row.netTotalIn)
        case .netOutTotal: return Fmt.bytes(row.netTotalOut)
        case .resident: return Fmt.bytes(row.resident)
        case .readTotal: return Fmt.bytes(row.diskReadTotal)
        case .writeTotal: return Fmt.bytes(row.diskWriteTotal)
        case .wakeups: return Fmt.compact(row.wakeups)
        case .ppid: return "\(row.ppid)"
        case .nice: return "\(row.nice)"
        case .started: return Fmt.startDate.string(from: row.startTime)
        case .path: return row.path
        }
    }
}

struct ProcessSort: Equatable {
    var column: ProcessColumn
    var ascending: Bool
    var comparators: [KeyPathComparator<ProcessRow>] {
        [column.comparator(ascending: ascending), ProcessColumn.pid.comparator(ascending: true)]
    }
}

/// AppKit-backed process table. SwiftUI's Table diffs every row on each refresh, which is what made
/// the app laggy; NSTableView.reloadData only touches visible rows.
struct NativeProcessTable: NSViewRepresentable {
    var rows: [ProcessRow]
    var tree: Bool
    var cpuScale: Double
    var theme: Theme
    @Binding var selection: Set<pid_t>
    @Binding var sort: ProcessSort
    var store: SystemStore

    func makeCoordinator() -> ProcessTableController { ProcessTableController(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let controller = context.coordinator
        let table = ProcessNSTableView()
        table.controller = controller
        table.style = .fullWidth
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.rowHeight = 22
        table.intercellSpacing = NSSize(width: 8, height: 0)
        table.backgroundColor = .clear

        for column in ProcessColumn.allCases {
            let tc = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            tc.title = column.title
            tc.width = column.width
            tc.minWidth = column == .name ? 140 : 40
            tc.headerCell.alignment = column.isNumeric ? .right : .left
            tc.sortDescriptorPrototype = NSSortDescriptor(key: column.rawValue, ascending: !column.isNumeric)
            table.addTableColumn(tc)
        }
        table.autosaveName = "ProcessTable.v1"
        table.autosaveTableColumns = true
        controller.applyHiddenColumns(to: table)

        table.sortDescriptors = [NSSortDescriptor(key: sort.column.rawValue, ascending: sort.ascending)]
        table.dataSource = controller
        table.delegate = controller
        table.target = controller
        table.doubleAction = #selector(ProcessTableController.doubleClicked(_:))

        let menu = NSMenu()
        menu.delegate = controller
        table.menu = menu
        let headerMenu = NSMenu()
        headerMenu.delegate = controller
        table.headerView?.menu = headerMenu
        controller.headerMenu = headerMenu

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        controller.tableView = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.reload()
    }
}

@MainActor
final class ProcessTableController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    var parent: NativeProcessTable
    weak var tableView: NSTableView?
    weak var headerMenu: NSMenu?
    private var rows: [ProcessRow] = []
    private var applyingSelection = false
    private static let hiddenKey = "ProcessTable.hiddenColumns"

    init(_ parent: NativeProcessTable) { self.parent = parent }

    func reload() {
        guard let table = tableView else { return }
        let countChanged = parent.rows.count != rows.count
        rows = parent.rows
        applyingSelection = true
        // Processes come and go every tick; adjusting the row count keeps existing row views alive,
        // whereas reloadData would rebuild them all.
        if countChanged { table.noteNumberOfRowsChanged() }
        let visible = table.rows(in: table.visibleRect)
        for index in visible.location..<min(visible.location + visible.length, rows.count) {
            for (c, column) in table.tableColumns.enumerated() where !column.isHidden {
                if let view = table.view(atColumn: c, row: index, makeIfNecessary: false) {
                    configure(view, column: column, row: index)
                }
            }
        }
        let indexes = IndexSet(rows.indices.filter { parent.selection.contains(rows[$0].pid) })
        table.selectRowIndexes(indexes, byExtendingSelection: false)
        applyingSelection = false
    }

    // MARK: Columns

    private var hiddenColumns: Set<String> {
        get { Self.hiddenColumns() }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: Self.hiddenKey)
            UserDefaults.standard.set(ProcessColumn.allCases.map(\.rawValue), forKey: Self.knownKey)
        }
    }

    private static let knownKey = "ProcessTable.knownColumns"

    /// Hidden column ids. Columns added after the user last changed the list start out at their default.
    static func hiddenColumns(_ defaults: UserDefaults = .standard) -> Set<String> {
        let byDefault = Set(ProcessColumn.allCases.filter(\.hiddenByDefault).map(\.rawValue))
        guard let saved = defaults.stringArray(forKey: hiddenKey) else { return byDefault }
        // Lists saved before `knownKey` existed knew every column up to `path`, none of the network ones.
        let known = defaults.stringArray(forKey: knownKey).map(Set.init)
            ?? Set(ProcessColumn.allCases.filter { !ProcessColumn.network.contains($0) }.map(\.rawValue))
        return Set(saved).union(byDefault.subtracting(known))
    }

    /// Whether any visible column needs connection data.
    static var showsNetworkColumns: Bool {
        let hidden = hiddenColumns()
        return ProcessColumn.network.contains { !hidden.contains($0.rawValue) }
    }

    func applyHiddenColumns(to table: NSTableView) {
        let hidden = hiddenColumns
        for column in table.tableColumns { column.isHidden = hidden.contains(column.identifier.rawValue) }
    }

    private func toggleColumn(_ column: ProcessColumn) {
        var hidden = hiddenColumns
        if hidden.contains(column.rawValue) { hidden.remove(column.rawValue) } else { hidden.insert(column.rawValue) }
        hiddenColumns = hidden
        if let table = tableView { applyHiddenColumns(to: table) }
        parent.store.processTableColumnsChanged()
    }

    // MARK: Data source / delegate

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let d = tableView.sortDescriptors.first, let key = d.key, let column = ProcessColumn(rawValue: key) else { return }
        parent.sort = ProcessSort(column: column, ascending: d.ascending)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !applyingSelection, let table = tableView else { return }
        parent.selection = Set(table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].pid : nil })
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row index: Int) -> NSView? {
        guard let tableColumn, let column = ProcessColumn(rawValue: tableColumn.identifier.rawValue) else { return nil }
        let id = tableColumn.identifier
        let view: NSView = tableView.makeView(withIdentifier: id, owner: nil) ?? {
            switch column {
            case .name: NameCell(identifier: id)
            case .cpu: CPUCell(identifier: id)
            default: TextCell(identifier: id)
            }
        }()
        configure(view, column: tableColumn, row: index)
        return view
    }

    private func configure(_ view: NSView, column tableColumn: NSTableColumn, row index: Int) {
        guard let column = ProcessColumn(rawValue: tableColumn.identifier.rawValue), rows.indices.contains(index) else { return }
        let row = rows[index]
        let theme = parent.theme

        switch column {
        case .name:
            guard let cell = view as? NameCell else { return }
            cell.configure(row: row, tree: parent.tree, icon: parent.store.icon(for: row), isMine: row.uid == parent.store.myUID) { [weak self] in
                self?.toggleCollapsed(row.pid)
            }
        case .cpu:
            guard let cell = view as? CPUCell else { return }
            let value = row.isCollapsed ? row.subtreeCPU : row.cpu
            let fraction = min(value / max(parent.cpuScale, 1), 1)
            cell.configure(text: column.text(row), fraction: row.hasTaskInfo ? fraction : nil,
                           barColor: NSColor(theme.meter(fraction)),
                           textColor: fraction >= 0.8 ? NSColor(theme.high) : .labelColor)
        default:
            guard let cell = view as? TextCell else { return }
            var color = NSColor.labelColor
            switch column {
            case .user: color = row.uid == parent.store.myUID ? .labelColor : .secondaryLabelColor
            case .state:
                color = switch row.state {
                case .running: NSColor(theme.low)
                case .zombie, .stopped: NSColor(theme.high)
                default: .secondaryLabelColor
                }
            case .path, .started: color = .secondaryLabelColor
            default: break
            }
            cell.configure(text: column.text(row), color: color, numeric: column.isNumeric,
                           truncateMiddle: column == .path)
        }
    }

    private func toggleCollapsed(_ pid: pid_t) {
        let store = parent.store
        if store.collapsed.contains(pid) { store.collapsed.remove(pid) } else { store.collapsed.insert(pid) }
    }

    @objc func doubleClicked(_ sender: NSTableView) {
        guard rows.indices.contains(sender.clickedRow) else { return }
        parent.store.reveal(rows[sender.clickedRow].pid)
    }

    func quitSelection() { parent.store.requestQuit(parent.selection) }

    // MARK: Menus

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if menu === headerMenu {
            for column in ProcessColumn.allCases where column != .name {
                let item = ActionMenuItem(column.title) { [weak self] in self?.toggleColumn(column) }
                item.state = hiddenColumns.contains(column.rawValue) ? .off : .on
                menu.addItem(item)
            }
            menu.addItem(.separator())
            menu.addItem(ActionMenuItem("Reset Columns") { [weak self] in
                UserDefaults.standard.removeObject(forKey: Self.hiddenKey)
                UserDefaults.standard.removeObject(forKey: Self.knownKey)
                if let table = self?.tableView { self?.applyHiddenColumns(to: table) }
                self?.parent.store.processTableColumnsChanged()
            })
            return
        }

        guard let table = tableView, rows.indices.contains(table.clickedRow) else { return }
        let clicked = rows[table.clickedRow].pid
        let pids = parent.selection.contains(clicked) ? Array(parent.selection) : [clicked]
        ProcessMenuBuilder.populate(menu, pids: pids, store: parent.store)
    }
}

/// Builds the process context menu with AppKit items (shared by table and toolbar).
@MainActor
enum ProcessMenuBuilder {
    static func populate(_ menu: NSMenu, pids: [pid_t], store: SystemStore) {
        menu.addItem(ActionMenuItem("Get Info") { if let pid = pids.first { store.reveal(pid) } })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Quit (SIGTERM)") { store.requestQuit(pids) })
        menu.addItem(ActionMenuItem("Force Quit (SIGKILL)") { store.requestForceQuit(pids) })

        let signals = NSMenu()
        for signal in ProcessControl.signals {
            signals.addItem(ActionMenuItem("\(signal.number)  \(signal.name) — \(signal.summary)") { store.request(signal, for: pids) })
        }
        let signalItem = NSMenuItem(title: "Send Signal", action: nil, keyEquivalent: "")
        signalItem.submenu = signals
        menu.addItem(signalItem)

        if pids.count == 1, let pid = pids.first {
            let nice = NSMenu()
            for value in [-20, -10, -5, 0, 5, 10, 19] {
                let item = ActionMenuItem(value == 0 ? "0 (Normal)" : "\(value)") { store.renice(pid, to: value) }
                item.state = store.process(pid)?.nice == value ? .on : .off
                nice.addItem(item)
            }
            let niceItem = NSMenuItem(title: "Priority (nice)", action: nil, keyEquivalent: "")
            niceItem.submenu = nice
            menu.addItem(niceItem)
            menu.addItem(.separator())
            if let entry = store.process(pid), !entry.path.isEmpty {
                menu.addItem(ActionMenuItem("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)])
                })
            }
            menu.addItem(ActionMenuItem("Select Parent Process") {
                if let ppid = store.process(pid)?.ppid { store.selection = [ppid] }
            })
        }
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Copy PID") { copy(pids.map(String.init).joined(separator: " ")) })
        menu.addItem(ActionMenuItem("Copy Name") { copy(pids.compactMap { store.process($0).map(store.displayName) }.joined(separator: "\n")) })
        menu.addItem(ActionMenuItem("Copy Command Line") {
            copy(pids.map { ProcessDetails.arguments(pid: $0).1.joined(separator: " ") }.joined(separator: "\n"))
        })
    }

    private static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func fire() { handler() }
}

final class ProcessNSTableView: NSTableView {
    weak var controller: ProcessTableController?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {  // delete / forward delete
            MainActor.assumeIsolated { controller?.quitSelection() }
        } else if event.charactersIgnoringModifiers == "/",
                  event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
                  focusSearchField() {
            // "/" jumps into the toolbar search field, like in vim, less and GitHub.
        } else {
            super.keyDown(with: event)
        }
    }

    /// Moves keyboard focus to the window's toolbar search field. Returns false if there is none.
    private func focusSearchField() -> Bool {
        guard let window else { return false }
        let field = window.toolbar?.items.lazy.compactMap { ($0 as? NSSearchToolbarItem)?.searchField }.first
            ?? window.contentView?.superview.flatMap { Self.findSearchField(in: $0) }
        guard let field else { return false }
        return window.makeFirstResponder(field)
    }

    private static func findSearchField(in view: NSView) -> NSSearchField? {
        if let field = view as? NSSearchField { return field }
        return view.subviews.lazy.compactMap { findSearchField(in: $0) }.first
    }
}

// MARK: Cells
// Cells use manual frame layout: Auto Layout in hundreds of cells per refresh dominated the main thread.

private let cellFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
private let rowTextHeight: CGFloat = 16

private func makeLabel(_ font: NSFont) -> NSTextField {
    let label = NSTextField(labelWithString: "")
    label.font = font
    label.lineBreakMode = .byTruncatingTail
    label.cell?.truncatesLastVisibleLine = true
    return label
}

private extension NSView {
    func centeredFrame(x: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
        NSRect(x: x, y: ((bounds.height - height) / 2).rounded(), width: max(width, 0), height: height)
    }
}

final class TextCell: NSTableCellView {
    private let label = makeLabel(cellFont)

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        addSubview(label)
        textField = label
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        label.frame = centeredFrame(x: 2, width: bounds.width - 4, height: rowTextHeight)
    }

    func configure(text: String, color: NSColor, numeric: Bool, truncateMiddle: Bool) {
        if label.stringValue != text { label.stringValue = text }
        if label.textColor != color { label.textColor = color }
        label.alignment = numeric ? .right : .left
        label.lineBreakMode = truncateMiddle ? .byTruncatingMiddle : .byTruncatingTail
    }
}

final class CPUCell: NSTableCellView {
    private let label = makeLabel(cellFont)
    private let bar = MeterView()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        label.alignment = .right
        addSubview(bar)
        addSubview(label)
        textField = label
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        bar.frame = centeredFrame(x: 2, width: 26, height: 4)
        label.frame = centeredFrame(x: 32, width: bounds.width - 34, height: rowTextHeight)
    }

    func configure(text: String, fraction: Double?, barColor: NSColor, textColor: NSColor) {
        if label.stringValue != text { label.stringValue = text }
        if label.textColor != textColor { label.textColor = textColor }
        bar.isHidden = fraction == nil
        bar.fraction = fraction ?? 0
        bar.color = barColor
    }
}

final class MeterView: NSView {
    var fraction: Double = 0 { didSet { if fraction != oldValue { needsDisplay = true } } }
    var color: NSColor = .systemGreen { didSet { if color != oldValue { needsDisplay = true } } }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.height / 2
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: r, yRadius: r).fill()
        color.setFill()
        let filled = NSRect(x: 0, y: 0, width: bounds.width * CGFloat(max(0, min(1, fraction))), height: bounds.height)
        NSBezierPath(roundedRect: filled, xRadius: r, yRadius: r).fill()
    }
}

final class NameCell: NSTableCellView {
    private let label = makeLabel(.systemFont(ofSize: NSFont.systemFontSize))
    private let icon = NSImageView()
    private let disclosure = NSButton()
    private var indent: CGFloat = 0
    private var showsDisclosureColumn = false
    private var onToggle: (() -> Void)?
    private var iconKey: ObjectIdentifier?
    private var disclosureCollapsed: Bool?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        icon.imageScaling = .scaleProportionallyUpOrDown
        disclosure.isBordered = false
        disclosure.imagePosition = .imageOnly
        disclosure.target = self
        disclosure.action = #selector(toggle)
        disclosure.contentTintColor = .secondaryLabelColor
        addSubview(disclosure)
        addSubview(icon)
        addSubview(label)
        textField = label
        imageView = icon
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        var x = indent
        if showsDisclosureColumn {
            disclosure.frame = centeredFrame(x: x, width: 12, height: 14)
            x += 16
        }
        icon.frame = centeredFrame(x: x, width: 16, height: 16)
        x += 22
        label.frame = centeredFrame(x: x, width: bounds.width - x - 2, height: rowTextHeight)
    }

    func configure(row: ProcessRow, tree: Bool, icon image: NSImage?, isMine: Bool, onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
        let newIndent = tree ? CGFloat(row.depth) * 14 : 2
        if newIndent != indent || showsDisclosureColumn != tree {
            indent = newIndent
            showsDisclosureColumn = tree
            needsLayout = true
        }
        disclosure.isHidden = !tree || !row.hasChildren
        if tree && row.hasChildren && disclosureCollapsed != row.isCollapsed {
            disclosureCollapsed = row.isCollapsed
            disclosure.image = NSImage(systemSymbolName: row.isCollapsed ? "chevron.right" : "chevron.down",
                                       accessibilityDescription: row.isCollapsed ? "Expand" : "Collapse")?
                .withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
        }
        let resolved = image ?? (row.uid == 0 ? Self.rootIcon : Self.userIcon)
        let key = ObjectIdentifier(resolved)
        if key != iconKey {
            iconKey = key
            icon.image = resolved
            icon.contentTintColor = image == nil ? .tertiaryLabelColor : nil
        }
        let text = row.isCollapsed ? "\(row.name)  +" : row.name
        if label.stringValue != text { label.stringValue = text }
        let tip = row.path.isEmpty ? row.name : row.path
        if toolTip != tip { toolTip = tip }
    }

    private static let rootIcon = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: nil)!
    private static let userIcon = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)!

    @objc private func toggle() { onToggle?() }
}
