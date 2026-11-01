import Foundation
import ServiceManagement

/// Registers the background history agent with launchd (SMAppService), so history keeps recording
/// while the app is closed. It shows up in System Settings → General → Login Items.
@MainActor
final class HistoryAgentService {
    static let plistName = "dev.lukas.BetterActivityMonitor.HistoryAgent.plist"

    private var service: SMAppService { .agent(plistName: Self.plistName) }

    /// False for a bare `swift run` binary, which has no bundle to carry the agent.
    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchAgents/\(Self.plistName)").path)
    }

    var status: SMAppService.Status { service.status }

    /// Brings the registration in line with the setting. Returns an error message to show, if any.
    @discardableResult
    func sync(enabled: Bool) -> String? {
        guard isAvailable else { return enabled ? "This build doesn't include the history agent." : nil }
        do {
            switch (enabled, service.status) {
            case (true, .notRegistered), (true, .notFound): try service.register()
            case (false, .enabled), (false, .requiresApproval): try service.unregister()
            default: break
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }

    static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: "Recording in the background."
        case .requiresApproval: "Waiting for approval in System Settings → Login Items."
        case .notRegistered: "Not recording."
        case .notFound: "The agent couldn't be found in the app bundle."
        @unknown default: "Unknown state."
        }
    }
}
