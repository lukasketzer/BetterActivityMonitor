import SwiftUI

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
    }
}

private struct GeneralSettings: View {
    @AppStorage(SettingsKey.refreshInterval) private var interval = 1.0
    @AppStorage(SettingsKey.historyLength) private var history = 120
    @AppStorage(SettingsKey.fahrenheit) private var fahrenheit = false
    @AppStorage(SettingsKey.freezeDuringResize) private var freezeDuringResize = true

    var body: some View {
        Form {
            Picker("Update every", selection: $interval) {
                ForEach([0.25, 0.5, 1, 2, 3, 5, 10], id: \.self) { value in
                    Text(value < 1 ? "\(Int(value * 1000)) ms" : "\(Int(value)) s").tag(value)
                }
            }
            Text("Faster updates are smoother but cost more CPU. Shortcut: ⌘+ / ⌘−.")
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
    @AppStorage(SettingsKey.showMenuBarExtra) private var show = false
    @AppStorage(SettingsKey.menuBarShowsCPU) private var cpu = true
    @AppStorage(SettingsKey.menuBarShowsMemory) private var memory = true
    @AppStorage(SettingsKey.menuBarShowsNetwork) private var network = false

    var body: some View {
        Form {
            Toggle("Show in menu bar", isOn: $show)
            Section("Menu bar shows") {
                Toggle("CPU usage", isOn: $cpu)
                Toggle("Memory usage", isOn: $memory)
                Toggle("Network throughput", isOn: $network)
            }
            .disabled(!show)
        }
        .formStyle(.grouped)
    }
}
