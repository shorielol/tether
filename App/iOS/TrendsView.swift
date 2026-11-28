import Charts
import StrandAnalytics
import SwiftUI
import TetherCore

/// Your measures over the last 7, 30 or 90 days, with this week against last at the top. Charge and sleep
/// are bars (Charge coloured by zone, sleep against eight hours); the rest are soft lines.
struct TrendsView: View {
    @Environment(AppModel.self) private var model
    @State private var days = 30

    private var today: String { DayScorer.dayKey(dayStart: Int(Calendar.current.startOfDay(for: .now).timeIntervalSince1970)) }

    var body: some View {
        let series = Trends.compute(nights: model.nights, days: days, today: today).filter { $0.points.count >= 2 }
        TabScreen {
            ScreenHeader(eyebrow: "Last \(days) days", title: "Trends")
            RangePicker(days: $days)
            if model.nights.count >= 7 { WeekCard(digest: Trends.weekly(nights: model.nights, today: today)).staggered(0) }
            JournalInsightsCard()
            if series.isEmpty {
                NotYet(title: "Trends start after a few nights",
                       detail: "Charge, sleep, HRV, resting heart rate and the rest appear here once there are a couple of scored nights in this range.")
                    .card()
            }
            ForEach(Array(series.enumerated()), id: \.element.id) { index, item in
                TrendCard(series: item, days: days)
                    .id("\(item.name)-\(days)")
                    .staggered(1 + index)
            }
        }
    }
}

/// 7D, 30D, 90D on glass, with a pill that slides to the chosen range.
private struct RangePicker: View {
    @Binding var days: Int
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Trends.ranges, id: \.self) { range in
                Button {
                    withAnimation(Motion.quick) { days = range }
                } label: {
                    Text("\(range)D")
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(days == range ? TetherBrand.text : TetherBrand.sub)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if days == range {
                                Capsule().fill(Color.white.opacity(0.14))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18)))
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(range) days")
                .accessibilityAddTraits(days == range ? .isSelected : [])
            }
        }
        .padding(4)
        .glass(cornerRadius: 22)
    }
}

/// This week against last: NOOP's weekly digest in a sentence or two.
private struct WeekCard: View {
    let digest: WeeklyDigest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Your week")
            if digest.focalPoints.isEmpty {
                Text("Steady: nothing moved much against last week.").font(.body.weight(.medium))
            }
            ForEach(digest.focalPoints, id: \.self) { point in
                Text(point).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            }
            Text("\(digest.daysWithData) of 7 days recorded").font(.caption).foregroundStyle(TetherBrand.sub)
        }
        .card()
    }
}

private struct TrendCard: View {
    let series: TrendSeries
    let days: Int
    @State private var shown = false

    private enum Style { case chargeBars, sleepBars, line }

    private var style: Style {
        switch series.name {
        case "Charge": .chargeBars
        case "Asleep": .sleepBars
        default: .line
        }
    }

    private var tint: Color {
        switch series.name {
        case "Charge": TetherBrand.good
        case "Asleep", "HRV": TetherBrand.dusk
        case "Resting HR", "Effort": TetherBrand.ember
        default: TetherBrand.bone
        }
    }

    /// Eight hours, the line sleep bars are read against.
    private static let sleepGoal = 8.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: series.name)
                Spacer()
                if let change = series.change {
                    Text(changeText(change)).font(.caption.weight(.semibold))
                        .foregroundStyle(series.isBetter == true ? TetherBrand.good
                                         : series.isBetter == false ? TetherBrand.headsUp : TetherBrand.sub)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(series.average.map(display) ?? "–")
                    .font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit()
                Text("average").font(.footnote).foregroundStyle(TetherBrand.sub)
            }
            chart
                .frame(height: 120)
                // Room above the plot so the top axis label and the "8 h" note sit inside the mask.
                .padding(.top, 12)
                .mask(alignment: style == .line ? .leading : .bottom) {
                    GeometryReader { geo in
                        Rectangle()
                            .frame(width: style == .line && !shown ? 0 : geo.size.width,
                                   height: style != .line && !shown ? 0 : geo.size.height)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
        }
        .card()
        .entrance($shown, Motion.draw, delay: 0.2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(series.name), average \(series.average.map(display) ?? "none")")
    }

    @ViewBuilder private var chart: some View {
        switch style {
        case .chargeBars: chargeChart
        case .sleepBars: sleepChart
        case .line: lineChart
        }
    }

    /// Each day's Charge as a bar in its zone's colour; the best day at full strength, the rest softer.
    private var chargeChart: some View {
        let best = series.points.max { $0.value < $1.value }?.day
        return Chart(series.points) { point in
            let colour = TetherBrand.charge(ChargeZone(charge: point.value))
            BarMark(x: .value("Day", date(point.day), unit: .day), y: .value("Charge", point.value))
                .foregroundStyle(LinearGradient(colors: [colour, colour.opacity(0.3)], startPoint: .top, endPoint: .bottom))
                .opacity(point.day == best ? 1 : 0.7)
                .clipShape(.rect(cornerRadius: days <= 30 ? 4 : 1))
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel().foregroundStyle(TetherBrand.sub)
            }
        }
        .chartXAxis { dateAxis }
    }

    /// Hours asleep as bars against a dashed eight-hour line.
    private var sleepChart: some View {
        let top = max(series.points.map(\.value).max() ?? Self.sleepGoal, Self.sleepGoal) + 1
        return Chart {
            ForEach(series.points) { point in
                BarMark(x: .value("Day", date(point.day), unit: .day), y: .value("Asleep", point.value))
                    .foregroundStyle(LinearGradient(colors: [TetherBrand.dusk, TetherBrand.dusk.opacity(0.25)],
                                                    startPoint: .top, endPoint: .bottom))
                    .clipShape(.rect(cornerRadius: days <= 30 ? 4 : 1))
            }
            RuleMark(y: .value("Eight hours", Self.sleepGoal))
                .foregroundStyle(TetherBrand.bone.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("8 h").font(.caption2).foregroundStyle(TetherBrand.sub)
                }
        }
        .chartYScale(domain: 0...top)
        .chartYAxis(.hidden)
        .chartXAxis { dateAxis }
    }

    /// The measure as a soft line with a fading area under it and the average dashed across.
    private var lineChart: some View {
        let domain = yDomain
        return Chart {
            ForEach(series.points) { point in
                AreaMark(x: .value("Day", date(point.day)), yStart: .value("Floor", domain.lowerBound),
                         yEnd: .value(series.name, point.value))
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.25), tint.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Day", date(point.day)), y: .value(series.name, point.value))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.catmullRom)
            }
            if let average = series.average {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(TetherBrand.sub.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            if let last = series.points.last {
                PointMark(x: .value("Day", date(last.day)), y: .value(series.name, last.value))
                    .foregroundStyle(tint).symbolSize(44)
            }
        }
        .chartYScale(domain: domain)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel { if let number = value.as(Double.self) { Text(format(number)) } }
                    .foregroundStyle(TetherBrand.sub)
            }
        }
        .chartXAxis { dateAxis }
    }

    private var dateAxis: some AxisContent {
        AxisMarks(values: tickDates) { _ in
            AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(TetherBrand.sub)
        }
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

    /// The headline average: sleep as hours and minutes, Charge with %, the rest with their unit.
    private func display(_ value: Double) -> String {
        if series.name == "Asleep" { return ScoreStrip.clock(value * 60) }
        let unit = series.unit
        if unit.isEmpty { return format(value) }
        return unit == "%" ? "\(format(value))%" : "\(format(value)) \(unit)"
    }

    /// "↑ 4 ms" from the first half of the range to the second; sleep in minutes.
    private func changeText(_ change: Double) -> String {
        if series.name == "Asleep" {
            let minutes = Int((abs(change) * 60).rounded())
            return minutes == 0 ? "Level" : "\(change > 0 ? "↑" : "↓") \(minutes) min"
        }
        let size = format(abs(change))
        if size == format(0) { return "Level" }
        return "\(change > 0 ? "↑" : "↓") \(size)\(series.unit.isEmpty ? "" : " \(series.unit)")"
    }

    private func format(_ value: Double) -> String { String(format: "%.\(series.decimals)f", value) }

    private static let dayKey: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func date(_ day: String) -> Date { Self.dayKey.date(from: day) ?? .now }
}
