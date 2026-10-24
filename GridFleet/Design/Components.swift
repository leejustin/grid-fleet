import SwiftUI

extension Theme {
    /// A flat card surface.
    var surface: Color { scheme == .dark ? .white.opacity(0.055) : .white.opacity(0.72) }
    /// A hairline around surfaces and between rows.
    var hairline: Color { ink.opacity(scheme == .dark ? 0.09 : 0.08) }
    /// Text on an accent fill.
    var onAccent: Color { scheme == .dark ? Color.black.opacity(0.88) : .white }
}

/// The animated ocean behind every screen. Quiet on purpose.
struct OceanBackdrop: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var strength: Double = 0.10
    /// Gameplay screens hold the backdrop still: it's mostly hidden behind boards, and redrawing it costs battery.
    var animated = true

    var body: some View {
        let ambient = animated && MotionBudget.shared.allowsAmbient(reduceMotion: reduceMotion) && !theme.isPaper
        // The backdrop drifts slowly, so a low frame rate looks the same and costs far less.
        TimelineView(.animation(minimumInterval: 1 / 12, paused: !ambient)) { timeline in
            let t = ambient ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000) : 0
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                context.fill(Path(rect), with: .linearGradient(Gradient(colors: [theme.backdropTop, theme.backdropBottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                Caustics.draw(in: context, rect: rect, time: t, color: theme.caustic, strength: theme.isPaper ? 0 : strength * 0.45, scale: 2.2)
            }
        }
        .overlay {
            if theme.isPaper { PaperGrain() }
        }
        .ignoresSafeArea()
    }
}

/// Faint ruled lines for the Graph Paper theme.
struct PaperGrain: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 22
            var path = Path()
            var x: CGFloat = 0
            while x < size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y < size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
            context.stroke(path, with: .color(theme.gridLine.opacity(0.35)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

/// Buttons. Sentence case, no glow.
struct FleetButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
    var kind: Kind = .primary
    var compact = false
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        // Disabled buttons go neutral rather than faded, so an off Fire button reads as off, and the
        // switch to the accent color when it turns on is easy to notice.
        let neutral = theme.ink.opacity(theme.scheme == .dark ? 0.1 : 0.07)
        let fill: Color = switch kind {
        case _ where !isEnabled: neutral
        case .primary: theme.accent
        case .secondary: neutral
        case .destructive: theme.danger
        }
        let foreground: Color = !isEnabled ? theme.inkSecondary.opacity(0.75) : (kind == .secondary ? theme.ink : theme.onAccent)
        configuration.label
            .font(compact ? .subheadline.weight(.semibold) : .headline)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? Space.m : Space.l)
            .frame(height: compact ? 36 : 50)
            .frame(maxWidth: compact ? nil : .infinity)
            .background(Capsule().fill(fill))
            .overlay {
                if !isEnabled, kind != .secondary {
                    Capsule().strokeBorder(theme.hairline, lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .animation(.smooth(duration: 0.2), value: isEnabled)
    }
}

extension ButtonStyle where Self == FleetButtonStyle {
    static var fleet: FleetButtonStyle { FleetButtonStyle() }
    static var fleetSecondary: FleetButtonStyle { FleetButtonStyle(kind: .secondary) }
    static func fleet(_ kind: FleetButtonStyle.Kind, compact: Bool = false) -> FleetButtonStyle { FleetButtonStyle(kind: kind, compact: compact) }
}

/// A round floating control. Liquid Glass belongs on floating controls, so it's used here and in the battle HUD only.
struct CircleIconButton: View {
    let systemImage: String
    var label: String
    var size: CGFloat = 40
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(theme.ink)
                .frame(width: size, height: size)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

extension View {
    /// A flat card with a hairline edge.
    func surface(_ radius: CGFloat = Radius.card) -> some View {
        modifier(SurfaceModifier(radius: radius))
    }

    /// Applies the theme to text colors and the system color scheme.
    func themed(_ theme: Theme) -> some View {
        self
            .environment(\.theme, theme)
            .foregroundStyle(theme.ink)
            .tint(theme.accent)
            .preferredColorScheme(theme.scheme)
    }
}

private struct SurfaceModifier: ViewModifier {
    let radius: CGFloat
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(theme.surface))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
    }
}

/// A short tag, like "Hard".
struct Chip: View {
    let text: String
    var tint: Color?
    @Environment(\.theme) private var theme

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint ?? theme.inkSecondary)
            .padding(.horizontal, Space.xs)
            .padding(.vertical, 3)
            .background(Capsule().fill((tint ?? theme.inkSecondary).opacity(0.14)))
    }
}

/// A row in a grouped list: icon, title, optional detail, trailing accessory.
struct ListRow<Trailing: View>: View {
    let systemImage: String
    let title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(theme.inkSecondary)
                }
            }
            Spacer(minLength: Space.xs)
            trailing
        }
        .foregroundStyle(theme.ink)
        .padding(.horizontal, Space.m)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

extension ListRow where Trailing == DisclosureChevron {
    init(systemImage: String, title: String, detail: String? = nil) {
        self.init(systemImage: systemImage, title: title, detail: detail) { DisclosureChevron() }
    }
}

struct DisclosureChevron: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(theme.inkSecondary.opacity(0.7))
    }
}

/// A divider inset to line up with row text.
struct RowDivider: View {
    var inset: CGFloat = Space.m + 28 + Space.s
    @Environment(\.theme) private var theme

    var body: some View {
        Rectangle().fill(theme.hairline).frame(height: 1).padding(.leading, inset)
    }
}

/// A titled group of content.
struct ContentSection<Content: View>: View {
    let title: String?
    var footer: String?
    @ViewBuilder var content: Content
    @Environment(\.theme) private var theme

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if let title {
                Text(title).sectionLabel().foregroundStyle(theme.inkSecondary).padding(.leading, Space.xxs)
            }
            content
            if let footer {
                Text(footer).font(.footnote).foregroundStyle(theme.inkSecondary).padding(.horizontal, Space.xxs)
            }
        }
    }
}

/// Scales down slightly while pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// A side-to-side shake for a hit on your fleet.
struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 7
    var shakes: CGFloat = 4
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let progress = animatableData - animatableData.rounded(.down)
        let decay = 1 - progress
        let x = amount * decay * sin(progress * .pi * 2 * shakes)
        let y = amount * 0.3 * decay * cos(progress * .pi * 2 * shakes * 1.3)
        return ProjectionTransform(CGAffineTransform(translationX: x, y: y))
    }
}

/// Shared screen scaffolding: ocean background, scrolling content at a readable width.
struct ScreenScroll<Content: View>: View {
    var maxWidth: CGFloat = 600
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            OceanBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    content
                }
                .padding(.horizontal, Space.l)
                .padding(.top, Space.xs)
                .padding(.bottom, Space.xxl)
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }
}

extension View {
    /// Large native title over the ocean background.
    func oceanNavigation(_ title: String) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}

/// A setting with a switch.
struct ToggleRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(theme.inkSecondary)
                }
            }
        }
        .tint(theme.accent)
        .foregroundStyle(theme.ink)
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .frame(minHeight: 52)
    }
}

/// A setting whose value is picked from a menu.
struct MenuRow<Value: Hashable, Options: View>: View {
    let title: String
    /// The current choice, as shown in the row.
    let value: String
    @Binding var selection: Value
    @ViewBuilder var options: Options
    @Environment(\.theme) private var theme

    var body: some View {
        Menu {
            Picker(title, selection: $selection) { options }
        } label: {
            HStack(spacing: Space.xs) {
                Text(title).font(.body).foregroundStyle(theme.ink)
                Spacer(minLength: Space.xs)
                Text(value).font(.body).foregroundStyle(theme.inkSecondary).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(theme.inkSecondary.opacity(0.7))
            }
            .padding(.horizontal, Space.m)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .accessibilityValue(value)
    }
}

/// A row that opens another screen, with the current value on the right.
struct ValueRow: View {
    let title: String
    var value: String?
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                Text(title).font(.body).foregroundStyle(theme.ink)
                Spacer(minLength: Space.xs)
                if let value {
                    Text(value).font(.body).foregroundStyle(theme.inkSecondary).lineLimit(1)
                }
                DisclosureChevron()
            }
            .padding(.horizontal, Space.m)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// A row that performs an action, with an optional value on the right.
struct ActionRow: View {
    let title: String
    var value: String?
    var role: ButtonRole?
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(role: role, action: action) {
            HStack {
                Text(title).font(.body).foregroundStyle(role == .destructive ? theme.danger : theme.accent)
                Spacer(minLength: Space.xs)
                if let value {
                    Text(value).font(.body).foregroundStyle(theme.inkSecondary).lineLimit(1)
                }
            }
            .padding(.horizontal, Space.m)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// A soft, breathing ring that points the eye at what a tip is talking about.
struct CoachPulse: View {
    var cornerRadius: CGFloat
    var spread: CGFloat = 0
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(theme.accent, lineWidth: 2)
            .padding(-spread)
            .shadow(color: theme.accent.opacity(lit ? 0.7 : 0.2), radius: lit ? 10 : 4)
            .opacity(reduceMotion ? 0.8 : (lit ? 0.95 : 0.35))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { lit = true }
            }
    }
}
