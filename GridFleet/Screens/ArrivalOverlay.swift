import SwiftUI

/// The moment two phones find each other across the table: both captains take their seats and a coin
/// decides who fires first.
struct ArrivalOverlay: View {
    let myName: String
    let partnerName: String
    let iFireFirst: Bool
    let onDone: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var seated = false
    @State private var landed = false
    @State private var flip: Double = 0

    var body: some View {
        ZStack {
            theme.backdropBottom.opacity(0.94).ignoresSafeArea()
            VStack(spacing: Space.xl) {
                Seat(name: partnerName, caption: "Across the table", isMe: false)
                    .offset(y: seated ? 0 : -40)
                    .opacity(seated ? 1 : 0)

                Coin(front: initial(myName), back: initial(partnerName), angle: flip)
                    .frame(width: 112, height: 112)
                    .opacity(seated ? 1 : 0)

                VStack(spacing: Space.xxs) {
                    Text(iFireFirst ? "You fire first" : "\(partnerName) fires first")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(theme.ink)
                    Text("Deploy your fleet, then the battle begins.")
                        .font(.subheadline)
                        .foregroundStyle(theme.inkSecondary)
                }
                .multilineTextAlignment(.center)
                .opacity(landed ? 1 : 0)
                .offset(y: landed ? 0 : 8)

                Seat(name: myName, caption: "You", isMe: true)
                    .offset(y: seated ? 0 : 40)
                    .opacity(seated ? 1 : 0)
            }
            .padding(Space.xl)
            .frame(maxWidth: 420)
        }
        .contentShape(Rectangle())
        .onTapGesture { if landed { onDone() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Connected with \(partnerName). \(iFireFirst ? "You fire first" : "\(partnerName) fires first").")
        .accessibilityAddTraits(.isModal)
        .accessibilityAction { onDone() }
        .task { await play() }
    }

    private func play() async {
        SoundBoard.shared.play(.radio, volume: 0.7)
        Haptics.tap()
        withAnimation(.spring(duration: 0.5, bounce: 0.25)) { seated = true }
        try? await Task.sleep(for: .seconds(0.55))
        // Whole turns land on my face; a half turn more lands on theirs.
        let target = 360.0 * (reduceMotion ? 0 : 4) + (iFireFirst ? 0 : 180)
        if reduceMotion {
            flip = target
        } else {
            withAnimation(.timingCurve(0.2, 0.7, 0.25, 1, duration: 1.3)) { flip = target }
            for i in 0..<6 {
                try? await Task.sleep(for: .seconds(0.06 + Double(i) * 0.035))
                SoundBoard.shared.play(.tap, volume: 0.35)
            }
            try? await Task.sleep(for: .seconds(0.55))
        }
        SoundBoard.shared.play(.peg)
        Haptics.hit()
        withAnimation(.easeOut(duration: 0.3)) { landed = true }
        try? await Task.sleep(for: .seconds(2.2))
        onDone()
    }

    private func initial(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }
}

private struct Seat: View {
    let name: String
    let caption: String
    let isMe: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 2) {
            Text(caption.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(theme.inkSecondary)
            Text(name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(isMe ? theme.accent : theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
        .frame(minWidth: 180)
        .surface()
    }
}

/// A coin with a captain's initial on each face, flipping end over end.
private struct Coin: View, Animatable {
    let front: String
    let back: String
    var angle: Double
    @Environment(\.theme) private var theme

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        let showsFront = cos(angle * .pi / 180) >= 0
        ZStack {
            Circle().fill(showsFront ? theme.accent : theme.ink.opacity(0.9))
            Circle().strokeBorder(.black.opacity(0.18), lineWidth: 6)
            Circle().inset(by: 10).strokeBorder(.white.opacity(0.35), lineWidth: 1)
            Text(showsFront ? front : back)
                .font(.system(size: 44, weight: .bold, design: .serif))
                .foregroundStyle(theme.backdropBottom)
                // Undo the flip on the back face so its letter reads the right way up.
                .scaleEffect(y: showsFront ? 1 : -1)
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
        .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
    }
}
