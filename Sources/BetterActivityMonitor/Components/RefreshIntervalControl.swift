import SwiftUI

/// btop-style `− 1000 ms +`: click − / + to step, or click the number and type a value.
struct RefreshIntervalControl: View {
    @AppStorage(SettingsKey.refreshInterval) private var interval = 1.0
    @State private var text = ""
    @FocusState private var editing: Bool

    private var milliseconds: Int { RefreshInterval.clamped(Int((interval * 1000).rounded())) }

    var body: some View {
        HStack(spacing: 2) {
            Button { set(RefreshInterval.step(milliseconds, faster: true)) } label: { Image(systemName: "minus") }
                .help("Update more often (⌘+)")
                .disabled(milliseconds <= RefreshInterval.range.lowerBound)
            TextField("Interval", text: $text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 44)
                .focused($editing)
                .onSubmit(commit)
                .onExitCommand {
                    text = "\(milliseconds)"
                    editing = false
                }
                .onChange(of: editing) { if !editing { commit() } }
            Text("ms").foregroundStyle(.secondary)
            Button { set(RefreshInterval.step(milliseconds, faster: false)) } label: { Image(systemName: "plus") }
                .help("Update less often (⌘−)")
                .disabled(milliseconds >= RefreshInterval.range.upperBound)
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 6)
        .help("How often everything updates, \(RefreshInterval.range.lowerBound)–\(RefreshInterval.range.upperBound) ms. Faster costs more CPU.")
        .onAppear { text = "\(milliseconds)" }
        .onChange(of: interval) { if !editing { text = "\(milliseconds)" } }
    }

    private func set(_ ms: Int) {
        RefreshInterval.set(ms)
        text = "\(ms)"
    }

    /// Out-of-range values snap to the nearest limit; anything unparsable reverts.
    private func commit() {
        if let ms = RefreshInterval.parse(text) { set(ms) } else { text = "\(milliseconds)" }
    }
}
