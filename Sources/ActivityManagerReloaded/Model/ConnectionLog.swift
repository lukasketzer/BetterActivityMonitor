import Foundation
import SystemKit

/// A connection appearing or disappearing between two samples.
struct ConnectionEvent: Identifiable, Hashable {
    enum Kind { case opened, closed }
    let id = UUID()
    var date: Date
    var kind: Kind
    var flow: NetworkFlow
}

enum ConnectionLog {
    static let capacity = 500

    /// Opened and closed flows between two samples. Unconnected sockets (no remote address) are skipped:
    /// they are mostly unbound UDP sockets that come and go constantly and would drown out the log.
    static func events(from old: [NetworkFlow], to new: [NetworkFlow], at date: Date) -> [ConnectionEvent] {
        let oldByID = Dictionary(old.lazy.filter(isLoggable).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let newByID = Dictionary(new.lazy.filter(isLoggable).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let opened = newByID.values.filter { oldByID[$0.id] == nil }
            .map { ConnectionEvent(date: date, kind: .opened, flow: $0) }
        let closed = oldByID.values.filter { newByID[$0.id] == nil }
            .map { ConnectionEvent(date: date, kind: .closed, flow: $0) }
        return (opened + closed).sorted { $0.flow.processName < $1.flow.processName }
    }

    private static func isLoggable(_ flow: NetworkFlow) -> Bool {
        !flow.isListening && !flow.remote.isWildcard
    }
}
