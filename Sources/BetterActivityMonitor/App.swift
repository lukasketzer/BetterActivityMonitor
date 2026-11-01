import SwiftUI

@main
struct BetterActivityMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = SystemStore()
    @AppStorage(SettingsKey.showMenuBarExtra) private var showMenuBarExtra = false

    var body: some Scene {
        Window("BetterActivityMonitor", id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 900, minHeight: 560)
                // Widgets link to betteractivitymonitor://<section>.
                .onOpenURL { url in
                    if let section = url.host().flatMap(AppSection.init(rawValue:)) { store.section = section }
                }
        }
        .handlesExternalEvents(matching: ["*"])
        .defaultSize(width: 1280, height: 820)
        .commands { AppCommands(store: store) }

        Settings {
            SettingsView().environment(store)
        }

        MenuBarExtra(isInserted: $showMenuBarExtra) {
            MenuBarView().environment(store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`) rather than from the .app bundle.
        NSApp.setActivationPolicy(.regular)
        // Show our exact artwork in the Dock: the system-styled icon gets a white glass rim on macOS 26+.
        // Unbundled (`swift run`) the icon comes from the repo instead.
        let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("../../Resources/AppIcon.icns").standardized
        NSApp.applicationIconImage = NSImage(contentsOf: icon)
        NSApp.activate()
        DebugSnapshot.runIfRequested()
        MenuBarSnapshot.runIfRequested()
        ResizeBench.runIfRequested()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: SettingsKey.showMenuBarExtra)
    }
}

struct AppCommands: Commands {
    @Bindable var store: SystemStore
    @AppStorage(SettingsKey.treeView) private var tree = false

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()
            ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                Button(section.title) { store.section = section }
                    .keyboardShortcut(AppSection.shortcut(index: index), modifiers: .command)
            }
            Divider()
            Button("Faster Updates") { store.adjustRefresh(faster: true) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Slower Updates") { store.adjustRefresh(faster: false) }
                .keyboardShortcut("-", modifiers: .command)
        }

        CommandMenu("Process") {
            Button("Quit Process") { store.requestQuit(store.selection) }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(store.selection.isEmpty)
            Button("Force Quit Process") { store.requestForceQuit(store.selection) }
                .keyboardShortcut(.delete, modifiers: [.command, .option])
                .disabled(store.selection.isEmpty)
            Divider()
            Toggle("Show Inspector", isOn: $store.showInspector)
                .keyboardShortcut("i", modifiers: .command)
            Toggle("Tree View", isOn: $tree)
                .keyboardShortcut("t", modifiers: .command)
            Toggle("Pause Process List", isOn: $store.paused)
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Divider()
            Button("Show All Processes") {
                store.section = .processes
                store.filterText = ""
            }
            .keyboardShortcut("l", modifiers: .command)
        }
    }
}
