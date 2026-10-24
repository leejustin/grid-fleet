import SwiftUI

/// Asks once, after the first finished game, whether to share anonymous usage.
struct AnalyticsPrompt: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Help improve Grid Fleet").font(.headline)
            Text("Share anonymous gameplay stats, like how long deploying takes. No names, nothing tied to you. You can change this in Settings.")
                .font(.subheadline)
                .foregroundStyle(theme.inkSecondary)
            HStack(spacing: Space.xs) {
                Button("Share stats") {
                    withAnimation { Analytics.shared.setOptedIn(true) }
                }
                .buttonStyle(.fleet(.primary, compact: true))
                Button("Not now") {
                    withAnimation { Analytics.shared.setOptedIn(false) }
                }
                .buttonStyle(.fleet(.secondary, compact: true))
            }
            .padding(.top, Space.xxs)
        }
        .foregroundStyle(theme.ink)
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface()
    }
}
