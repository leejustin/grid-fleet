import Charts
import GridFleetCore
import SwiftData
import SwiftUI

/// Your record: win rate, accuracy, medals and recent battles.
struct LogbookView: View {
    @Query(sort: \GameRecord.playedAt, order: .reverse) private var records: [GameRecord]
    @Query private var awards: [MedalAward]
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScreenScroll {
            if records.isEmpty {
                empty
            } else {
                summary
                medalCase
                if records.count >= 2 { accuracyChart }
                opponents
                recent
            }
        }
        .oceanNavigation("Logbook")
    }

    private var wins: Int { records.filter(\.won).count }
    private var winRate: Double { records.isEmpty ? 0 : Double(wins) / Double(records.count) }

    private var currentStreak: Int {
        var streak = 0
        for record in records {
            if record.won { streak += 1 } else { break }
        }
        return streak
    }

    private var empty: some View {
        VStack(spacing: Space.s) {
            Image(systemName: "book.closed").font(.title).foregroundStyle(theme.accent)
            Text("No battles yet").font(.headline)
            Text("Finished games show up here and sync through iCloud.")
                .font(.subheadline)
                .foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.xxl)
        .surface()
    }

    private var summary: some View {
        let accuracies = records.filter { $0.shotsFired > 0 }.map(\.accuracy)
        let average = accuracies.isEmpty ? 0 : accuracies.reduce(0, +) / Double(accuracies.count)
        let fastest = records.filter { $0.won && $0.turns > 0 }.map(\.turns).min()
        let large = typeSize.isAccessibilitySize
        return VStack(spacing: Space.m) {
            (large ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.m)) : AnyLayout(HStackLayout(spacing: Space.l))) {
                ZStack {
                    Circle().stroke(theme.ink.opacity(0.1), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: winRate)
                        .stroke(theme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(Int((winRate * 100).rounded()))%").font(.title3.weight(.semibold).monospacedDigit())
                        Text("won").font(.caption).foregroundStyle(theme.inkSecondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(Space.s)
                }
                .frame(width: large ? 120 : 88, height: large ? 120 : 88)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("\(records.count) battles").font(.headline)
                    Text("\(wins) won, \(records.count - wins) lost").font(.subheadline).foregroundStyle(theme.inkSecondary)
                    if currentStreak > 1 {
                        Text("\(currentStreak) wins in a row").font(.subheadline).foregroundStyle(theme.accent)
                    }
                }
                Spacer(minLength: 0)
            }
            Rectangle().fill(theme.hairline).frame(height: 1)
            (large ? AnyLayout(VStackLayout(spacing: Space.s)) : AnyLayout(HStackLayout(spacing: 0))) {
                figure("\(Int((average * 100).rounded()))%", "Average accuracy")
                figure("\(Int(((accuracies.max() ?? 0) * 100).rounded()))%", "Best accuracy")
                figure(fastest.map { "\($0)" } ?? "–", "Fastest win, turns")
            }
        }
        .padding(Space.m)
        .surface()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func figure(_ value: String, _ label: String) -> some View {
        if typeSize.isAccessibilitySize {
            // Side by side, the labels would break mid-word; as rows they read like a list.
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.subheadline).foregroundStyle(theme.inkSecondary)
                Spacer(minLength: Space.s)
                Text(value).font(.headline.monospacedDigit())
            }
        } else {
            VStack(spacing: 2) {
                Text(value).font(.headline.monospacedDigit())
                Text(label).font(.caption).foregroundStyle(theme.inkSecondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var medalCase: some View {
        let counts = Dictionary(grouping: awards.compactMap(\.medal), by: { $0 }).mapValues(\.count)
        return ContentSection("Medals · \(counts.count) of \(Medal.allCases.count)") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 150 : 92), spacing: Space.s)], spacing: Space.l) {
                ForEach(Medal.allCases) { medal in
                    let count = counts[medal] ?? 0
                    VStack(spacing: Space.xs) {
                        MedalBadge(medal: medal, earned: count > 0, size: 44)
                        VStack(spacing: 1) {
                            Text(medal.title).font(.caption.weight(.semibold)).multilineTextAlignment(.center).lineLimit(2)
                            Text(count > 1 ? "×\(count)" : (count == 1 ? "Earned" : medal.criterion))
                                .font(.caption2)
                                .foregroundStyle(theme.inkSecondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .padding(Space.m)
            .surface()
        }
    }

    private var accuracyChart: some View {
        let recent = Array(records.prefix(20).reversed().enumerated())
        return ContentSection("Accuracy, last \(recent.count) battles") {
            Chart {
                ForEach(recent, id: \.offset) { index, record in
                    LineMark(x: .value("Battle", index + 1), y: .value("Accuracy", record.accuracy * 100))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(theme.inkSecondary.opacity(0.5))
                    PointMark(x: .value("Battle", index + 1), y: .value("Accuracy", record.accuracy * 100))
                        .foregroundStyle(record.won ? theme.accent : theme.hit)
                        .symbolSize(28)
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { value in
                    AxisGridLine().foregroundStyle(theme.hairline)
                    AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%").font(.caption2).foregroundStyle(theme.inkSecondary) }
                }
            }
            .chartXAxis(.hidden)
            .frame(height: 140)
            .padding(Space.m)
            .surface()
        }
    }

    private var opponents: some View {
        let groups: [(String, [GameRecord])] = AIDifficulty.allCases.map { level in
            (Rival.for(level).fullName, records.filter { $0.mode == .computer && $0.difficulty == level })
        } + [GameMode.online, .live, .room, .passAndPlay].map { mode in
            (mode.displayName, records.filter { $0.mode == mode })
        }
        let played = groups.filter { !$0.1.isEmpty }
        return ContentSection("By opponent") {
            VStack(spacing: 0) {
                ForEach(Array(played.enumerated()), id: \.element.0) { index, group in
                    if index > 0 { RowDivider(inset: Space.m) }
                    let won = group.1.filter(\.won).count
                    HStack {
                        Text(group.0).font(.body)
                        Spacer()
                        Text("\(won)–\(group.1.count - won)").font(.body.monospacedDigit()).foregroundStyle(theme.inkSecondary)
                    }
                    .padding(.horizontal, Space.m)
                    .frame(minHeight: 48)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(group.0): \(won) won, \(group.1.count - won) lost")
                }
            }
            .surface()
        }
    }

    private var recent: some View {
        ContentSection("Recent battles") {
            VStack(spacing: 0) {
                ForEach(Array(records.prefix(25).enumerated()), id: \.element.id) { index, record in
                    if index > 0 { RowDivider(inset: Space.m) }
                    HStack(spacing: Space.s) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: Space.xs) {
                                Text(record.won ? "Won" : "Lost")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(record.won ? theme.accent : theme.hit)
                                Text("vs \(record.opponentName)").font(.subheadline).lineLimit(1)
                                if record.verified == true {
                                    Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(theme.accent)
                                        .accessibilityLabel("Verified")
                                }
                            }
                            Text("\(record.mode.displayName) · \(record.preset.displayName) · \(record.turns) turns")
                                .font(.footnote)
                                .foregroundStyle(theme.inkSecondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int((record.accuracy * 100).rounded()))%").font(.subheadline.monospacedDigit())
                            Text(record.playedAt, format: .dateTime.month(.abbreviated).day()).font(.footnote).foregroundStyle(theme.inkSecondary)
                        }
                    }
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.s)
                    .accessibilityElement(children: .combine)
                }
            }
            .surface()
        }
    }
}
