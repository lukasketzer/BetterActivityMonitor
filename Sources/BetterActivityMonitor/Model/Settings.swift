import Foundation

/// UserDefaults keys shared by `@AppStorage` call sites.
enum SettingsKey {
    static let refreshInterval = "refreshInterval"
    static let historyLength = "historyLength"
    static let theme = "theme"
    static let graphStyle = "graphStyle"
    static let backgroundGradient = "backgroundGradient"
    static let fahrenheit = "fahrenheit"
    static let cpuPerCore = "cpuPerCore"
    static let useRegex = "useRegex"
    static let confirmKill = "confirmKill"
    static let showMenuBarExtra = "showMenuBarExtra"
    static let menuBarShowsCPU = "menuBarShowsCPU"
    static let menuBarShowsMemory = "menuBarShowsMemory"
    static let menuBarShowsNetwork = "menuBarShowsNetwork"
    static let overviewCPU = "overview.cpu"
    static let overviewMemory = "overview.memory"
    static let overviewNetwork = "overview.network"
    static let overviewDisks = "overview.disks"
    static let overviewSensors = "overview.sensors"
    static let overviewGPU = "overview.gpu"
    static let overviewProcesses = "overview.processes"
    static let treeView = "treeView"
    static let processScope = "processScope"
    static let networkPage = "network.page"
    static let networkShowLoopback = "network.showLoopback"
    static let freezeDuringResize = "freezeDuringResize"
}

enum NetworkPage: String, CaseIterable, Identifiable {
    case overview, connections, listening, log
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum GraphStyle: String, CaseIterable, Identifiable {
    case area, line, bars
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum Defaults {
    static func register() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.refreshInterval: 1.0,
            SettingsKey.historyLength: 120,
            SettingsKey.theme: Theme.system.id,
            SettingsKey.graphStyle: GraphStyle.area.rawValue,
            SettingsKey.backgroundGradient: true,
            SettingsKey.fahrenheit: false,
            SettingsKey.cpuPerCore: true,
            SettingsKey.useRegex: false,
            SettingsKey.confirmKill: true,
            SettingsKey.showMenuBarExtra: false,
            SettingsKey.menuBarShowsCPU: true,
            SettingsKey.menuBarShowsMemory: true,
            SettingsKey.menuBarShowsNetwork: false,
            SettingsKey.overviewCPU: true,
            SettingsKey.overviewMemory: true,
            SettingsKey.overviewNetwork: true,
            SettingsKey.overviewDisks: true,
            SettingsKey.overviewSensors: true,
            SettingsKey.overviewGPU: true,
            SettingsKey.overviewProcesses: true,
            SettingsKey.freezeDuringResize: true,
            SettingsKey.treeView: false,
            SettingsKey.processScope: ProcessScope.all.rawValue,
            SettingsKey.networkPage: NetworkPage.overview.rawValue,
            SettingsKey.networkShowLoopback: false,
        ])
    }

    static var refreshInterval: Double {
        min(max(UserDefaults.standard.double(forKey: SettingsKey.refreshInterval), 0.25), 10)
    }

    static var historyLength: Int {
        min(max(UserDefaults.standard.integer(forKey: SettingsKey.historyLength), 30), 3600)
    }
}
