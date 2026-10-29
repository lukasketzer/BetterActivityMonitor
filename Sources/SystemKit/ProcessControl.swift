import Darwin
import Foundation

public enum ProcessControl {
    public struct Signal: Sendable, Hashable, Identifiable {
        public var id: Int32 { number }
        public var number: Int32
        public var name: String
        public var summary: String
    }

    /// The same list btop offers in its signal menu.
    public static let signals: [Signal] = [
        Signal(number: SIGHUP, name: "SIGHUP", summary: "Hangup"),
        Signal(number: SIGINT, name: "SIGINT", summary: "Interrupt"),
        Signal(number: SIGQUIT, name: "SIGQUIT", summary: "Quit"),
        Signal(number: SIGILL, name: "SIGILL", summary: "Illegal instruction"),
        Signal(number: SIGTRAP, name: "SIGTRAP", summary: "Trace trap"),
        Signal(number: SIGABRT, name: "SIGABRT", summary: "Abort"),
        Signal(number: SIGEMT, name: "SIGEMT", summary: "EMT instruction"),
        Signal(number: SIGFPE, name: "SIGFPE", summary: "Floating point exception"),
        Signal(number: SIGKILL, name: "SIGKILL", summary: "Kill (cannot be caught)"),
        Signal(number: SIGBUS, name: "SIGBUS", summary: "Bus error"),
        Signal(number: SIGSEGV, name: "SIGSEGV", summary: "Segmentation fault"),
        Signal(number: SIGSYS, name: "SIGSYS", summary: "Bad system call"),
        Signal(number: SIGPIPE, name: "SIGPIPE", summary: "Broken pipe"),
        Signal(number: SIGALRM, name: "SIGALRM", summary: "Alarm clock"),
        Signal(number: SIGTERM, name: "SIGTERM", summary: "Terminate"),
        Signal(number: SIGURG, name: "SIGURG", summary: "Urgent I/O"),
        Signal(number: SIGSTOP, name: "SIGSTOP", summary: "Stop (cannot be caught)"),
        Signal(number: SIGTSTP, name: "SIGTSTP", summary: "Terminal stop"),
        Signal(number: SIGCONT, name: "SIGCONT", summary: "Continue"),
        Signal(number: SIGCHLD, name: "SIGCHLD", summary: "Child status changed"),
        Signal(number: SIGTTIN, name: "SIGTTIN", summary: "Background read"),
        Signal(number: SIGTTOU, name: "SIGTTOU", summary: "Background write"),
        Signal(number: SIGIO, name: "SIGIO", summary: "I/O possible"),
        Signal(number: SIGXCPU, name: "SIGXCPU", summary: "CPU time limit"),
        Signal(number: SIGXFSZ, name: "SIGXFSZ", summary: "File size limit"),
        Signal(number: SIGVTALRM, name: "SIGVTALRM", summary: "Virtual alarm"),
        Signal(number: SIGPROF, name: "SIGPROF", summary: "Profiling alarm"),
        Signal(number: SIGWINCH, name: "SIGWINCH", summary: "Window size change"),
        Signal(number: SIGINFO, name: "SIGINFO", summary: "Info request"),
        Signal(number: SIGUSR1, name: "SIGUSR1", summary: "User signal 1"),
        Signal(number: SIGUSR2, name: "SIGUSR2", summary: "User signal 2"),
    ]

    public enum Failure: Error, Sendable {
        case permissionDenied
        case noSuchProcess
        case other(Int32)

        public var message: String {
            switch self {
            case .permissionDenied: "Permission denied. The process belongs to another user."
            case .noSuchProcess: "The process no longer exists."
            case .other(let code): String(cString: strerror(code))
            }
        }
    }

    public static func send(_ signal: Int32, to pid: pid_t) -> Result<Void, Failure> {
        kill(pid, signal) == 0 ? .success(()) : .failure(failure(errno))
    }

    public static func setPriority(_ nice: Int, of pid: pid_t) -> Result<Void, Failure> {
        setpriority(PRIO_PROCESS, id_t(pid), Int32(nice)) == 0 ? .success(()) : .failure(failure(errno))
    }

    /// Runs a shell command through the standard macOS administrator prompt.
    public static func runAsAdmin(_ command: String) -> Result<Void, Failure> {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?.executeAndReturnError(&error)
        return error == nil ? .success(()) : .failure(.other(EPERM))
    }

    private static func failure(_ code: Int32) -> Failure {
        switch code {
        case EPERM, EACCES: .permissionDenied
        case ESRCH: .noSuchProcess
        default: .other(code)
        }
    }
}
