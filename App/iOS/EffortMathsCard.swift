import SwiftUI
import TetherCore

/// "Show the maths" for Effort: the minutes in each heart-rate band, what they added, and a what-if
/// that adds time to a band and re-runs the same curve.
struct EffortMathsCard: View {
    let bandMinutes: [Double]
    let breakdown: ScoreBreakdown

    @State private var whatIfOpen = BreakdownCard.opensWhatIfForScreenshots

    var body: some View {
        BreakdownCard(title: "How Effort got to \(BreakdownCard.text(breakdown.total, breakdown.decimals))",
                      startTitle: "Resting", startDetail: "time below the light band counts nothing",
                      totalTitle: "Effort", unit: "", breakdown: breakdown,
                      footnote: "Your range runs from your resting heart rate to your max. Minutes add up quickly at first and more slowly later, so the same half hour adds less on a day that's already busy.",
                      whatIf: { whatIfOpen = true }, hidesEmptySteps: true)
            .sheet(isPresented: $whatIfOpen) {
                EffortWhatIfSheet(bandMinutes: bandMinutes)
                    .presentationDetents([.medium, .large])
            }
    }
}

/// Add time in one band and watch Effort change. Uses the same curve as the real number.
struct EffortWhatIfSheet: View {
    let bandMinutes: [Double]

    @State private var band = 3
    @State private var extraMinutes = 30.0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    result
                    Picker("Band", selection: $band) {
                        ForEach(1...ScoreBreakdown.effortBandNames.count, id: \.self) { band in
                            Text(ScoreBreakdown.effortBandNames[band - 1]).tag(band)
                        }
                    }
                    .pickerStyle(.menu).tint(TetherBrand.text)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Extra time").font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(Int(extraMinutes)) min").font(.subheadline).monospacedDigit()
                        }
                        Slider(value: $extraMinutes, in: 0...180, step: 5).tint(TetherBrand.ember)
                            .accessibilityLabel("Extra time")
                            .accessibilityValue("\(Int(extraMinutes)) minutes")
                    }
                    Text("Adds that time to today's heart rate in the band you pick, then runs the same Effort curve.")
                        .font(.footnote).foregroundStyle(TetherBrand.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
            .navigationTitle("What if")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var result: some View {
        var more = bandMinutes
        if more.indices.contains(band) { more[band] += extraMinutes }
        let now = ScoreBreakdown.effortScore(bandMinutes: more)
        let was = ScoreBreakdown.effortScore(bandMinutes: bandMinutes)
        return VStack(alignment: .leading, spacing: 2) {
            Text("Effort").font(.subheadline).foregroundStyle(TetherBrand.sub)
            Text(String(format: "%.1f", now))
                .font(.system(.largeTitle, design: .rounded).weight(.bold)).monospacedDigit()
                .foregroundStyle(TetherBrand.text)
                .contentTransition(.numericText())
            Text("So far today \(String(format: "%.1f", was))").font(.caption).foregroundStyle(TetherBrand.sub)
        }
        .accessibilityElement(children: .combine)
    }
}
