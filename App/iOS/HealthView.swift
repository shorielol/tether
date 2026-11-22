import Charts
import SwiftUI
import TetherCore

/// Last night's vitals against your normal, each with its week. A vital the strap hasn't sent says so.
struct HealthView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let vitals = HealthVital.compute(latest: model.lastNight, history: model.nights)
        let monitor = model.healthMonitor
        TabScreen {
            ScreenHeader(eyebrow: "Last night vs your normal", title: "Health")
            if let monitor { EarlyWarningCard(warning: monitor.warning) }
            if vitals.isEmpty {
                NotYet(title: "No nights yet", detail: "Wear the strap to bed. Your vitals show here in the morning.")
                    .card()
            } else {
                Text(HealthVital.summary(vitals)).font(.subheadline).foregroundStyle(TetherBrand.sub)
                ForEach(vitals) { vital in
                    VitalCard(vital: vital, flag: monitor?.flags.first { $0.name == vital.name })
                }
            }
            PendingVital(name: "Blood oxygen", status: "not sent yet",
                         detail: "Your strap hasn't sent blood oxygen yet. If it never does, this will say it isn't available on your strap.")
        }
    }
}

/// The early warning: quiet when all's well, a gentle note when several signals drift together.
private struct EarlyWarningCard: View {
    let warning: HealthMonitor.Warning

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(TetherBrand.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch warning {
        case .learning: "Early warning is learning"
        case .clear: "Nothing unusual last night"
        case .mild: "A little off your normal"
        case .raised: "A few signals are off your normal"
        case .explained: "Off your normal, with a likely reason"
        }
    }

    private var detail: String {
        switch warning {
        case .learning(let nights):
            "It watches for several signals drifting together, the way they can a day or two before you feel ill. It starts once it knows your normal: \(nights) more \(nights == 1 ? "night" : "nights")."
        case .clear:
            "Resting heart rate, HRV, breathing and skin temperature are where they usually are for you."
        case .mild(let signals):
            "\(signals.joined(separator: ", ")). Probably nothing; worth seeing whether it's still there tomorrow."
        case .raised(let signals):
            "\(signals.joined(separator: ", ")). Take it easy and see how you feel. On-device estimate, not a diagnosis."
        case .explained(let signals):
            "\(signals.joined(separator: ", ")), but something else you did likely explains it."
        }
    }

    private var icon: String {
        switch warning {
        case .raised, .mild: "exclamationmark.circle.fill"
        case .clear: "checkmark.circle.fill"
        default: "circle.dotted"
        }
    }

    private var tint: Color {
        switch warning {
        case .raised, .mild: TetherBrand.headsUp
        case .clear: TetherBrand.good
        default: TetherBrand.sub
        }
    }
}

private struct VitalCard: View {
    let vital: HealthVital
    /// The health monitor's verdict: only an out-of-range flag turns the card to a heads-up.
    let flag: HealthMonitor.Flag?

    private var flagged: Bool { flag?.outOfRange == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(vital.name).font(.headline)
                Spacer()
                Text(verdict).font(.footnote.weight(flagged ? .semibold : .regular))
                    .foregroundStyle(flagged ? TetherBrand.headsUp : TetherBrand.sub)
            }
            if let value = vital.value {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(format(value)).font(.system(.title, weight: .bold)).monospacedDigit()
                    Text(vital.unit).font(.subheadline).foregroundStyle(TetherBrand.sub)
                }
                RangeBar(placement: placement(value), tint: flagged ? TetherBrand.headsUp : TetherBrand.text)
            }
            WeekChart(vital: vital).frame(height: 64)
            if let band = vital.band {
                let low = format(band.low), high = format(band.high)
                Text("Your normal: \(low == high ? low : "\(low)–\(high)") \(vital.unit)")
                    .font(.caption).foregroundStyle(TetherBrand.sub)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private var verdict: String {
        guard let value = vital.value else {
            let everMeasured = vital.recent.contains { $0.value != nil }
            return everMeasured ? "not measured last night" : "starts after a night's sleep"
        }
        if flagged {
            return flag?.personal == true ? "outside your usual range" : "outside the typical adult range"
        }
        guard let band = vital.band else { return "learning your normal" }
        if band.contains(value) { return "in your normal" }
        return value < band.low ? "below your normal" : "above your normal"
    }

    private func placement(_ value: Double) -> RangePlacement {
        let domain = vital.band.map { RangePlacement.domain(around: $0, value: value) } ?? (value * 0.5)...(value * 1.5)
        return RangePlacement(value: value, band: vital.band, domain: domain)
    }

    private func format(_ value: Double) -> String { String(format: "%.\(vital.decimals)f", value) }
}

/// The last week of nights as a small line, with your normal as a band behind it.
private struct WeekChart: View {
    let vital: HealthVital

    private static let dayKey: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private var points: [(day: String, value: Double)] {
        vital.recent.compactMap { night in night.value.map { (night.day, $0) } }
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.value) + [vital.band?.low, vital.band?.high].compactMap { $0 }
        let low = values.min() ?? 0, high = values.max() ?? 1
        let pad = max((high - low) * 0.25, abs(high) * 0.05, 1)
        return (low - pad)...(high + pad)
    }

    var body: some View {
        Chart {
            if let band = vital.band {
                RectangleMark(yStart: .value("Normal low", band.low), yEnd: .value("Normal high", band.high))
                    .foregroundStyle(Color.white.opacity(0.07))
            }
            ForEach(points, id: \.day) { point in
                LineMark(x: .value("Night", weekday(point.day)), y: .value(vital.name, point.value))
                    .foregroundStyle(Color(white: 0.8))
                PointMark(x: .value("Night", weekday(point.day)), y: .value(vital.name, point.value))
                    .foregroundStyle(Color(white: 0.8))
                    .symbolSize(24)
            }
        }
        .chartXScale(domain: vital.recent.map { weekday($0.day) })
        .chartYScale(domain: yDomain)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel().foregroundStyle(TetherBrand.sub) }
        }
        .accessibilityLabel(summary)
    }

    /// "Sun" for a night key, falling back to the key itself.
    private func weekday(_ day: String) -> String {
        Self.dayKey.date(from: day).map { $0.formatted(.dateTime.weekday(.abbreviated)) } ?? day
    }

    private var summary: String {
        guard let low = points.map(\.value).min(), let high = points.map(\.value).max() else {
            return "\(vital.name): no nights measured this week"
        }
        return "\(vital.name) over the last \(points.count) nights, from \(Int(low.rounded())) to \(Int(high.rounded()))"
    }
}

private struct PendingVital: View {
    let name: String
    let status: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(.headline)
                Spacer()
                Text(status).font(.footnote).foregroundStyle(TetherBrand.sub)
            }
            Text(detail).font(.subheadline).foregroundStyle(TetherBrand.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}
