import Charts
import SwiftUI
import TetherCore

/// Last night's vitals against your normal, each with its week. A vital the strap hasn't sent says so.
struct HealthView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let vitals = HealthVital.compute(latest: model.lastNight, history: model.nights)
        TabScreen {
            ScreenHeader(eyebrow: "Last night vs your normal", title: "Health")
            if vitals.isEmpty {
                NotYet(title: "No nights yet", detail: "Wear the strap to bed. Your vitals show here in the morning.")
                    .card()
            } else {
                Text(HealthVital.summary(vitals)).font(.subheadline).foregroundStyle(TetherBrand.sub)
                ForEach(vitals) { VitalCard(vital: $0) }
            }
            PendingVital(name: "Blood oxygen", status: "not sent yet",
                         detail: "Your strap hasn't sent blood oxygen yet. If it never does, this will say it isn't available on your strap.")
        }
    }
}

private struct VitalCard: View {
    let vital: HealthVital

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(vital.name).font(.headline)
                Spacer()
                Text(verdict).font(.footnote.weight(vital.isWorse ? .semibold : .regular))
                    .foregroundStyle(vital.isWorse ? TetherBrand.headsUp : TetherBrand.sub)
            }
            if let value = vital.value {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(format(value)).font(.system(.title, weight: .bold)).monospacedDigit()
                    Text(vital.unit).font(.subheadline).foregroundStyle(TetherBrand.sub)
                }
                RangeBar(placement: placement(value), tint: vital.isWorse ? TetherBrand.headsUp : TetherBrand.text)
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
        guard let value = vital.value else { return "not measured last night" }
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
