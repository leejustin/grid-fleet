import SwiftUI

/// Pass and play: hides the board while the phone changes hands.
struct HandoffView: View {
    enum Reason { case passTo, hidden }

    let name: String
    let reason: Reason
    var detail: String?
    let onReady: () -> Void

    @Environment(\.theme) private var theme
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            OceanBackdrop()
            VStack(spacing: Space.xl) {
                Spacer()
                Image(systemName: reason == .passTo ? "arrow.left.arrow.right" : "eye.slash")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(theme.accent.opacity(0.12)))
                VStack(spacing: Space.xs) {
                    Text(reason == .passTo ? "Pass to \(name)" : "Fleet hidden")
                        .font(.title.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(detail ?? (reason == .passTo ? "Everyone else, look away." : "Only \(name) should look."))
                        .font(.body)
                        .foregroundStyle(theme.inkSecondary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
                holdButton
            }
            .foregroundStyle(theme.ink)
            .padding(Space.l)
            .padding(.bottom, Space.l)
        }
        .accessibilityAction(named: "I'm \(name)") { onReady() }
    }

    /// Press and hold, so a stray tap doesn't reveal the fleet.
    private var holdButton: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(theme.ink.opacity(0.08))
            GeometryReader { proxy in
                Capsule().fill(theme.accent).frame(width: max(50, proxy.size.width * progress))
                    .opacity(progress > 0 ? 1 : 0)
            }
            Text("Hold to show \(name)'s fleet")
                .font(.headline)
                .foregroundStyle(progress > 0.5 ? theme.onAccent : theme.ink)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 50)
        .frame(maxWidth: 420)
        .onLongPressGesture(minimumDuration: 0.6, maximumDistance: 40) {
            Haptics.hit()
            onReady()
        } onPressingChanged: { pressing in
            if pressing {
                Haptics.tap()
                withAnimation(.linear(duration: 0.6)) { progress = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
            }
        }
        .accessibilityLabel("Show \(name)'s fleet")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("handoff-hold")
    }
}
