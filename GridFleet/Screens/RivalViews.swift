import GridFleetCore
import SwiftUI

/// A rival's remark, typed out as it arrives.
struct SpeechBubble: View {
    let line: RivalLine
    let rival: Rival
    @Environment(\.theme) private var theme
    @State private var shown = 0

    var body: some View {
        let characters = Array(line.text)
        Text(String(characters.prefix(shown)))
            .font(.subheadline.weight(.medium))
            .foregroundStyle(theme.ink)
            .frame(maxWidth: 230, alignment: .leading)
            .background(alignment: .topLeading) {
                // Reserve the final size so the bubble doesn't grow while typing.
                Text(line.text).font(.subheadline.weight(.medium)).frame(maxWidth: 230, alignment: .leading).hidden()
            }
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs + 2)
            .background {
                BubbleShape()
                    .fill(theme.backdropBottom.opacity(0.94))
                    .overlay(BubbleShape().stroke(theme.hairline, lineWidth: 1))
            }
            .task(id: line.id) {
                shown = 0
                SoundBoard.shared.play(.radio, volume: 0.4)
                for i in 1...max(1, characters.count) {
                    shown = i
                    try? await Task.sleep(for: .milliseconds(18))
                }
            }
            .accessibilityLabel("\(rival.fullName): \(line.text)")
    }
}

/// A rival's remark typed out under their name.
struct TypedLine: View {
    let line: RivalLine
    let rival: Rival
    @Environment(\.theme) private var theme
    @State private var shown = 0

    var body: some View {
        let characters = Array(line.text)
        Text(String(characters.prefix(shown)))
            .font(.footnote.italic())
            .foregroundStyle(theme.ink)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .topLeading) {
                Text(line.text).font(.footnote.italic()).lineLimit(2).hidden()
            }
            .task(id: line.id) {
                shown = 0
                SoundBoard.shared.play(.radio, volume: 0.4)
                for i in 1...max(1, characters.count) {
                    shown = i
                    try? await Task.sleep(for: .milliseconds(18))
                }
            }
            .accessibilityLabel("\(rival.fullName) says: \(line.text)")
    }
}

/// A rounded bubble with a small tail at the top left, toward the portrait above it.
nonisolated struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(roundedRect: rect, cornerRadius: 14, style: .continuous)
        p.move(to: CGPoint(x: rect.minX + 14, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + 20, y: rect.minY - 6))
        p.addLine(to: CGPoint(x: rect.minX + 26, y: rect.minY))
        return p
    }
}

/// The face-off before a battle with the computer.
struct RivalIntro: View {
    let rival: Rival
    let captain: String
    let line: RivalLine?
    let onDone: () -> Void

    @Environment(\.theme) private var theme
    @State private var stage = 0

    var body: some View {
        ZStack {
            theme.backdropBottom.ignoresSafeArea()
            RadialGradient(colors: [rival.flag.color.opacity(0.18), .clear], center: .center, startRadius: 0, endRadius: 360)
                .ignoresSafeArea()
                .opacity(stage >= 1 ? 1 : 0)
            VStack(spacing: Space.xl) {
                Spacer()
                // The flag runs up, as if hoisted.
                RivalFlag(rival: rival, mood: line?.mood ?? .neutral, talking: stage == 2)
                    .frame(width: 96, height: 96)
                    .offset(y: stage >= 1 ? 0 : 40)
                    .opacity(stage >= 1 ? 1 : 0)
                VStack(spacing: Space.xs) {
                    Text(rival.fullName).font(.title.weight(.bold))
                    Text(rival.tagline).font(.subheadline).foregroundStyle(theme.inkSecondary)
                    Text("Flies \(rival.flag.name)").font(.caption).foregroundStyle(theme.inkSecondary.opacity(0.8))
                }
                .opacity(stage >= 1 ? 1 : 0)
                if let line {
                    Text("“\(line.text)”")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Space.l)
                        .padding(.vertical, Space.m)
                        .frame(maxWidth: 340)
                        .surface()
                        .opacity(stage >= 2 ? 1 : 0)
                        .offset(y: stage >= 2 ? 0 : 8)
                }
                Spacer()
                Text("Tap to begin").font(.footnote).foregroundStyle(theme.inkSecondary).opacity(stage >= 2 ? 1 : 0)
            }
            .foregroundStyle(theme.ink)
            .padding(Space.xl)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("rival-intro")
        .accessibilityAddTraits(.isButton)
        .onTapGesture {
            if stage < 3 { Analytics.shared.capture("rival_intro_skipped", ["rival": .string(rival.id.rawValue), "stage": .int(stage)]) }
            finish()
        }
        .task {
            withAnimation(.smooth(duration: 0.45)) { stage = 1 }
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation(.smooth(duration: 0.35)) { stage = 2 }
            SoundBoard.shared.play(.radio, volume: 0.4)
            #if DEBUG
            // The screenshot scene holds the face-off on screen.
            if DemoDirector.scene == "intro" { return }
            #endif
            try? await Task.sleep(for: .seconds(2.6))
            finish()
        }
        .accessibilityAction(named: "Begin") { finish() }
    }

    private func finish() {
        guard stage < 3 else { return }
        stage = 3
        onDone()
    }
}

#if DEBUG
/// Every rival in every mood, for checking the drawings.
struct RivalGallery: View {
    private let moods: [RivalMood] = [.neutral, .smug, .happy, .angry, .shocked, .defeated]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                ForEach([Rival.pip, .gale, .thorn]) { rival in
                    Text(rival.fullName).font(.headline)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3)) {
                        ForEach(Array(moods.enumerated()), id: \.offset) { _, mood in
                            RivalFlag(rival: rival, mood: mood, talking: mood == .happy).frame(width: 100, height: 100)
                        }
                    }
                }
            }
            .padding()
        }
        .background(OceanBackdrop())
    }
}
#endif
