import SwiftUI
import TetherCore

/// "Show the maths" for Stress: pick an hour and see how its heart rate and HRV, against today's calm
/// level, put it where it is on the 0–3 scale.
struct StressMathsCard: View {
    let detail: StressDetail

    @State private var chosen: Int?

    private var scored: [StressDetail.Hour] { detail.hours.filter { $0.breakdown != nil } }

    private var hour: StressDetail.Hour? {
        let pick = chosen ?? detail.peak?.hour ?? scored.last?.hour
        return scored.first { $0.hour == pick } ?? scored.last
    }

    var body: some View {
        if let hour, let breakdown = hour.breakdown {
            BreakdownCard(title: "How \(label(hour.hour)) got to \(BreakdownCard.text(breakdown.total, 1))",
                          startTitle: "An hour at your calm level", startDetail: calmText,
                          totalTitle: "Stress", unit: " of 3", breakdown: breakdown,
                          footnote: "Today is its own yardstick: your calm level is the calmer end of today's waking hours, not earlier days. Above 1.5 means heart rate higher or HRV lower than that.",
                          accessory: AnyView(picker), upIsGood: false)
        }
    }

    private var picker: some View {
        Picker("Hour", selection: Binding(get: { hour?.hour ?? 0 }, set: { chosen = $0 })) {
            ForEach(scored) { Text(label($0.hour)).tag($0.hour) }
        }
        .pickerStyle(.menu).tint(TetherBrand.text)
        .accessibilityLabel("Hour to explain")
    }

    private var calmText: String {
        guard let calm = detail.calm else { return "the calmer end of your day" }
        let hrv = calm.hrv.map { ", HRV \($0) ms" } ?? ""
        return "today that's \(calm.heartRate) bpm\(hrv)"
    }

    private func label(_ hour: Int) -> String {
        var parts = DateComponents()
        parts.hour = hour
        let date = Calendar.current.date(from: parts) ?? .now
        return date.formatted(.dateTime.hour())
    }
}
