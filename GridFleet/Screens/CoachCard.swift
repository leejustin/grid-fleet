import SwiftUI

/// A first-game tip from Ensign Pip, floating at the bottom of the battle screen.
struct CoachCard: View {
    let text: String
    let number: Int
    let total: Int
    let onSkip: () -> Void

    @Environment(\.theme) private var theme
    @State private var visible = false

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            RivalFlag(rival: .pip, mood: .smug, talking: visible)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tip \(number) of \(total)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.accent)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: onSkip) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(theme.inkSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Skip tips")
        }
        .padding(.leading, Space.m)
        .padding(.trailing, Space.xs)
        .padding(.vertical, Space.s)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(theme.backdropBottom.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(theme.accent.opacity(0.55), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        .frame(maxWidth: 520)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tip from Ensign Pip: \(text)")
        .accessibilityAction(named: "Skip tips", onSkip)
        .task(id: text) {
            visible = false
            SoundBoard.shared.play(.radio, volume: 0.4)
            withAnimation(.spring(duration: 0.4, bounce: 0.2)) { visible = true }
            AccessibilityNotification.Announcement("Tip: \(text)").post()
        }
    }
}
