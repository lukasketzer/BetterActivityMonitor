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
                    if let section = url.host().flatMap(AppSection.resolve) { store.section = section }
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
    /// Opened at login with the menu bar item on: start as a menu-bar-only app, without the window.
    private var startHidden = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        startHidden = (LoginItem.launchedAtLogin || CommandLine.arguments.contains("--hidden"))
            && UserDefaults.standard.bool(forKey: SettingsKey.showMenuBarExtra)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`) rather than from the .app bundle.
        NSApp.setActivationPolicy(startHidden ? .accessory : .regular)
        // Show our exact artwork in the Dock: the system-styled icon gets a white glass rim on macOS 26+.
        // Unbundled (`swift run`) the icon comes from the repo instead.
        let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("../../Resources/AppIcon.icns").standardized
        NSApp.applicationIconImage = NSImage(contentsOf: icon)
        observeMainWindow()
        if startHidden {
            // SwiftUI opens the main window on launch; close it as soon as it exists.
            DispatchQueue.main.async {
                NSApp.closeAppWindows()
                NSApp.setActivationPolicy(.accessory)
                self.startHidden = false
            }
        } else {
            NSApp.activate()
        }
        DebugSnapshot.runIfRequested()
        MenuBarSnapshot.runIfRequested()
        ResizeBench.runIfRequested()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: SettingsKey.showMenuBarExtra)
    }

    /// With the menu bar item on, closing the main window leaves a menu-bar-only app (no Dock icon, no app
    /// menu); opening it again from the menu bar brings the Dock icon back.
    private func observeMainWindow() {
        let isMain = { (note: Notification) in
            (note.object as? NSWindow)?.identifier?.rawValue.hasPrefix("main") == true
        }
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            guard isMain(note), UserDefaults.standard.bool(forKey: SettingsKey.showMenuBarExtra) else { return }
            NSApp.setActivationPolicy(.accessory)
        }
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            guard isMain(note), self?.startHidden != true, NSApp.activationPolicy() != .regular else { return }
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
    }
}

extension NSApplication {
    /// Closes the main and Settings windows, leaving the menu bar item.
    func closeAppWindows() {
        for window in windows where window.styleMask.contains(.titled) && window.isVisible {
            window.close()
        }
    }
}

struct AppCommands: Commands {
    @Bindable var store: SystemStore
    @AppStorage(SettingsKey.treeView) private var tree = false
    @AppStorage(SettingsKey.refreshInterval) private var interval = 1.0
    @AppStorage(SettingsKey.showMenuBarExtra) private var showMenuBarExtra = false

    private var milliseconds: Binding<Int> {
        Binding { RefreshInterval.nearestPreset(Int((interval * 1000).rounded())) } set: { RefreshInterval.set($0) }
    }

    var body: some Commands {
        // With the menu bar item on, ⌘Q only closes the windows; ⌥⌘Q (or Quit in the popover) really quits.
        // Logout, shutdown and the Dock's Quit call terminate directly and are unaffected.
        CommandGroup(replacing: .appTermination) {
            if showMenuBarExtra {
                Button("Close to Menu Bar") { NSApp.closeAppWindows() }
                    .keyboardShortcut("q", modifiers: .command)
                Button("Quit BetterActivityMonitor") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: [.command, .option])
            } else {
                Button("Quit BetterActivityMonitor") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
        }

        CommandGroup(after: .sidebar) {
            Divider()
            // Don't make this list depend on an @AppStorage setting (e.g. the hidden sidebar pages): that sent
            // SwiftUI into a permanent re-evaluation loop that pegged a core and froze the app.
            ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                Button(section.title) { store.section = section }
                    .keyboardShortcut(AppSection.shortcut(index: index).map { KeyboardShortcut($0, modifiers: .command) })
            }
            Divider()
            Picker("Update Interval", selection: milliseconds) {
                ForEach(RefreshInterval.presets, id: \.self) { Text(RefreshInterval.label($0)).tag($0) }
            }
            .pickerStyle(.menu)
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
