import SwiftUI
import TetherCore

/// This morning's journal: a few taps about yesterday. After a couple of weeks Trends shows which of
/// these move your Charge.
struct JournalCard: View {
    @Environment(AppModel.self) private var model
    @State private var yes: Set<JournalQuestion> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Yesterday, did you have…").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(JournalQuestion.allCases) { question in
                    let on = yes.contains(question)
                    Button {
                        if on { yes.remove(question) } else { yes.insert(question) }
                    } label: {
                        Text(question.rawValue).font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(on ? TetherBrand.ember.opacity(0.22) : Color.white.opacity(0.05), in: .rect(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? TetherBrand.ember : TetherBrand.cardStroke))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            HStack {
                Button(yes.isEmpty ? "None of these" : "Save") { model.saveJournal(yes: yes) }
                    .buttonStyle(.borderedProminent).tint(TetherBrand.ember)
                Spacer()
                Text("Stays on your phone").font(.caption).foregroundStyle(TetherBrand.sub)
            }
        }
        .card()
    }
}

/// On Trends: which journal answers go with a higher or lower Charge the next morning.
struct JournalInsightsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let insights = JournalInsights.compute(entries: model.journalEntries, nights: model.nights)
        VStack(alignment: .leading, spacing: 8) {
            Text("What moves your Charge").font(.headline)
            if insights.isEmpty {
                Text("Answer the morning journal on Today for a couple of weeks. Each answer needs \(JournalInsights.minimumEach) mornings with it and \(JournalInsights.minimumEach) without. \(JournalInsights.morningsLogged(model.journalEntries)) mornings so far.")
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
