import SwiftUI
import TetherCore

/// The morning journal as a small sheet from the bottom: tap what happened yesterday, then Done.
struct CheckUpSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var yes: Set<JournalQuestion> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Quick check up").font(.title3.bold())
                Spacer()
                Text("Yesterday").font(.subheadline).foregroundStyle(TetherBrand.sub)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(JournalQuestion.allCases) { question in
                    chip(question)
                }
            }
            Button {
                model.saveJournal(yes: yes)
                dismiss()
            } label: {
                Text(yes.isEmpty ? "None of these" : "Done").fontWeight(.semibold)
                    .foregroundStyle(TetherBrand.onEmber)
                    .frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent).tint(TetherBrand.ember)
        }
        .padding(20)
        .presentationDetents([.height(290), .medium])
        .presentationDragIndicator(.visible)
    }

    private func chip(_ question: JournalQuestion) -> some View {
        let on = yes.contains(question)
        return Button {
            if on { yes.remove(question) } else { yes.insert(question) }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: Self.icon(question)).font(.title3)
                Text(Self.short(question)).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundStyle(on ? TetherBrand.ember : TetherBrand.text)
            .background(on ? TetherBrand.ember.opacity(0.16) : Color.white.opacity(0.05), in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(on ? TetherBrand.ember : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(question.rawValue)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    static func icon(_ question: JournalQuestion) -> String {
        switch question {
        case .caffeineLate: "cup.and.saucer"
        case .alcohol: "wineglass"
        case .lateMeal: "fork.knife"
        case .screensInBed: "iphone"
        case .hardWorkout: "figure.run"
        case .stressfulDay: "cloud.bolt"
        case .nap: "powersleep"
        }
    }

    static func short(_ question: JournalQuestion) -> String {
        switch question {
        case .caffeineLate: "Coffee"
        case .alcohol: "Alcohol"
        case .lateMeal: "Late meal"
        case .screensInBed: "Screens"
        case .hardWorkout: "Workout"
        case .stressfulDay: "Stress"
        case .nap: "Nap"
        }
    }
}
