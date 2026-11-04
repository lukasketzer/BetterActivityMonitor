import SwiftUI
import AppKit

/// Keeps the Settings window above the main window. SwiftUI's window ordering otherwise lets the main window
/// (which redraws on every sample) come to the front and cover Settings.
private struct KeepWindowInFront: NSViewRepresentable {
    final class Anchor: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.level = .floating
            // Floating windows would otherwise stay on screen over other apps; hide with the app instead.
            window.hidesOnDeactivate = true
        }
    }

    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {}
}

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings().tabItem { Label("Appearance", systemImage: "paintpalette") }
            ProcessSettings().tabItem { Label("Processes", systemImage: "list.bullet.rectangle") }
            MenuBarSettings().tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
        }
        .frame(width: 520)
        .scenePadding()
        .background(KeepWindowInFront())
    }
}

private struct GeneralSettings: View {
    @Environment(SystemStore.self) private var store
    @AppStorage(SettingsKey.refreshInterval) private var interval = 1.0
    @AppStorage(SettingsKey.historyLength) private var history = 120
    @AppStorage(SettingsKey.fahrenheit) private var fahrenheit = false
    @AppStorage(SettingsKey.freezeDuringResize) private var freezeDuringResize = true
    @AppStorage(SettingsKey.sidebarHidden) private var hiddenSections = AppSection.defaultHidden

    private func shown(_ section: AppSection) -> Binding<Bool> {
        Binding {
            !AppSection.hidden(hiddenSections).contains(section)
        } set: { on in
            var hidden = AppSection.hidden(hiddenSections)
            if on { hidden.remove(section) } else { hidden.insert(section) }
            // Don't leave the detail pane on a page whose sidebar entry just disappeared.
            if !on, store.section == section { store.section = .overview }
            hiddenSections = AppSection.allCases.filter(hidden.contains).map(\.rawValue).joined(separator: ",")
        }
    }

    private var milliseconds: Binding<Int> {
        Binding { RefreshInterval.nearestPreset(Int((interval * 1000).rounded())) } set: { RefreshInterval.set($0) }
    }

    var body: some View {
        Form {
            Picker("Update every", selection: milliseconds) {
                ForEach(RefreshInterval.presets, id: \.self) { Text(RefreshInterval.label($0)).tag($0) }
            }
            Text("Faster updates are smoother but cost more CPU. Also in the View menu, and with ⌘+ / ⌘−.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Graph history", selection: $history) {
                ForEach([60, 120, 300, 600, 1800], id: \.self) { Text("\($0) samples").tag($0) }
            }
            Picker("Temperature", selection: $fahrenheit) {
                Text("Celsius").tag(false)
                Text("Fahrenheit").tag(true)
            }
            .pickerStyle(.segmented)
            Section("Sidebar") {
                ForEach(AppSection.hideable) { section in
                    Toggle(isOn: shown(section)) { Label(section.title, systemImage: section.symbol) }
                }
                Text("Choose which pages appear in the sidebar. Overview is always shown. Temperatures is off by default.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Freeze content while resizing the window", isOn: $freezeDuringResize)
            Text("Keeps the page still while you drag the window edge and lays it out once when you let go. Resizing stays smooth; turn it off to see the layout adapt live.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceSettings: View {
    @AppStorage(SettingsKey.theme) private var themeID = Theme.system.id
    @AppStorage(SettingsKey.graphStyle) private var graphStyle: GraphStyle = .area
    @AppStorage(SettingsKey.backgroundGradient) private var gradient = true

    var body: some View {
        Form {
            Picker("Theme", selection: $themeID) {
                ForEach(Theme.all) { theme in
                    HStack {
                        ThemeSwatch(theme: theme)
                        Text(theme.name)
                    }
                    .tag(theme.id)
                }
            }
            .pickerStyle(.radioGroup)
            Picker("Graph style", selection: $graphStyle) {
                ForEach(GraphStyle.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Colored background gradient", isOn: $gradient)
        }
        .formStyle(.grouped)
    }
}

private struct ThemeSwatch: View {
    var theme: Theme
    var body: some View {
        HStack(spacing: 2) {
            ForEach([theme.cpuUser, theme.memApp, theme.netIn, theme.netOut, theme.low, theme.mid, theme.high], id: \.self) {
                RoundedRectangle(cornerRadius: 2).fill($0).frame(width: 10, height: 14)
            }
        }
    }
}

private struct ProcessSettings: View {
    @AppStorage(SettingsKey.cpuPerCore) private var perCore = true
    @AppStorage(SettingsKey.useRegex) private var regex = false
    @AppStorage(SettingsKey.confirmKill) private var confirm = true
    @AppStorage(SettingsKey.treeView) private var tree = false
    @AppStorage(SettingsKey.processScope) private var scope: ProcessScope = .all

    var body: some View {
        Form {
            Picker("Process CPU %", selection: $perCore) {
                Text("Per core (100% = one core, like Activity Monitor)").tag(true)
                Text("Of whole system (100% = all cores, like btop)").tag(false)
            }
            .pickerStyle(.radioGroup)
            Toggle("Filter field uses regular expressions", isOn: $regex)
            Toggle("Confirm before sending signals", isOn: $confirm)
            Toggle("Show process tree", isOn: $tree)
            Picker("Show", selection: $scope) {
                ForEach(ProcessScope.allCases) { Text($0.label).tag($0) }
            }
            Text("Columns: right-click the table header to show or hide columns; drag headers to reorder. Click a header to sort.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct MenuBarSettings: View {
    @Environment(SystemStore.self) private var store
    @AppStorage(SettingsKey.showMenuBarExtra) private var show = false
    @AppStorage(SettingsKey.menuBarItems) private var items = MenuBarItems.default
    @AppStorage(SettingsKey.menuBarStyle) private var style: MenuBarStyle = .rings
    @AppStorage(SettingsKey.menuBarColored) private var colored = false
    @AppStorage(SettingsKey.menuBarSymbols) private var symbols = true
    @AppStorage(SettingsKey.theme) private var themeID = Theme.system.id
    @AppStorage(SettingsKey.fahrenheit) private var fahrenheit = false
    @State private var openAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Toggle("Show in menu bar", isOn: $show)
            Toggle("Open at login", isOn: Binding { openAtLogin } set: { on in
                loginError = LoginItem.set(on)
                openAtLogin = LoginItem.isEnabled
            })
            .help("Starts with only the menu bar item when it's shown; otherwise opens the window.")
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.secondary)
            }
            // Only the options below are greyed out; the toggle itself must stay usable to turn this back on.
            Group {
            Section {
                MenuBarPreview(glyph: MenuBarGlyph(readings: store.menuBarReadings(items.enabled, fahrenheit: fahrenheit),
                                                   style: style, colored: colored, symbols: symbols, theme: Theme.named(themeID)))
                Picker("Style", selection: $style) {
                    ForEach(MenuBarStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if style == .absolute {
                    Text("CPU shows the 1-minute load average; memory, GPU memory and disk show the amount in use; battery shows the time remaining. Percentages stand in where there is no absolute value.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle(style == .rings ? "Show labels beside rings" : "Show symbols before values", isOn: $symbols)
                Toggle("Use theme colors", isOn: $colored)
                Text("Monochrome matches the system menu bar and follows its light, dark and tinted appearance.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                List {
                    ForEach($items.entries) { $entry in
                        MenuBarMetricRow(entry: $entry, available: isAvailable(entry.metric))
                    }
                    .onMove { items.entries.move(fromOffsets: $0, toOffset: $1) }
                }
                .scrollDisabled(true)
                .frame(height: CGFloat(items.entries.count) * 26 + 8)
            } header: {
                Text("Metrics")
            } footer: {
                Text("Drag to reorder. Network shows download over upload and has no ring.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            }
            .disabled(!show)
        }
        .formStyle(.grouped)
    }

    private func isAvailable(_ metric: MenuBarMetric) -> Bool {
        guard let snapshot = store.snapshot else { return true }
        return MenuBarInputs(snapshot, temperature: store.cpuTemperatureNow).reading(metric, fahrenheit: fahrenheit) != nil
    }
}

private struct MenuBarMetricRow: View {
    @Binding var entry: MenuBarEntry
    var available: Bool

    var body: some View {
        HStack {
            Toggle(isOn: $entry.enabled) {
                Label(entry.metric.title, systemImage: entry.metric.symbol)
            }
            .toggleStyle(.checkbox)
            Spacer()
            if !available {
                Text("Not available on this Mac").font(.caption).foregroundStyle(.tertiary)
            }
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
        }
    }
}

/// The glyph between stand-ins for the clock and system icons, on a strip that looks like the menu bar.
private struct MenuBarPreview: View {
    var glyph: MenuBarGlyph

    var body: some View {
        HStack(spacing: 14) {
            Spacer()
            if glyph.readings.isEmpty {
                Image(systemName: "gauge.with.dots.needle.33percent")
            } else {
                glyph
            }
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Text(Date.now, format: .dateTime.weekday().hour().minute())
        }
        .font(.system(size: MenuBarGlyph.fontSize))
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(.bar, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
    }
}
