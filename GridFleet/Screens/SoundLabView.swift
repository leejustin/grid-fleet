#if DEBUG
import SwiftUI

/// Developer screen for auditioning each sound and haptic and tuning sound levels on a real device.
struct SoundLabView: View {
    @Environment(\.theme) private var theme
    @State private var gains: [SoundBoard.Sound: Float] = Dictionary(
        uniqueKeysWithValues: SoundBoard.Sound.allCases.map { ($0, SoundBoard.shared.gain(for: $0)) }
    )

    private let haptics: [(String, @MainActor () -> Void)] = [
        ("Aim", Haptics.aim), ("Fire", Haptics.fire), ("Splash", Haptics.splash), ("Hit", Haptics.hit),
        ("Take hit", Haptics.takeHit), ("Sunk", Haptics.sunk), ("Warning", Haptics.warning), ("Tap", Haptics.tap),
        ("Periscope", Haptics.periscope), ("Victory", Haptics.victory), ("Defeat", Haptics.defeat),
    ]

    var body: some View {
        ScreenScroll {
            ContentSection("Sounds", footer: "Levels are saved on this device and apply everywhere the sound plays.") {
                VStack(spacing: 0) {
                    ForEach(Array(SoundBoard.Sound.allCases.enumerated()), id: \.element) { index, sound in
                        if index > 0 { RowDivider(inset: Space.m) }
                        soundRow(sound)
                    }
                }
                .surface()
            }

            ContentSection("Haptics", footer: "Haptics only play on a real device.") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: Space.xs)], spacing: Space.xs) {
                    ForEach(haptics, id: \.0) { name, play in
                        Button(name) { play() }
                            .buttonStyle(FleetButtonStyle(kind: .secondary))
                    }
                }
            }

            Button("Reset all levels") {
                for sound in SoundBoard.Sound.allCases {
                    SoundBoard.shared.setGain(1, for: sound)
                    gains[sound] = 1
                }
            }
            .buttonStyle(FleetButtonStyle(kind: .secondary))
        }
        .oceanNavigation("Sound lab")
    }

    private func soundRow(_ sound: SoundBoard.Sound) -> some View {
        let binding = Binding<Float>(
            get: { gains[sound] ?? 1 },
            set: { gains[sound] = $0; SoundBoard.shared.setGain($0, for: sound) }
        )
        return HStack(spacing: Space.s) {
            Button {
                SoundBoard.shared.play(sound)
            } label: {
                Image(systemName: "play.fill")
                    .font(.body)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(theme.accent.opacity(0.16)))
                    .foregroundStyle(theme.accent)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Play \(sound.rawValue)")
            Text(sound.rawValue.capitalized).font(.body).frame(width: 92, alignment: .leading)
            Slider(value: binding, in: 0...1.5, onEditingChanged: { editing in
                if !editing { SoundBoard.shared.play(sound) }
            })
            .tint(theme.accent)
            Text("\(Int(((gains[sound] ?? 1) * 100).rounded()))%")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(theme.inkSecondary)
                .frame(width: 44, alignment: .trailing)
        }
        .foregroundStyle(theme.ink)
        .padding(.horizontal, Space.m)
        .frame(minHeight: 56)
    }
}
#endif
