import Charts
import SwiftUI
import TetherCore
import TetherFiles

/// One measure at a time, as in the approved mockup: the latest night as the hero, one large
/// chart with its average, and four quiet tiles that show every measure's shape and switch the chart.
struct TrendsView: View {
    @Environment(MacModel.self) private var model
    @AppStorage("tether.trends.measure") private var measure: TrendMeasure = .charge
    @AppStorage("tether.trends.days") private var days = 14

    var body: some View {
        let nights = scoredNights
        Group {
            if nights.count < 2 {
                ContentUnavailableView {
                    Label("Trends need a few nights", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("Each scored night adds a point. You have \(nights.count) so far.")
                }
                .frame(maxWidth: .infinity, minHeight: 420)
            } else {
                let points = measure.points(in: nights, days: days)
                hero(points)
                TrendChart(measure: measure, points: points, days: days).frame(height: 300)
                tiles(nights)
            }
        }
    }

    private var scoredNights: [(Date, NightSummary)] {
        model.records.compactMap { record in
            guard let night = record.night, night.sleepStart != nil, let date = RecentNights.parse(record.day) else { return nil }
            return (date, night)
        }
    }

    // MARK: Hero

    private func hero(_ points: [(Date, Double)]) -> some View {
        HeroNumber(label: "\(measure.title), last night",
                   value: points.last.map { measure.format($0.1) } ?? "—",
                   unit: measure.unit.isEmpty ? nil : measure.unit,
                   caption: caption(points), tint: measure.tint)
    }

    private func caption(_ points: [(Date, Double)]) -> String? {
        guard points.count >= 2 else { return nil }
        let values = points.map(\.1)
        let mean = values.reduce(0, +) / Double(values.count)
        return "Average \(measure.format(mean)) over \(values.count) nights · \(direction(values))"
    }

    /// The last three nights against the ones before: a move under a tenth of the measure's
    /// meaningful span reads as steady.
    private func direction(_ values: [Double]) -> String {
        let recent = values.suffix(3), earlier = values.dropLast(3)
        guard !earlier.isEmpty else { return "early days" }
        let change = recent.reduce(0, +) / Double(recent.count) - earlier.reduce(0, +) / Double(earlier.count)
        if abs(change) < measure.minSpan / 10 { return "steady" }
        return change > 0 ? "rising" : "falling"
    }

    // MARK: Tiles

    private func tiles(_ nights: [(Date, NightSummary)]) -> some View {
        HStack(spacing: Space.l) {
            ForEach(TrendMeasure.allCases) { item in
                TrendTile(measure: item, points: item.points(in: nights, days: days), isSelected: item == measure) {
                    measure = item
                }
            }
        }
    }
}

/// The four measures Trends can show, each on its own scale.
enum TrendMeasure: String, CaseIterable, Identifiable {
    case charge, asleep, hrv, resting
    var id: String { rawValue }

    var title: String {
        switch self {
        case .charge: "Charge"
        case .asleep: "Asleep"
        case .hrv: "HRV"
        case .resting: "Resting heart rate"
        }
    }

    var shortTitle: String { self == .resting ? "Resting" : title }

    var unit: String {
        switch self {
        case .charge: ""
        case .asleep: "h"
        case .hrv: "ms"
        case .resting: "bpm"
        }
    }

    var tint: Color {
        switch self {
        case .charge: Theme.ember
        case .asleep: Theme.dusk
        case .hrv, .resting: .primary
        }
    }

    /// The y axis never spans less than this, so a 1 bpm wobble doesn't look like a swing.
    var minSpan: Double {
        switch self {
        case .charge, .hrv: 30
        case .asleep: 3
        case .resting: 12
        }
    }

    /// A y range at least `minSpan` tall around the values, with a little headroom.
    func yDomain(_ values: [Double]) -> ClosedRange<Double> {
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let pad = max(minSpan * 0.1, (minSpan - (high - low)) / 2)
        return (low - pad)...(high + pad)
    }

    func value(_ night: NightSummary) -> Double? {
        switch self {
        case .charge: night.charge
        case .asleep: night.totalSleepMin.map { $0 / 60 }
        case .hrv: night.hrv
        case .resting: night.restingHR.map(Double.init)
        }
    }

    func format(_ value: Double) -> String {
        String(format: self == .asleep ? "%.1f" : "%.0f", value)
    }

    func points(in nights: [(Date, NightSummary)], days: Int) -> [(Date, Double)] {
        let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: .now)) ?? .distantPast
        return nights.filter { $0.0 >= start }.compactMap { date, night in value(night).map { (date, $0) } }
    }
}

/// The selected measure across the chosen range, with a dashed average and a hover readout.
struct TrendChart: View {
    let measure: TrendMeasure
    let points: [(Date, Double)]
    let days: Int

    @State private var hovered: Date?

    private var mean: Double? {
        points.isEmpty ? nil : points.map(\.1).reduce(0, +) / Double(points.count)
    }

    /// From the first night (at most the range back, at least a week) to the end of today, so a few
    /// nights fill the width. Each night is a whole day wide, so the last one needs today's full day.
    private var domain: ClosedRange<Date> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let oldest = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        let week = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let first = points.map(\.0).min() ?? week
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return min(max(first, oldest), week)...end
    }

    private var yDomain: ClosedRange<Double> { measure.yDomain(points.map(\.1)) }

    var body: some View {
        if points.isEmpty {
            Text("Not measured in this range yet.").font(.bodyText).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            chart
        }
    }

    private var chart: some View {
        Chart {
            if let mean {
                RuleMark(y: .value("Average", mean))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading, spacing: 4) {
                        Text("Average \(measure.format(mean))").font(.captionText).foregroundStyle(.secondary)
                    }
            }
            ForEach(points, id: \.0) { date, value in
                LineMark(x: .value("Night", date, unit: .day), y: .value(measure.title, value))
                    .foregroundStyle(measure.tint)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                PointMark(x: .value("Night", date, unit: .day), y: .value(measure.title, value))
                    .foregroundStyle(measure.tint)
                    .symbolSize(isHovered(date) ? 70 : 28)
            }
            if let point = hoveredPoint {
                RuleMark(x: .value("Night", point.0, unit: .day))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .annotation(position: isEarly(point.0) ? .trailing : .leading, alignment: .top, spacing: 12,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        tooltip(point)
                    }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 7)) { _ in
                AxisGridLine().foregroundStyle(Theme.grid)
                AxisValueLabel(format: .dateTime.day().month(.abbreviated), verticalSpacing: Space.s)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Theme.grid)
                AxisValueLabel()
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        guard case .active(let location) = phase, let plot = proxy.plotFrame,
                              let when: Date = proxy.value(atX: location.x - geo[plot].origin.x) else {
                            hovered = nil
                            return
                        }
                        hovered = when
                    }
            }
        }
        .accessibilityLabel("\(measure.title) over the last \(days) days")
    }

    private var hoveredPoint: (Date, Double)? {
        guard let hovered else { return nil }
        return points.min { abs($0.0.timeIntervalSince(hovered)) < abs($1.0.timeIntervalSince(hovered)) }
            .flatMap { abs($0.0.timeIntervalSince(hovered)) < 43_200 ? $0 : nil }
    }

    private func isHovered(_ date: Date) -> Bool {
        hoveredPoint.map { Calendar.current.isDate($0.0, inSameDayAs: date) } ?? false
    }

    private func isEarly(_ date: Date) -> Bool {
        date < domain.lowerBound.addingTimeInterval(domain.upperBound.timeIntervalSince(domain.lowerBound) / 2)
    }

    private func tooltip(_ point: (Date, Double)) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(point.0, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                .font(.captionText).foregroundStyle(.secondary)
            Text(measure.format(point.1) + (measure.unit.isEmpty ? "" : " \(measure.unit)"))
                .font(.bodyText.weight(.semibold)).monospacedDigit()
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.regularMaterial, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline))
    }
}

/// A measure's name, latest value and a sparkline. Clicking it puts that measure in the big chart.
struct TrendTile: View {
    let measure: TrendMeasure
    let points: [(Date, Double)]
    let isSelected: Bool
    var select: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(measure.shortTitle).font(.label).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(points.last.map { measure.format($0.1) } ?? "—").font(.readout(22)).monospacedDigit()
                    if !measure.unit.isEmpty { Text(measure.unit).font(.captionText).foregroundStyle(.secondary) }
                }
                sparkline.frame(height: 32)
            }
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: .rect(cornerRadius: 14))
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("\(measure.title), latest \(points.last.map { measure.format($0.1) } ?? "none")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fill: Color {
        isSelected ? Theme.groupFill : isHovering ? Theme.groupFill.opacity(0.5) : .clear
    }

    @ViewBuilder private var sparkline: some View {
        if points.count >= 2 {
            Chart(points, id: \.0) { date, value in
                LineMark(x: .value("Night", date), y: .value(measure.title, value))
                    .foregroundStyle(measure.tint.opacity(isSelected ? 1 : 0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: measure.yDomain(points.map(\.1)))
        } else {
            Color.clear
        }
    }
}
