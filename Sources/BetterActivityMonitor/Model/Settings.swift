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
    static let cpuCoresExpanded = "cpu.coresExpanded"
    static let sidebarHidden = "sidebar.hidden"
    static let sensorsExpanded = "sensors.expanded"
    static let memoryVirtualExpanded = "memory.virtualExpanded"
    static let useRegex = "useRegex"
    static let confirmKill = "confirmKill"
    static let showMenuBarExtra = "showMenuBarExtra"
    static let menuBarItems = "menuBar.items"
    static let menuBarStyle = "menuBar.style"
    static let menuBarColored = "menuBar.colored"
    static let menuBarSymbols = "menuBar.symbols"
    static let overviewCPU = "overview.cpu"
    static let overviewMemory = "overview.memory"
    static let overviewNetwork = "overview.network"
    static let overviewDisks = "overview.disks"
    static let overviewStorage = "overview.storage"
    static let overviewBattery = "overview.battery"
    static let overviewGPU = "overview.gpu"
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
        migrateMenuBarToggles()
        UserDefaults.standard.register(defaults: [
            SettingsKey.refreshInterval: 1.0,
            SettingsKey.historyLength: 120,
            SettingsKey.theme: Theme.system.id,
            SettingsKey.graphStyle: GraphStyle.area.rawValue,
            SettingsKey.backgroundGradient: true,
            SettingsKey.fahrenheit: false,
            SettingsKey.sidebarHidden: AppSection.defaultHidden,
            SettingsKey.cpuPerCore: true,
            SettingsKey.useRegex: false,
            SettingsKey.confirmKill: true,
            SettingsKey.showMenuBarExtra: false,
            SettingsKey.menuBarItems: MenuBarItems.default.rawValue,
            SettingsKey.menuBarStyle: MenuBarStyle.rings.rawValue,
            SettingsKey.menuBarColored: false,
            SettingsKey.menuBarSymbols: true,
            SettingsKey.overviewCPU: true,
            SettingsKey.overviewMemory: true,
            SettingsKey.overviewNetwork: true,
            SettingsKey.overviewDisks: true,
            SettingsKey.overviewStorage: true,
            SettingsKey.overviewBattery: true,
            SettingsKey.overviewGPU: true,
            SettingsKey.freezeDuringResize: true,
            SettingsKey.treeView: false,
            SettingsKey.processScope: ProcessScope.all.rawValue,
            SettingsKey.networkPage: NetworkPage.overview.rawValue,
            SettingsKey.networkShowLoopback: false,
        ])
    }

    /// Earlier versions stored three menu bar toggles; carry them over into the ordered list once.
    static func migrateMenuBarToggles(_ defaults: UserDefaults = .standard) {
        let old = ["menuBarShowsCPU", "menuBarShowsMemory", "menuBarShowsNetwork"]
        guard old.contains(where: { defaults.object(forKey: $0) != nil }) else { return }
        if defaults.object(forKey: SettingsKey.menuBarItems) == nil {
            let items = MenuBarItems.migrated(cpu: defaults.object(forKey: old[0]) as? Bool ?? true,
                                              memory: defaults.object(forKey: old[1]) as? Bool ?? true,
                                              network: defaults.object(forKey: old[2]) as? Bool ?? false)
            defaults.set(items.rawValue, forKey: SettingsKey.menuBarItems)
        }
        old.forEach(defaults.removeObject(forKey:))
    }

    static var refreshInterval: Double {
        min(max(UserDefaults.standard.double(forKey: SettingsKey.refreshInterval), 0.5), 60)
    }

    static var historyLength: Int {
        min(max(UserDefaults.standard.integer(forKey: SettingsKey.historyLength), 30), 3600)
    }
}
