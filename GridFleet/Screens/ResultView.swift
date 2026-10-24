import GridFleetCore
import SwiftUI

/// The end of a battle: the verdict, the numbers, and both fleets laid bare.
struct ResultView: View {
    let outcome: BattleOutcome
    let session: BattleSession
    var onRematch: (() -> Void)?
    var onDone: () -> Void

    @Environment(\.theme) private var theme
    @State private var appeared = false
    @State private var shareImage: Image?

    var body: some View {
        ZStack {
            OceanBackdrop(strength: 0.04, animated: false)
            Rectangle().fill(theme.backdropBottom.opacity(0.6)).ignoresSafeArea()
            ScrollView {
                VStack(spacing: Space.xl) {
                    headline
                    if let rival = session.rival, let line = session.finalLine { quote(rival, line) }
                    if !outcome.medals.isEmpty { medals }
                    stats
                    boards
                    if let audit = outcome.audit {
                        AuditBadge(audit: audit)
                    } else if session.revealedEnemyFleet == nil, session.rival == nil, session.opponentDetail != "Pass & Play" {
                        Text("Their fleet appears once they open the match.")
                            .font(.footnote)
                            .foregroundStyle(theme.inkSecondary)
                    }
                }
                .padding(.horizontal, Space.l)
                .padding(.top, Space.xxl)
                .padding(.bottom, Space.l)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
            }
            .scrollIndicators(.hidden)
            // The actions stay on screen however long the result is.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                buttons
                    .padding(.horizontal, Space.l)
                    .padding(.top, Space.m)
                    .padding(.bottom, Space.xs)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .background {
                        LinearGradient(stops: [
                            .init(color: theme.backdropBottom.opacity(0), location: 0),
                            .init(color: theme.backdropBottom.opacity(0.97), location: 0.22),
                            .init(color: theme.backdropBottom, location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                            .padding(.top, -Space.l)
                            .ignoresSafeArea()
                    }
                    .opacity(appeared ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.5)) { appeared = true }
            renderShareImage()
        }
    }

    private var headline: some View {
        VStack(spacing: Space.xs) {
            Text("vs \(session.opponentName) · \(session.rules.summary)")
                .font(.subheadline)
                .foregroundStyle(theme.inkSecondary)
            Text(outcome.headline)
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(outcome.won ? theme.ink : theme.danger)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(outcome.detail)
                .font(.body)
                .foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Space.l)
        .accessibilityElement(children: .combine)
    }

    private func quote(_ rival: Rival, _ line: RivalLine) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            RivalFlag(rival: rival, mood: line.mood)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(rival.fullName).font(.caption.weight(.semibold)).foregroundStyle(theme.inkSecondary)
                Text("“\(line.text)”").font(.body)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.m)
        .surface()
        .accessibilityElement(children: .combine)
    }

    private var medals: some View {
        ContentSection("Medals") {
            HStack(alignment: .top, spacing: Space.m) {
                ForEach(Array(outcome.medals.enumerated()), id: \.element) { index, medal in
                    VStack(spacing: Space.xs) {
                        MedalBadge(medal: medal, size: 48)
                        Text(medal.title).font(.caption).multilineTextAlignment(.center).lineLimit(2)
                    }
                    .frame(width: 76)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .animation(.spring(response: 0.45, dampingFraction: 0.7).delay(0.25 + Double(index) * 0.1), value: appeared)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.m)
            .surface()
        }
        .task {
            for index in outcome.medals.indices {
                try? await Task.sleep(for: .seconds(index == 0 ? 0.3 : 0.1))
                SoundBoard.shared.play(.aim, volume: 0.6)
            }
        }
    }

    private var stats: some View {
        let accuracy = Int((outcome.stats.accuracy * 100).rounded())
        return Grid(horizontalSpacing: 0, verticalSpacing: Space.m) {
            GridRow {
                stat("Accuracy", "\(accuracy)%")
                stat("Shots", "\(outcome.stats.shotsFired)")
                stat("Hits", "\(outcome.stats.hits)")
            }
            Rectangle().fill(theme.hairline).frame(height: 1).gridCellColumns(3)
            GridRow {
                stat("Turns", "\(outcome.turns)")
                stat("Ships lost", "\(outcome.shipsLost)")
                stat("Time", Duration.seconds(outcome.duration).formatted(.time(pattern: .minuteSecond)))
            }
        }
        .padding(.vertical, Space.m)
        .surface()
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(theme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var boards: some View {
        HStack(alignment: .top, spacing: Space.m) {
            VStack(spacing: Space.xs) {
                BoardView(scene: BoardScene.target(session.target, revealed: session.revealedEnemyFleet), showsLabels: false)
                Text("Their waters").font(.caption).foregroundStyle(theme.inkSecondary)
            }
            VStack(spacing: Space.xs) {
                BoardView(scene: BoardScene.ocean(session.ocean), showsLabels: false)
                Text("Your fleet").font(.caption).foregroundStyle(theme.inkSecondary)
            }
        }
    }

    private var buttons: some View {
        VStack(spacing: Space.s) {
            if let onRematch {
                Button("Rematch", action: onRematch).buttonStyle(.fleet)
            }
            HStack(spacing: Space.s) {
                if let shareImage {
                    ShareLink(item: shareImage, preview: SharePreview(outcome.headline, image: shareImage)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.fleet(.secondary))
                }
                Button("Done", action: onDone).buttonStyle(.fleet(.secondary))
            }
        }
    }

    private func renderShareImage() {
        let card = ShareCard(outcome: outcome, opponent: session.opponentName, rules: session.rules)
            .environment(\.theme, theme)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        if let image = renderer.uiImage { shareImage = Image(uiImage: image) }
    }
}

/// A square card for sharing a result.
private struct ShareCard: View {
    let outcome: BattleOutcome
    let opponent: String
    let rules: GameRules
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Grid Fleet").font(.wordmark(15)).foregroundStyle(theme.accent)
            Spacer()
            Text(outcome.headline).font(.system(size: 40, weight: .bold))
            Text("vs \(opponent) · \(rules.summary)").font(.subheadline).foregroundStyle(theme.inkSecondary)
            HStack(spacing: Space.xl) {
                figure("\(Int((outcome.stats.accuracy * 100).rounded()))%", "accuracy")
                figure("\(outcome.turns)", "turns")
                figure("\(outcome.shipsLost)", "ships lost")
            }
        }
        .foregroundStyle(theme.ink)
        .padding(Space.xxl)
        .frame(width: 360, height: 360, alignment: .leading)
        .background(LinearGradient(colors: [theme.backdropTop, theme.backdropBottom], startPoint: .top, endPoint: .bottom))
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.title2.weight(.semibold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(theme.inkSecondary)
        }
    }
}

struct AuditBadge: View {
    let audit: AuditResult
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: audit.isClean ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(audit.isClean ? theme.accent : theme.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text(audit.headline).font(.subheadline.weight(.semibold))
                Text(audit.isClean
                    ? "Their revealed fleet matches the seal it was locked with, and every reported hit and miss checks out."
                    : "Their revealed fleet doesn't add up, so this result may not be fair.")
                    .font(.footnote)
                    .foregroundStyle(theme.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.m)
        .surface()
        .accessibilityElement(children: .combine)
    }
}
