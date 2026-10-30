import SwiftUI

struct Theme: Identifiable, Hashable {
    let id: String
    let name: String
    var prefersDark = false
    var accent: Color
    var cpuUser: Color
    var cpuSystem: Color
    var memApp: Color
    var memWired: Color
    var memCompressed: Color
    var memCached: Color
    var swap: Color
    var netIn: Color
    var netOut: Color
    var diskRead: Color
    var diskWrite: Color
    var gpu: Color
    var temperature: Color
    var low: Color
    var mid: Color
    var high: Color

    var cpu: Color { cpuUser }

    /// btop-style green → yellow → red meter colour.
    func meter(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.5: low
        case ..<0.8: mid
        default: high
        }
    }

    func meterGradient() -> LinearGradient {
        LinearGradient(colors: [low, mid, high], startPoint: .leading, endPoint: .trailing)
    }
}

private func hex(_ value: UInt32) -> Color {
    Color(red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255, blue: Double(value & 0xff) / 255)
}

extension Theme {
    static let system = Theme(
        id: "system", name: "System", accent: .accentColor,
        cpuUser: .blue, cpuSystem: .red, memApp: .yellow, memWired: .orange, memCompressed: .purple,
        memCached: .teal, swap: .pink, netIn: .blue, netOut: .red, diskRead: .blue, diskWrite: .red,
        gpu: .indigo, temperature: .orange, low: .green, mid: .yellow, high: .red
    )

    static let btop = Theme(
        id: "btop", name: "btop Default", prefersDark: true, accent: hex(0xee4b2b),
        cpuUser: hex(0x77ca9b), cpuSystem: hex(0xcc486f), memApp: hex(0xeeb12a), memWired: hex(0xff6a4b),
        memCompressed: hex(0xa772d7), memCached: hex(0x0b93c7), swap: hex(0xdc4c4c), netIn: hex(0x83d3f2),
        netOut: hex(0xd45454), diskRead: hex(0x83d3f2), diskWrite: hex(0xd45454), gpu: hex(0x8e5ef0),
        temperature: hex(0xe5a03e), low: hex(0x50f095), mid: hex(0xf2e266), high: hex(0xfa1e1e)
    )

    static let nord = Theme(
        id: "nord", name: "Nord", prefersDark: true, accent: hex(0x88c0d0),
        cpuUser: hex(0x88c0d0), cpuSystem: hex(0xbf616a), memApp: hex(0xebcb8b), memWired: hex(0xd08770),
        memCompressed: hex(0xb48ead), memCached: hex(0x81a1c1), swap: hex(0xbf616a), netIn: hex(0x8fbcbb),
        netOut: hex(0xd08770), diskRead: hex(0x8fbcbb), diskWrite: hex(0xd08770), gpu: hex(0xb48ead),
        temperature: hex(0xd08770), low: hex(0xa3be8c), mid: hex(0xebcb8b), high: hex(0xbf616a)
    )

    static let dracula = Theme(
        id: "dracula", name: "Dracula", prefersDark: true, accent: hex(0xbd93f9),
        cpuUser: hex(0xbd93f9), cpuSystem: hex(0xff5555), memApp: hex(0xf1fa8c), memWired: hex(0xffb86c),
        memCompressed: hex(0xff79c6), memCached: hex(0x8be9fd), swap: hex(0xff5555), netIn: hex(0x8be9fd),
        netOut: hex(0xff79c6), diskRead: hex(0x8be9fd), diskWrite: hex(0xff79c6), gpu: hex(0xbd93f9),
        temperature: hex(0xffb86c), low: hex(0x50fa7b), mid: hex(0xf1fa8c), high: hex(0xff5555)
    )

    static let gruvbox = Theme(
        id: "gruvbox", name: "Gruvbox", prefersDark: true, accent: hex(0xfe8019),
        cpuUser: hex(0x8ec07c), cpuSystem: hex(0xfb4934), memApp: hex(0xfabd2f), memWired: hex(0xfe8019),
        memCompressed: hex(0xd3869b), memCached: hex(0x83a598), swap: hex(0xfb4934), netIn: hex(0x83a598),
        netOut: hex(0xfb4934), diskRead: hex(0x83a598), diskWrite: hex(0xfb4934), gpu: hex(0xd3869b),
        temperature: hex(0xfe8019), low: hex(0xb8bb26), mid: hex(0xfabd2f), high: hex(0xfb4934)
    )

    static let all: [Theme] = [.system, .btop, .nord, .dracula, .gruvbox]

    static func named(_ id: String) -> Theme { all.first { $0.id == id } ?? .system }
}

extension EnvironmentValues {
    @Entry var theme: Theme = .system
}
