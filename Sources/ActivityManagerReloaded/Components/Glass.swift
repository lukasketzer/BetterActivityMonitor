import SwiftUI

/// Developer aid: `BAM_NO_GLASS=1` renders the pre-macOS 26 materials instead of Liquid Glass (for A/B profiling).
let glassDisabled = ProcessInfo.processInfo.environment["BAM_NO_GLASS"] != nil

extension View {
    /// Liquid Glass card on macOS 26+, translucent material on older systems.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 18, tint: Color? = nil, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *), !glassDisabled {
            self.glassEffect(interactive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint), in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(.separator.opacity(0.5)))
        }
    }

    /// Capsule-shaped glass for small badges and chips.
    @ViewBuilder
    func glassCapsule(tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *), !glassDisabled {
            self.glassEffect(Glass.regular.tint(tint), in: Capsule())
        } else {
            self.background(.thinMaterial, in: Capsule())
        }
    }
}

/// Groups glass views so they render (and morph) together, which is also cheaper for the GPU.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: Content

    init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26.0, *), !glassDisabled {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// Soft, theme-tinted backdrop so the glass panels have something to refract.
struct AmbientBackground: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let strength = scheme == .dark ? 0.22 : 0.14
        ZStack {
            Rectangle().fill(.background)
            RadialGradient(colors: [theme.cpuUser.opacity(strength), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 700)
            RadialGradient(colors: [theme.memCompressed.opacity(strength), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 800)
            RadialGradient(colors: [theme.netIn.opacity(strength * 0.7), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 600)
        }
        .ignoresSafeArea()
    }
}
