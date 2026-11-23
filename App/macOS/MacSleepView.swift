import Charts
import SwiftUI
import TetherCore
import TetherFiles

/// The night that ended on the selected day, as in the approved mockup: time asleep as the hero
/// with four metrics beside it, the stages across the full width, and the last two weeks in a
/// quiet panel you can click to move between nights.
struct MacSleepView: View {
    @Environment(MacModel.self) private var model

    var body: some View {
        if let night = model.selectedRecord?.night, night.sleepStart != nil {
            heroRow(night)
            VStack(alignment: .leading, spacing: Space.l) {
                SectionHeader(title: "Stages") { Text("Estimated from heart rate") }
                Hypnogram(night: night).frame(height: 220)
                StageTotals(night: night)
            }
            Panel {
                RecentNights(records: model.records, selectedKey: model.selectedKey) { day in
                    model.selectedDay = day
                }
            }
        } else {
            ContentUnavailableView {
                Label(model.isShowingToday ? "Last night isn't scored yet" : "No night for this day", systemImage: "moon.zzz")
            } description: {
                Text("Your iPhone scores each night the morning after, once you've been awake about 20 minutes.")
            }
            .frame(maxWidth: .infinity, minHeight: 420)
        }
    }

    // MARK: Hero row

    private func heroRow(_ night: NightSummary) -> some View {
        let hero = HeroNumber(label: "Asleep", value: hoursMinutes(night.totalSleepMin), unit: "h",
                              caption: heroCaption(night), tint: Theme.dusk)
        let metrics = HStack(alignment: .top, spacing: Space.section - 8) {
            MetricView(label: "Efficiency", value: night.efficiency.map { "\(Int(($0 * 100).rounded()))" } ?? "—",
                       unit: "%", caption: "of time in bed")
            MetricView(label: "Resting", value: night.restingHR.map(String.init) ?? "—", unit: "bpm",
                       caption: "lowest steady rate")
            MetricView(label: "HRV", value: night.hrv.map { "\(Int($0.rounded()))" } ?? "—", unit: "ms",
                       caption: hrvCaption(night))
            MetricView(label: "Breathing", value: night.respRate.map { String(format: "%.1f", $0) } ?? "—",
                       caption: "breaths a minute")
        }
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: Space.section) {
                hero
                Spacer(minLength: 0)
                metrics
            }
            VStack(alignment: .leading, spacing: Space.xxl) {
                hero
                metrics
            }
        }
    }

    private func heroCaption(_ night: NightSummary) -> String? {
        guard let start = night.sleepStart, let end = night.sleepEnd else { return nil }
        var caption = "\(clock(start)) – \(clock(end))"
        if let woke = night.disturbances, woke > 0 { caption += " · woke \(woke) time\(woke == 1 ? "" : "s")" }
        return caption
    }

    /// The HRV driver says how the night compares with your normal; without one, say what the number is.
    private func hrvCaption(_ night: NightSummary) -> String {
        night.drivers.first { $0.label == "HRV" }?.valueText ?? "overnight average"
    }

    private func hoursMinutes(_ minutes: Double?) -> String {
        guard let minutes else { return "—" }
        let total = Int(minutes.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    private func clock(_ ts: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(ts)).formatted(date: .omitted, time: .shortened)
    }
}

extension Theme {
    /// Sleep depth as one Dusk ramp, validated as ordinal in both modes. Awake stays neutral.
    static func stage(_ kind: NightSummary.Stage.Kind) -> Color {
        switch kind {
        case .wake: Color.secondary.opacity(0.45)
        case .light: Color(light: 0x9FA5E2, dark: 0x6164B7)
        case .rem: Color(light: 0x7174D0, dark: 0x898EE5)
        case .deep: Color(light: 0x4B47AD, dark: 0xB8BEFD)
        }
    }

    static func stageName(_ kind: NightSummary.Stage.Kind) -> String {
        switch kind {
        case .wake: "Awake"
        case .rem: "REM"
        case .light: "Light"
        case .deep: "Deep"
        }
    }
}

/// Stages as lanes, deepest at the bottom, like a hypnogram on paper. Lane names sit in a fixed
/// 64 pt column so the plot lines up the same way every night.
struct Hypnogram: View {
    let night: NightSummary
    private let lanes: [NightSummary.Stage.Kind] = [.wake, .rem, .light, .deep]
    /// Where each lane's centre sits, read from the chart so the names line up with the bands.
    @State private var laneCenters: [CGFloat] = []

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            ZStack(alignment: .topLeading) {
                ForEach(Array(zip(lanes, laneCenters)), id: \.0) { kind, center in
                    Text(Theme.stageName(kind)).font(.captionText).foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .leading)
                        .position(x: 28, y: center)
                }
            }
            .frame(width: 56)
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)
            chart
        }
    }

    private var chart: some View {
        Chart(night.stages) { stage in
            RectangleMark(xStart: .value("From", date(stage.start)), xEnd: .value("To", date(stage.end)),
                          y: .value("Stage", Theme.stageName(stage.kind)), height: .ratio(0.7))
                .foregroundStyle(Theme.stage(stage.kind))
                .clipShape(.rect(cornerRadius: 2))
        }
        .chartYScale(domain: lanes.map(Theme.stageName))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour)) { _ in
                AxisGridLine().foregroundStyle(Theme.grid)
                AxisValueLabel(format: .dateTime.hour(), verticalSpacing: Space.s)
            }
        }
        .chartBackground { proxy in
            GeometryReader { geo in
                let centers = centers(proxy, geo)
                Color.clear
                    .onAppear { laneCenters = centers }
                    .onChange(of: centers) { _, new in laneCenters = new }
            }
        }
        .accessibilityLabel("Sleep stages from \(clock(night.sleepStart)) to \(clock(night.sleepEnd))")
    }

    private func centers(_ proxy: ChartProxy, _ geo: GeometryProxy) -> [CGFloat] {
        guard let plot = proxy.plotFrame else { return [] }
        let top = geo[plot].minY
        return lanes.compactMap { proxy.position(forY: Theme.stageName($0)).map { $0 + top } }
    }

    private func date(_ ts: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(ts)) }
    private func clock(_ ts: Int?) -> String {
        ts.map { date($0).formatted(date: .omitted, time: .shortened) } ?? "unknown"
    }
}

/// Time per stage under the hypnogram, each with its own swatch so colour is never the only cue.
struct StageTotals: View {
    let night: NightSummary

    private var awakeMinutes: Double? {
        guard !night.stages.isEmpty else { return nil }
        let seconds = night.stages.filter { $0.kind == .wake }.reduce(0) { $0 + $1.end - $1.start }
        return Double(seconds) / 60
    }

    var body: some View {
        HStack(spacing: Space.xl) {
            item(.deep, night.deepMin)
            item(.rem, night.remMin)
            item(.light, night.lightMin)
            item(.wake, awakeMinutes)
            Spacer(minLength: 0)
        }
        .font(.bodyText)
    }

    private func item(_ kind: NightSummary.Stage.Kind, _ minutes: Double?) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(Theme.stage(kind)).frame(width: 10, height: 10)
            Text(Theme.stageName(kind)).foregroundStyle(.secondary)
            Text(duration(minutes)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func duration(_ minutes: Double?) -> String {
        guard let minutes else { return "—" }
        let total = Int(minutes.rounded())
        return total < 60 ? "\(total) m" : "\(total / 60) h \(total % 60) m"
    }
}

/// Fourteen nights as thin bars of time asleep. Click one to open that night.
struct RecentNights: View {
    let records: [DayRecord]
    let selectedKey: String
    var select: (Date) -> Void

    @State private var hoveredDay: String?

    private var nights: [(key: String, date: Date, hours: Double)] {
        records.suffix(14).compactMap { record in
            guard let minutes = record.night?.totalSleepMin, let date = Self.parse(record.day) else { return nil }
            return (record.day, date, minutes / 60)
        }
    }

    var body: some View {
        SectionHeader(title: "Last two weeks") { Text(summaryText) }
        if nights.count < 2 {
            Text("More nights appear here as your iPhone scores them.").font(.bodyText).foregroundStyle(.secondary)
        } else {
            chart.frame(height: 120)
        }
    }

    private var chart: some View {
        Chart(nights, id: \.key) { night in
            BarMark(x: .value("Night", night.date, unit: .day), y: .value("Hours asleep", night.hours), width: .fixed(14))
                .foregroundStyle(night.key == selectedKey ? Theme.dusk : Theme.dusk.opacity(0.4))
                .clipShape(.rect(cornerRadii: .init(topLeading: 3, topTrailing: 3)))
                .annotation(position: .top, spacing: 4) {
                    if night.key == hoveredDay || night.key == selectedKey {
                        Text(String(format: "%.1f h", night.hours)).font(.captionText).foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
        }
        .chartXScale(domain: fortnight)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 4, 8]) { _ in
                AxisGridLine().foregroundStyle(Theme.grid)
                AxisValueLabel()
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        if case .active(let point) = phase { hoveredDay = key(at: point, proxy, geo) } else { hoveredDay = nil }
                    }
                    .onTapGesture { point in
                        if let key = key(at: point, proxy, geo), let date = Self.parse(key) { select(date) }
                    }
            }
        }
        .accessibilityLabel("Time asleep over the last \(nights.count) nights. \(summaryText)")
    }

    /// Always fourteen days wide, ending on the newest night, so bars keep their width as nights arrive.
    private var fortnight: ClosedRange<Date> {
        let calendar = Calendar.current
        let last = nights.last?.date ?? calendar.startOfDay(for: .now)
        let end = calendar.date(byAdding: .day, value: 1, to: last) ?? last
        let start = calendar.date(byAdding: .day, value: -13, to: last) ?? last
        return start...end
    }

    private var summaryText: String {
        guard nights.count >= 2 else { return "" }
        let mean = nights.map(\.hours).reduce(0, +) / Double(nights.count)
        return String(format: "Average %.1f h · click a night to open it", mean)
    }

    private func key(at point: CGPoint, _ proxy: ChartProxy, _ geo: GeometryProxy) -> String? {
        guard let plot = proxy.plotFrame, let when: Date = proxy.value(atX: point.x - geo[plot].origin.x) else { return nil }
        return nights.min(by: { abs($0.date.timeIntervalSince(when)) < abs($1.date.timeIntervalSince(when)) })?.key
    }

    static func parse(_ day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
