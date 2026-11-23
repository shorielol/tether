import SwiftUI
import TetherCore

/// On Trends: which journal answers go with a higher or lower Charge the next morning.
struct JournalInsightsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let insights = JournalInsights.compute(entries: model.journalEntries, nights: model.nights)
        VStack(alignment: .leading, spacing: 8) {
            Text("What moves your Charge").font(.headline)
            if insights.isEmpty {
                Text("Fills in after about two weeks of check ups. \(JournalInsights.morningsLogged(model.journalEntries)) so far.")
                    .font(.subheadline).foregroundStyle(TetherBrand.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(insights) { insight in
                VStack(alignment: .leading, spacing: 2) {
                    Text(insight.sentence).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    Text(insight.clear ? "A clear difference over \(insight.mornings) mornings"
                                       : "Could still be chance (\(insight.mornings) mornings)")
                        .font(.caption)
                        .foregroundStyle(insight.clear ? (insight.difference < 0 ? TetherBrand.headsUp : TetherBrand.good) : TetherBrand.sub)
                }
                .padding(.vertical, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
