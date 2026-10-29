import SwiftUI
import AppKit

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum Palette {
    static let violet = Color(hex: 0x6B4DFF)
    static let violetDeep = Color(hex: 0x4A2BD6)
    static let lavender = Color(hex: 0xB9A7FF)
    static let coral = Color(hex: 0xFF6B7A)
    static let coralDeep = Color(hex: 0xE1465B)
    static let mint = Color(hex: 0x00B894)
    static let teal = Color(hex: 0x00CEC9)
    static let amber = Color(hex: 0xF3A712)
    static let sky = Color(hex: 0x4D9BFF)
    static let ink = Color(hex: 0x181322)
}

struct Theme {
    let scheme: ColorScheme

    var isDark: Bool { scheme == .dark }

    var canvas: Color {
        isDark ? Color(hex: 0x100D16) : Color(hex: 0xF7F4FB)
    }

    var surface: Color {
        isDark ? Color(hex: 0x1B1722) : Color.white
    }

    var surfaceLow: Color {
        isDark ? Color(hex: 0x241F2D) : Color(hex: 0xF1EBFA)
    }

    var surfaceHigh: Color {
        isDark ? Color(hex: 0x2D2738) : Color(hex: 0xE9E1F6)
    }

    var outline: Color {
        isDark ? Color.white.opacity(0.09) : Color(hex: 0x2E2540, opacity: 0.08)
    }

    var outlineStrong: Color {
        isDark ? Color.white.opacity(0.16) : Color(hex: 0x2E2540, opacity: 0.14)
    }

    var textPrimary: Color {
        isDark ? Color(hex: 0xF8F4FF) : Color(hex: 0x1A1424)
    }

    var textSecondary: Color {
        isDark ? Color(hex: 0xB9AEC9) : Color(hex: 0x6F657D)
    }

    var textTertiary: Color {
        isDark ? Color(hex: 0x8C829B) : Color(hex: 0x988DA7)
    }

    var primary: Color { Palette.violet }
    var primaryContainer: Color {
        isDark ? Color(hex: 0x34285F) : Color(hex: 0xEDE6FF)
    }
    var onPrimaryContainer: Color {
        isDark ? Color(hex: 0xD9CBFF) : Color(hex: 0x3D278F)
    }

    var secondary: Color { Palette.coral }
    var secondaryContainer: Color {
        isDark ? Color(hex: 0x4A2430) : Color(hex: 0xFFE7EA)
    }

    var success: Color { Palette.mint }
    var warning: Color { Palette.amber }
    var danger: Color { Palette.coral }

    var shadow: Color {
        isDark ? Color.black.opacity(0.34) : Color(hex: 0x35245C, opacity: 0.09)
    }

    var primaryGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0x7657FF), Color(hex: 0x5A38E8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var expressiveGradient: LinearGradient {
        LinearGradient(
            colors: [Palette.violet, Color(hex: 0xA76BFF), Palette.coral],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var softGradient: LinearGradient {
        LinearGradient(
            colors: isDark
                ? [Color(hex: 0x2A2138), Color(hex: 0x1B1722)]
                : [Color(hex: 0xF7F0FF), Color.white],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    func statusColor(_ status: SignatureStatus) -> Color {
        switch status {
        case .signed: return Palette.mint
        case .adHoc: return Palette.amber
        case .unsigned: return textSecondary
        case .invalid: return Palette.coral
        case .unsupported: return Palette.sky
        }
    }
}

// MARK: - Surfaces

struct CardSurface<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let padding: CGFloat
    let radius: CGFloat
    let tint: Color?
    let content: Content

    init(
        padding: CGFloat = 24,
        radius: CGFloat = 28,
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.radius = radius
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        let theme = Theme(scheme: scheme)
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tint ?? theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(theme.outline, lineWidth: 1)
            )
            .shadow(color: theme.shadow, radius: 22, x: 0, y: 14)
    }
}

struct InsetSurface<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let radius: CGFloat
    let content: Content

    init(radius: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.content = content()
    }

    var body: some View {
        let theme = Theme(scheme: scheme)
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(theme.surfaceLow)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(theme.outline, lineWidth: 1)
            )
    }
}

// MARK: - Text

struct Eyebrow: View {
    @Environment(\.colorScheme) private var scheme
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        let theme = Theme(scheme: scheme)
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(1.8)
            .foregroundStyle(theme.textTertiary)
    }
}

struct SectionTitle: View {
    @Environment(\.colorScheme) private var scheme
    let text: String
    let subtitle: String?

    init(_ text: String, subtitle: String? = nil) {
        self.text = text
        self.subtitle = subtitle
    }

    var body: some View {
        let theme = Theme(scheme: scheme)
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Badges

struct StatusBadge: View {
    @Environment(\.colorScheme) private var scheme
    let text: String
    let symbol: String
    let color: Color
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 9 : 11, weight: .bold))
            Text(text)
                .font(.system(size: compact ? 10 : 11.5, weight: .bold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 4 : 5)
        .background(Capsule().fill(color.opacity(scheme == .dark ? 0.16 : 0.11)))
        .overlay(Capsule().strokeBorder(color.opacity(0.16), lineWidth: 1))
    }
}

struct LiveDot: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 16, height: 16)
                .scaleEffect(pulse ? 1.35 : 0.8)
                .opacity(pulse ? 0 : 1)
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

// MARK: - Buttons

struct PrimaryPillStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    var compact = false
    var tint: Color = Palette.violet

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12.5 : 14.5, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 14 : 20)
            .frame(height: compact ? 34 : 46)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [tint.opacity(0.98), tint.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            .shadow(
                color: tint.opacity(configuration.isPressed ? 0.16 : 0.30),
                radius: configuration.isPressed ? 6 : 14,
                x: 0,
                y: configuration.isPressed ? 3 : 7
            )
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct TonalPillStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    var compact = false
    var tint: Color = Palette.violet

    func makeBody(configuration: Configuration) -> some View {
        let theme = Theme(scheme: scheme)
        configuration.label
            .font(.system(size: compact ? 12.5 : 14, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, compact ? 13 : 18)
            .frame(height: compact ? 34 : 44)
            .background(
                Capsule().fill(tint.opacity(theme.isDark ? 0.16 : 0.09))
            )
            .overlay(Capsule().strokeBorder(tint.opacity(0.16), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(isEnabled ? 1 : 0.42)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct GhostPillStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    var compact = false
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        let theme = Theme(scheme: scheme)
        configuration.label
            .font(.system(size: compact ? 12.5 : 13.5, weight: .semibold, design: .rounded))
            .foregroundStyle(tint ?? theme.textSecondary)
            .padding(.horizontal, compact ? 12 : 16)
            .frame(height: compact ? 32 : 40)
            .background(
                Capsule().fill(configuration.isPressed ? theme.surfaceLow : Color.clear)
            )
            .overlay(Capsule().strokeBorder(theme.outline, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.4)
    }
}

struct DestructivePillStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        let theme = Theme(scheme: scheme)
        configuration.label
            .font(.system(size: compact ? 12.5 : 13.5, weight: .semibold, design: .rounded))
            .foregroundStyle(theme.danger)
            .padding(.horizontal, compact ? 12 : 18)
            .frame(height: compact ? 32 : 42)
            .background(Capsule().fill(theme.danger.opacity(configuration.isPressed ? 0.15 : 0.08)))
            .overlay(Capsule().strokeBorder(theme.danger.opacity(0.18), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.4)
    }
}

struct IconCircleButton: View {
    @Environment(\.colorScheme) private var scheme
    let symbol: String
    let help: String
    var tint: Color?
    var size: CGFloat = 38
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let theme = Theme(scheme: scheme)
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(tint ?? theme.textSecondary)
                .frame(width: size, height: size)
                .background(Circle().fill(tint?.opacity(hover ? 0.14 : 0.08) ?? theme.surfaceLow))
                .overlay(Circle().strokeBorder(theme.outline, lineWidth: 1))
                .scaleEffect(hover ? 1.05 : 1)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) { hover = inside }
        }
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Segmented tabs

struct SegmentedTabs: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var selection: InspectorTab
    @Namespace private var namespace

    var body: some View {
        let theme = Theme(scheme: scheme)
        HStack(spacing: 3) {
            ForEach(InspectorTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                        selection = tab
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 12, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(selection == tab ? theme.textPrimary : theme.textSecondary)
                    .padding(.horizontal, 17)
                    .frame(height: 36)
                    .background {
                        if selection == tab {
                            Capsule()
                                .fill(theme.surface)
                                .matchedGeometryEffect(id: "selectedTab", in: namespace)
                                .shadow(color: theme.shadow, radius: 9, x: 0, y: 4)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(theme.surfaceLow))
        .overlay(Capsule().strokeBorder(theme.outline, lineWidth: 1))
    }
}

// MARK: - Inputs

struct OptionToggle: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    var subtitle: String?
    let symbol: String
    @Binding var isOn: Bool
    var isEnabled = true

    var body: some View {
        let theme = Theme(scheme: scheme)
        Button {
            guard isEnabled else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOn ? theme.primary : theme.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(isOn ? theme.primaryContainer : theme.surfaceLow)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Capsule()
                    .fill(isOn ? theme.primary : theme.surfaceHigh)
                    .frame(width: 36, height: 21)
                    .overlay(
                        Circle()
                            .fill(Color.white)
                            .frame(width: 15, height: 15)
                            .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
                            .offset(x: isOn ? 7.5 : -7.5)
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.72), value: isOn)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isOn ? theme.primaryContainer.opacity(theme.isDark ? 0.55 : 0.45) : theme.surfaceLow.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isOn ? theme.primary.opacity(0.18) : theme.outline, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.42)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

struct InfoRow: View {
    @Environment(\.colorScheme) private var scheme
    let label: String
    let value: String?
    var monospaced = false
    var copyable = false
    @State private var copied = false

    var body: some View {
        let theme = Theme(scheme: scheme)
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(theme.textTertiary)
                .frame(width: 88, alignment: .leading)

            Text(value ?? "—")
                .font(monospaced
                    ? .system(size: 11.5, weight: .medium, design: .monospaced)
                    : .system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(theme.textPrimary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if copyable, let value, !value.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                    withAnimation { copied = true }
                    Task {
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        await MainActor.run { withAnimation { copied = false } }
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(copied ? theme.success : theme.textTertiary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(theme.surfaceLow))
                }
                .buttonStyle(.plain)
                .help("复制")
            }
        }
    }
}

// MARK: - Background

struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = Theme(scheme: scheme)
        ZStack {
            theme.canvas

            GeometryReader { proxy in
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Palette.violet.opacity(theme.isDark ? 0.28 : 0.16), .clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: 380
                            )
                        )
                        .frame(width: 760, height: 760)
                        .offset(x: proxy.size.width * 0.72, y: -300)
                        .blur(radius: 26)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Palette.coral.opacity(theme.isDark ? 0.14 : 0.10), .clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: 300
                            )
                        )
                        .frame(width: 560, height: 560)
                        .offset(x: -180, y: proxy.size.height - 230)
                        .blur(radius: 38)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .ignoresSafeArea()

            DotField()
                .opacity(theme.isDark ? 0.25 : 0.42)
                .ignoresSafeArea()
        }
    }
}

private struct DotField: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = Theme(scheme: scheme)
        Canvas { context, size in
            let spacing: CGFloat = 28
            var path = Path()
            var y: CGFloat = 8
            while y < size.height {
                var x: CGFloat = 8
                while x < size.width {
                    path.addEllipse(in: CGRect(x: x, y: y, width: 1.3, height: 1.3))
                    x += spacing
                }
                y += spacing
            }
            context.fill(path, with: .color(theme.textPrimary.opacity(theme.isDark ? 0.055 : 0.045)))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Window helpers

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DraggableView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DraggableView: NSView {
        override var isOpaque: Bool { false }
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.zoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        window.minSize = NSSize(width: 1040, height: 720)
        if window.frame.width < 1000 {
            window.setContentSize(NSSize(width: 1180, height: 820))
            window.center()
        }
    }
}

struct AppMark: View {
    var size: CGFloat = 34

    var body: some View {
        Group {
            if let image = NSApp.applicationIconImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                        .fill(Palette.violet)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: size * 0.48, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        .shadow(color: Palette.violet.opacity(0.22), radius: 8, x: 0, y: 4)
    }
}
