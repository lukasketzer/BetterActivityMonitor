import AppKit
import ServiceManagement

/// Opening the app at login, through the system's login items. Only works from the .app bundle.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns an error message when the system refused the change.
    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return Bundle.main.bundleURL.pathExtension == "app"
                ? error.localizedDescription
                : "Only available when running the BetterActivityMonitor app bundle."
        }
    }

    /// Whether this launch was the system opening the app at login (read before launch finishes).
    static var launchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == kAEOpenApplication else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
