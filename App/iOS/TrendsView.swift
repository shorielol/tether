import Charts
import StrandAnalytics
import SwiftUI
import TetherCore

/// Your measures over the last 7, 30 or 90 days, with this week against last at the top.
struct TrendsView: View {
    @Environment(AppModel.self) private var model
    @State private var days = 30

    private var today: String { DayScorer.dayKey(dayStart: Int(Calendar.current.startOfDay(for: .now).timeIntervalSince1970)) }

    var body: some View {
        let series = Trends.compute(nights: model.nights, days: days, today: today).filter { $0.points.count >= 2 }
        TabScreen {
            ScreenHeader(eyebrow: "Last \(days) days", title: "Trends")
            Picker("Range", selection: $days) {
                ForEach(Trends.ranges, id: \.self) { Text("\($0) days").tag($0) }
            }
            .pickerStyle(.segmented)
            if model.nights.count >= 7 { WeekCard(digest: Trends.weekly(nights: model.nights, today: today)) }
            JournalInsightsCard()
            if series.isEmpty {
                NotYet(title: "Trends start after a few nights",
                       detail: "Charge, sleep, HRV, resting heart rate and the rest appear here once there are a couple of scored nights in this range.")
                    .card()
            }
            ForEach(series) { TrendCard(series: $0, days: days) }
        }
    }
}

/// This week against last: NOOP's weekly digest in a sentence or two.
private struct WeekCard: View {
    let digest: WeeklyDigest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This week").font(.headline)
            if digest.focalPoints.isEmpty {
                Text("Steady: nothing moved much against last week.").font(.subheadline).foregroundStyle(TetherBrand.sub)
            }
            ForEach(digest.focalPoints, id: \.self) { point in
                Text(point).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
            Text("\(digest.daysWithData) of 7 days recorded").font(.caption).foregroundStyle(TetherBrand.sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct TrendCard: View {
    let series: TrendSeries
    let days: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(series.name).font(.headline)
                Spacer()
                if let average = series.average {
                    Text("avg \(format(average)) \(series.unit)").font(.subheadline).monospacedDigit()
                        .foregroundStyle(TetherBrand.sub)
                }
            }
            Chart(series.points) { point in
                LineMark(x: .value("Day", date(point.day)), y: .value(series.name, point.value))
                    .foregroundStyle(TetherBrand.text)
                if days <= 30 {
                    PointMark(x: .value("Day", date(point.day)), y: .value(series.name, point.value))
                        .foregroundStyle(TetherBrand.text).symbolSize(16)
                }
                if let average = series.average {
                    RuleMark(y: .value("Average", average))
                        .foregroundStyle(TetherBrand.sub.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartYScale(domain: yDomain)
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel { if let number = value.as(Double.self) { Text(format(number)) } }
                }
            }
            .chartXAxis {
                AxisMarks(values: tickDates) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) }
            }
            .frame(height: 110)
            if let change = series.change {
                Text(changeText(change)).font(.caption)
                    .foregroundStyle(series.isBetter == true ? TetherBrand.good : series.isBetter == false ? TetherBrand.headsUp : TetherBrand.sub)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(series.name), average \(series.average.map(format) ?? "none") \(series.unit)")
    }

    /// At least a sensible span, so a flat line sits in the middle rather than filling the card.
    private var yDomain: ClosedRange<Double> {
        let values = series.points.map(\.value)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let span = max(high - low, abs(series.average ?? high) * 0.1, series.decimals > 0 ? 0.5 : 4)
        let middle = (low + high) / 2
        return (middle - span * 0.6)...(middle + span * 0.6)
    }

    /// Up to four dates from the points themselves, so no day is labelled twice.
    private var tickDates: [Date] {
        let points = series.points
        guard points.count > 4 else { return points.map { date($0.day) } }
        let step = Double(points.count - 1) / 3
        return (0...3).map { date(points[Int((Double($0) * step).rounded())].day) }
    }

    private func changeText(_ change: Double) -> String {
        let size = format(abs(change))
        if size == format(0) { return "Level across the \(days) days" }
        return "\(change > 0 ? "Up" : "Down") \(size) \(series.unit) from the first half to the second"
    }

    private func format(_ value: Double) -> String { String(format: "%.\(series.decimals)f", value) }

    private func date(_ day: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: day) ?? .now
    }
}
