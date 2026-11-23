import SwiftUI
import TetherCore

/// "Show the maths" for Charge: a running total from a night at your normal to last night's score, and
/// a what-if that re-runs the same scoring with values you drag.
struct ChargeMathsCard: View {
    let inputs: ChargeInputs
    let breakdown: ScoreBreakdown

    /// Screenshot runs can pass `-tether.debugWhatIf YES` to open the what-if straight away.
    @State private var whatIfOpen = BreakdownCard.opensWhatIfForScreenshots

    var body: some View {
        BreakdownCard(title: "How Charge got to \(BreakdownCard.text(breakdown.total, breakdown.decimals))%",
                      startTitle: "A night at your normal", startDetail: "every measure level with your average",
                      totalTitle: "Charge", unit: "%", breakdown: breakdown,
                      footnote: "Each measure is added in this order. Charge follows a curve, so a different order would split the points a little differently, but the total stays the same.") {
            whatIfOpen = true
        }
        .sheet(isPresented: $whatIfOpen) {
            ChargeWhatIfSheet(lastNight: inputs)
                .presentationDetents([.medium, .large])
        }
    }
}

/// A score as a running total: where it starts, what each step added or took away, and the total.
struct BreakdownCard: View {
    let title: String
    let startTitle: String
    let startDetail: String
    let totalTitle: String
    let unit: String
    let breakdown: ScoreBreakdown
    let footnote: String
    /// Opens the what-if, or nil when this score has none.
    var whatIf: (() -> Void)? = nil
    /// Steps worth showing; a step that moved nothing and carried nothing is left out.
    var hidesEmptySteps = false
    /// How values read, when not a plain number (Sleep shows "6h 13m").
    var format: ((Double) -> String)? = nil
    /// A control under the title, such as Stress's hour picker.
    var accessory: AnyView? = nil
    /// False where a higher number is worse (Stress), so a rise shows as a heads-up rather than good.
    var upIsGood = true

    static var opensWhatIfForScreenshots: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "tether.debugWhatIf")
        #else
        false
        #endif
    }

    static func text(_ value: Double, _ decimals: Int) -> String {
        String(format: "%.\(decimals)f", value)
    }

    /// Folded to one row until opened: the maths is there for whoever wants it, not in the way.
    @State private var open = BreakdownCard.opensWhatIfForScreenshots

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { open.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "function").foregroundStyle(TetherBrand.sub)
                    Text(title).font(.headline)
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(TetherBrand.sub)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(open ? "Hides the working" : "Shows the working")
            if open { working }
        }
        .card()
    }

    @ViewBuilder private var working: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let accessory { accessory.padding(.vertical, 6) }
            row(title: startTitle, detail: startDetail) { Text(show(breakdown.start)) }
            ForEach(shownSteps) { step in
                Divider().overlay(TetherBrand.cardStroke)
                row(title: step.name, detail: detail(step)) {
                    Text(signed(step.points))
                        .foregroundStyle(tint(step.points))
                }
            }
            Divider().overlay(TetherBrand.text.opacity(0.5))
            row(title: totalTitle, detail: nil) { Text("\(show(breakdown.total))\(unit)") }
            Text(footnote)
                .font(.caption).foregroundStyle(TetherBrand.sub)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            if let whatIf {
                Button("What if…", action: whatIf)
                    .buttonStyle(.bordered).tint(TetherBrand.text)
                    .padding(.top, 12)
            }
        }
        .padding(.top, 8)
    }

    private var shownSteps: [ScoreBreakdown.Step] {
        hidesEmptySteps ? breakdown.steps.filter { $0.points != 0 || $0.weightPercent > 0 } : breakdown.steps
    }

    private func row(title: String, detail: String?, @ViewBuilder value: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(TetherBrand.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            value().font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func tint(_ points: Double) -> Color {
        guard points != 0 else { return TetherBrand.sub }
        return (points > 0) == upIsGood ? TetherBrand.good : TetherBrand.headsUp
    }

    private func show(_ value: Double) -> String {
        format?(value) ?? Self.text(value, breakdown.decimals)
    }

    private func detail(_ step: ScoreBreakdown.Step) -> String {
        let base = "\(step.valueText), \(step.compareText)"
        return step.weightPercent > 0 ? "\(base) · counts \(step.weightPercent)%" : base
    }

    private func signed(_ points: Double) -> String {
        let magnitude = show(abs(points))
        return points > 0 ? "+\(magnitude)" : points < 0 ? "−\(magnitude)" : "0"
    }
}

/// Drag last night's measures and watch Charge change. Uses the same scoring as the real number.
struct ChargeWhatIfSheet: View {
    let lastNight: ChargeInputs

    @State private var whatIf: ChargeInputs
    @Environment(\.dismiss) private var dismiss

    init(lastNight: ChargeInputs) {
        self.lastNight = lastNight
        _whatIf = State(initialValue: lastNight)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    result
                    slider("HRV", unit: "ms", value: $whatIf.hrv, was: lastNight.hrv,
                           range: range(around: lastNight.hrvNormal.mean, spread: 0.6, including: lastNight.hrv))
                    slider("Resting HR", unit: "bpm", value: $whatIf.restingHR, was: lastNight.restingHR,
                           range: range(around: lastNight.restingHRNormal?.mean ?? lastNight.restingHR, by: 12,
                                        including: lastNight.restingHR))
                    if let rest = lastNight.rest {
                        slider("Sleep quality", unit: "of 100", value: restBinding, was: rest,
                               range: min(40, rest.rounded(.down))...100)
                    }
                    Text("Runs the same scoring Tether used for last night. Breathing and skin temperature stay as they were.")
                        .font(.footnote).foregroundStyle(TetherBrand.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
            .navigationTitle("What if")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") { whatIf = lastNight }.disabled(whatIf == lastNight)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var result: some View {
        let now = whatIf.charge().map { Int($0.rounded()) }
        let was = lastNight.charge().map { Int($0.rounded()) }
        return VStack(alignment: .leading, spacing: 2) {
            Text("Charge").font(.subheadline).foregroundStyle(TetherBrand.sub)
            Text(now.map { "\($0)%" } ?? "–")
                .font(.system(.largeTitle, design: .rounded).weight(.bold)).monospacedDigit()
                .foregroundStyle(now.map { TetherBrand.charge(ChargeZone(charge: Double($0))) } ?? TetherBrand.sub)
                .contentTransition(.numericText())
            if let was { Text("Last night \(was)%").font(.caption).foregroundStyle(TetherBrand.sub) }
        }
        .accessibilityElement(children: .combine)
    }

    private var restBinding: Binding<Double> {
        Binding(get: { whatIf.rest ?? ChargeInputs.levelRest }, set: { whatIf.rest = $0 })
    }

    private func slider(_ title: String, unit: String, value: Binding<Double>, was: Double,
                        range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(value.wrappedValue.rounded())) \(unit)").font(.subheadline).monospacedDigit()
            }
            Slider(value: value, in: range, step: 1).tint(TetherBrand.ember)
                .accessibilityLabel(title)
                .accessibilityValue("\(Int(value.wrappedValue.rounded())) \(unit)")
            Text("Last night \(Int(was.rounded())) \(unit)").font(.caption).foregroundStyle(TetherBrand.sub)
        }
    }

    private func range(around mean: Double, spread fraction: Double, including value: Double) -> ClosedRange<Double> {
        range(around: mean, by: mean * fraction, including: value)
    }

    private func range(around mean: Double, by half: Double, including value: Double) -> ClosedRange<Double> {
        let low = min(max(1, (mean - half).rounded(.down)), value.rounded(.down))
        let high = max((mean + half).rounded(.up), value.rounded(.up))
        return low...high
    }
}
