import Foundation
import SystemKit

// Background agent that keeps the minute history while the app is closed. launchd starts it at login
// and keeps it alive (Resources/dev.lukas.BetterActivityMonitor.HistoryAgent.plist); the app registers
// and unregisters it through SMAppService from Settings → History. One sample every 15 s, one row a minute.

// BAM_HISTORY_DB points the agent at another file (scripts/measure-agent.sh).
let database = ProcessInfo.processInfo.environment["BAM_HISTORY_DB"].map { HistoryDatabase(url: URL(fileURLWithPath: $0)) }
    ?? HistoryDatabase()
let recorder = HistoryRecorder(database: database) {
    // Read on every prune, so a changed retention applies within the hour.
    HistorySettings.retentionDays(HistorySettings.appDefaults)
}

// Quit cleanly when launchd stops the agent (unregistering, logout).
signal(SIGTERM, SIG_IGN)
let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
term.setEventHandler { exit(0) }
term.resume()

Task.detached(priority: .utility) { await recorder.run() }
dispatchMain()
