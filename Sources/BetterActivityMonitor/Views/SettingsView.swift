import ServiceManagement
import SwiftUI
import SystemKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings().tabItem { Label("Appearance", systemImage: "paintpalette") }
            ProcessSettings().tabItem { Label("Processes", systemImage: "list.bullet.rectangle") }
            HistorySettingsTab().tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            MenuBarSettings().tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
        }
        .frame(width: 520)
        .scenePadding()
    }
}

private struct GeneralSettings: View {
    @AppStorage(SettingsKey.refreshInterval) private var interval = 1.0
    @AppStorage(SettingsKey.historyLength) private var history = 120
    @AppStorage(SettingsKey.fahrenheit) private var fahrenheit = false
    @AppStorage(SettingsKey.freezeDuringResize) private var freezeDuringResize = true

    /// The stored seconds as whole milliseconds; typed values outside the range snap to it.
    private var milliseconds: Binding<Int> {
        Binding { Int((interval * 1000).rounded()) } set: { RefreshInterval.set($0) }
    }

    var body: some View {
        Form {
            LabeledContent("Update every") {
                HStack(spacing: 6) {
                    TextField("Interval", value: milliseconds, format: .number.grouping(.never))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text("ms").foregroundStyle(.secondary)
                    Stepper("Interval", value: milliseconds, in: RefreshInterval.range, step: 100)
                        .labelsHidden()
                }
            }
            Text(interval < 0.25
                 ? "Below 250 ms the samplers alone use a noticeable share of a core."
                 : "\(RefreshInterval.range.lowerBound)–\(RefreshInterval.range.upperBound) ms. Faster updates are smoother but cost more CPU. Also in the toolbar, and with ⌘+ / ⌘−.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Graph history", selection: $history) {
                ForEach([60, 120, 300, 600, 1800], id: \.self) { Text("\($0) samples").tag($0) }
            }
            Picker("Temperature", selection: $fahrenheit) {
                Text("Celsius").tag(false)
                Text("Fahrenheit").tag(true)
            }
            .pickerStyle(.segmented)
            Toggle("Freeze content while resizing the window", isOn: $freezeDuringResize)
            Text("Keeps the page still while you drag the window edge and lays it out once when you let go. Resizing stays smooth; turn it off to see the layout adapt live.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct HistorySettingsTab: View {
    @Environment(SystemStore.self) private var store
    @AppStorage(SettingsKey.historyEnabled) private var enabled = false
    @AppStorage(SettingsKey.historyRetentionDays) private var days = HistorySettings.defaultRetention
    @State private var size: Int?
    @State private var status: SMAppService.Status = .notRegistered
    @State private var error: String?
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section {
                Toggle("Record history in the background", isOn: $enabled)
                    .disabled(!store.historyAgent.isAvailable)
                Text("A small background agent saves a summary of every minute (CPU, memory, GPU, network, disk, power and the busiest apps), also while BetterActivityMonitor is closed. It stays on this Mac and uses about as much CPU as a clock. The resource pages then get a Live / 1h / 24h / 7d / 30d switch.")
                    .font(.caption).foregroundStyle(.secondary)
                if enabled || status != .notRegistered {
                    LabeledContent("Status", value: HistoryAgentService.describe(status))
                }
                if status == .requiresApproval {
                    Button("Open Login Items Settings…") { store.historyAgent.openLoginItemsSettings() }
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                Picker("Keep", selection: $days) {
                    Text("1 day").tag(1)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                }
                LabeledContent("Size on disk", value: size.map { Fmt.bytes(UInt64($0)) } ?? "—")
                Button("Clear History…", role: .destructive) { confirmClear = true }
            }
        }
        .formStyle(.grouped)
        .onAppear { refresh() }
        .onChange(of: enabled) {
            error = store.historyAgent.sync(enabled: enabled)
            refresh()
        }
        .task(id: days) {
            // Apply a shorter retention right away instead of at the agent's next hourly prune.
            await store.history.prune(olderThan: Date().addingTimeInterval(-Double(days) * 86_400))
            size = await store.history.size()
        }
        .task {
            // Approval happens in System Settings; pick it up when the user comes back.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                refresh()
            }
        }
        .confirmationDialog("Clear all recorded history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) {
                Task {
                    await store.history.clear()
                    size = await store.history.size()
                }
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    private func refresh() { status = store.historyAgent.status }
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

    var body: some View {
        Form {
            Toggle("Show in menu bar", isOn: $show)
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
        .formStyle(.grouped)
        .disabled(!show)
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
