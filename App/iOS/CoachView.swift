import FoundationModels
import SwiftUI
import TetherCore

/// Ask about your numbers. Answers come from Apple's on-device model, given only a short brief of your own
/// numbers; nothing leaves the phone. Without Apple Intelligence the same numbers give written answers.
@MainActor
@Observable
final class CoachSession {
    struct Exchange: Identifiable {
        let id = UUID()
        let question: String
        var answer: String?
        var written = false
    }

    private(set) var exchanges: [Exchange] = []
    private(set) var busy = false

    /// Only the on-device model. Tether never uses a cloud model, even Apple's.
    private var model: SystemLanguageModel { .default }

    var usesModel: Bool { model.isAvailable }

    var modelNote: String {
        switch model.availability {
        case .available:
            "Answered by Apple's model on this iPhone, from your numbers. Nothing leaves your phone."
        case .unavailable(.appleIntelligenceNotEnabled):
            "Apple Intelligence is off, so these are written answers from your numbers. Turn it on in Settings for fuller ones."
        case .unavailable(.modelNotReady):
            "Apple's model is still downloading, so for now these are written answers from your numbers."
        case .unavailable:
            "This iPhone can't run Apple's model, so these are written answers from your numbers."
        }
    }

    func ask(_ question: String, input: Coach.Input) async {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !busy else { return }
        busy = true
        defer { busy = false }
        exchanges.append(Exchange(question: question))
        let index = exchanges.count - 1
        guard usesModel, Coach.hasData(input) else {
            exchanges[index].answer = Coach.writtenAnswer(to: question, input)
            exchanges[index].written = true
            return
        }
        let session = LanguageModelSession(model: model,
                                           instructions: Coach.instructions + "\n\nBrief:\n" + Coach.brief(input))
        do {
            exchanges[index].answer = try await session.respond(to: question).content
        } catch {
            exchanges[index].answer = Coach.writtenAnswer(to: question, input)
            exchanges[index].written = true
        }
    }
}

struct CoachView: View {
    @Environment(AppModel.self) private var model
    @State private var session = CoachSession()
    @State private var draft = ""
    @FocusState private var typing: Bool

    var body: some View {
        TabScreen {
            ScreenHeader(eyebrow: "On this iPhone", title: "Ask")
            Text(session.modelNote).font(.footnote).foregroundStyle(TetherBrand.sub)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(session.exchanges) { exchange in
                VStack(alignment: .leading, spacing: 8) {
                    Text(exchange.question).font(.headline)
                    if let answer = exchange.answer {
                        Text(answer).font(.body).fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    } else {
                        ProgressView().tint(TetherBrand.sub)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Coach.suggestions, id: \.self) { suggestion in
                    Button(suggestion) { send(suggestion) }
                        .buttonStyle(.bordered).tint(TetherBrand.text)
                        .disabled(session.busy)
                }
                HStack {
                    TextField("Ask about your numbers", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .focused($typing)
                        .submitLabel(.send)
                        .onSubmit { send(draft) }
                    Button { send(draft) } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                        .tint(TetherBrand.ember)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || session.busy)
                        .accessibilityLabel("Ask")
                }
            }
            .card()
            Text("Not medical advice. If something feels wrong, talk to a doctor.")
                .font(.caption).foregroundStyle(TetherBrand.sub)
        }
        #if DEBUG
        // `-tether.debugAsk "question"` asks once on open, to check answers without tapping.
        .task {
            if session.exchanges.isEmpty, let question = UserDefaults.standard.string(forKey: "tether.debugAsk") {
                send(question)
            }
        }
        #endif
    }

    private func send(_ question: String) {
        draft = ""
        typing = false
        let input = model.coachInput
        Task { await session.ask(question, input: input) }
    }
}

struct CoachRow: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ask about your numbers").font(.headline)
                Text("Why Charge is where it is, how your week went. Answered on this iPhone.")
                    .font(.subheadline).foregroundStyle(TetherBrand.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(TetherBrand.sub)
        }
        .card()
    }
}
