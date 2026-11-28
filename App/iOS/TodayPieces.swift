import Charts
import SwiftUI
import TetherCore

// MARK: - Range bar

/// A value on a thin track, with your normal shown as a lighter band behind it.
struct RangeBar: View {
    let placement: RangePlacement
    var tint: Color = TetherBrand.text
    /// False before there's a value, so an empty bar doesn't look like a reading of zero.
    var showsValue = true

    private static let dot: CGFloat = 12
    private static let track: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(TetherBrand.track).frame(height: Self.track)
                if let band = placement.band {
                    Capsule().fill(Color.white.opacity(0.24))
                        .frame(width: max(Self.track, (band.upperBound - band.lowerBound) * width), height: Self.track)
                        .offset(x: band.lowerBound * width)
                }
                if showsValue {
                    Circle().fill(tint)
                        .frame(width: Self.dot, height: Self.dot)
                        .overlay(Circle().stroke(TetherBrand.ink, lineWidth: 2))
                        .offset(x: placement.value * width - Self.dot / 2)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: Self.dot)
        .accessibilityHidden(true)
    }
}

// MARK: - Score strip

/// Charge, Sleep and Effort side by side: the day's answer, each with your normal under it.
struct ScoreStrip: View {
    let charge: Double?
    let chargeBand: NormalBand?
    let progress: BaselineProgress
    let night: NightSummary?
    let sleepBand: NormalBand?
    let effort: Double?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                                                  : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        VStack(spacing: 18) {
            DetailLink(.recovery) { ChargeOrb(charge: charge, band: chargeBand, progress: progress) }
            layout {
                DetailLink(.sleep) { sleepColumn.card(padding: 16) }
                DetailLink(.effort) { effortColumn.card(padding: 16) }
            }
        }
    }

    @ViewBuilder private var sleepColumn: some View {
        if let minutes = night?.totalSleepMin {
            let domain = sleepBand.map { RangePlacement.domain(around: $0, value: minutes) } ?? 240...600
            ScoreColumn(label: "Sleep", caption: sleepWindow ?? "last night",
                        accessibility: "Slept \(DayLine.duration(minutes))") {
                Text(Self.clock(minutes))
            } bar: {
                RangeBar(placement: RangePlacement(value: minutes, band: sleepBand, domain: domain))
            }
        } else {
            ScoreColumn(label: "Sleep", caption: "after tonight", accessibility: "No night recorded yet") {
                Text("–").foregroundStyle(TetherBrand.sub)
            } bar: { RangeBar(placement: RangePlacement(value: 0, band: nil, domain: 0...1), showsValue: false) }
        }
    }

    private var effortTarget: NormalBand? { charge.map { EffortTarget.band(for: ChargeZone(charge: $0)) } }

    private var effortColumn: some View {
        ScoreColumn(label: "Effort",
                    caption: effortTarget.map { "target \(Int($0.low))–\(Int($0.high))" } ?? "of 100 so far",
                    accessibility: "Effort \(effort.map { String(format: "%.1f", $0) } ?? "not started") of 100") {
            Text(effort.map { String(format: "%.1f", $0) } ?? "–")
        } bar: {
            RangeBar(placement: RangePlacement(value: effort ?? 0, band: effortTarget, domain: 0...100), tint: TetherBrand.ember,
                     showsValue: effort != nil)
        }
    }

    private var sleepWindow: String? {
        guard let start = night?.sleepStart, let end = night?.sleepEnd else { return nil }
        let format = Date.FormatStyle(date: .omitted, time: .shortened)
        return "\(Date(timeIntervalSince1970: TimeInterval(start)).formatted(format)) – \(Date(timeIntervalSince1970: TimeInterval(end)).formatted(format))"
    }

    /// "6:36" for six hours thirty-six minutes.
    static func clock(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct ScoreColumn<Value: View, Bar: View>: View {
    let label: String
    let caption: String
    let accessibility: String
    @ViewBuilder var value: Value
    @ViewBuilder var bar: Bar

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: label)
            value
                .font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            bar
            Text(caption).font(.footnote).foregroundStyle(TetherBrand.sub)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }
}

// MARK: - Day ribbon

/// Today's heart rate across 24 hours: sleep shaded, the zones as a strip along the bottom, and now.
struct TodayRibbon: View {
    let today: TodaySnapshot
    let sleep: ClosedRange<Int>?
    let now: Int
    /// Live heart rate while the strap is connected; nil shows the day's range instead.
    var live: Int?
    /// Changes with every sample, so the heart beats as they arrive.
    var beat: Int?
    /// Moments marked by double-tapping the strap, drawn as pins.
    var marks: [Int] = []

    @State private var drawn = false

    private var dayStart: Int {
        Int(Calendar.current.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(today.window.lowerBound))).timeIntervalSince1970)
    }
    private var yDomain: ClosedRange<Double> {
        let values = today.minuteSeries.map(\.bpm) + [live.map(Double.init)].compactMap { $0 }
        let low = max(30, ((values.min() ?? 50) - 12).rounded(.down))
        return low...max(low + 60, ((values.max() ?? 120) + 6).rounded(.up))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your day").font(.headline)
                Spacer()
                if let live {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: "heart.fill").font(.footnote).foregroundStyle(TetherBrand.ember)
                            .symbolEffect(.bounce, value: beat)
                        Text("\(live)").font(.headline).monospacedDigit().contentTransition(.numericText())
                        Text("bpm now").font(.footnote).foregroundStyle(TetherBrand.sub)
                    }
                    .animation(.smooth, value: live)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Heart rate now, \(live) beats per minute")
                } else if let low = today.minBPM, let high = today.maxBPM {
                    Text("\(low)–\(high) bpm").font(.footnote).foregroundStyle(TetherBrand.sub).monospacedDigit()
                }
                DetailChevron()
            }
            chart
                .frame(height: 104)
                .padding(.vertical, 4)
                .mask(alignment: .leading) {
                    GeometryReader { geo in
                        Rectangle().frame(width: drawn ? geo.size.width : 0)
                    }
                }
        }
        .card(padding: 16)
        .entrance($drawn, Motion.draw, delay: 0.3)
    }

    private var chart: some View {
        let domain = yDomain
        let stripTop = domain.lowerBound + (domain.upperBound - domain.lowerBound) * 0.06
        return Chart {
            if let sleep = clamped(sleep) {
                RectangleMark(xStart: .value("Asleep from", date(sleep.lowerBound)),
                              xEnd: .value("Asleep to", date(sleep.upperBound)))
                    .foregroundStyle(TetherBrand.dusk.opacity(0.18))
            }
            ForEach(today.minuteSeries) { point in
                LineMark(x: .value("Time", date(point.ts)), y: .value("Heart rate", point.bpm),
                         series: .value("Stretch", point.segment))
                    .foregroundStyle(Color(white: 0.88))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            ForEach(zoneRuns, id: \.start) { run in
                RectangleMark(xStart: .value("Zone from", date(run.start)), xEnd: .value("Zone to", date(run.end)),
                              yStart: .value("Strip bottom", domain.lowerBound), yEnd: .value("Strip top", stripTop))
                    .foregroundStyle(TetherBrand.zone(run.zone))
            }
            ForEach(marks, id: \.self) { mark in
                RuleMark(x: .value("Marked", date(mark)))
                    .foregroundStyle(TetherBrand.ember.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .accessibilityLabel("Marked at \(date(mark).formatted(date: .omitted, time: .shortened))")
            }
            RuleMark(x: .value("Now", date(now)))
                .foregroundStyle(Color.white.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 1))
            if let live {
                PointMark(x: .value("Now", date(now)), y: .value("Heart rate now", Double(live)))
                    .foregroundStyle(TetherBrand.ember)
                    .symbolSize(44)
            }
        }
        .chartXScale(domain: date(dayStart)...date(dayStart + 86_400))
        .chartYScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisValueLabel(format: .dateTime.hour(), verticalSpacing: 8)
                    .foregroundStyle(TetherBrand.sub)
            }
        }
        .chartYAxis(.hidden)
        .accessibilityLabel(summary)
    }

    /// Consecutive minutes in the same zone, merged so the strip is a handful of marks, not hundreds.
    private var zoneRuns: [(start: Int, end: Int, zone: Int)] {
        var runs: [(start: Int, end: Int, zone: Int)] = []
        for point in today.minuteSeries {
            let zone = TodayAnalytics.zone(bpm: Int(point.bpm.rounded()), maxHR: today.maxHR)
            guard zone > 0 else { continue }
            if let last = runs.last, last.zone == zone, point.ts - last.end <= 120 {
                runs[runs.count - 1].end = point.ts + 60
            } else {
                runs.append((point.ts, point.ts + 60, zone))
            }
        }
        return runs
    }

    private func clamped(_ span: ClosedRange<Int>?) -> ClosedRange<Int>? {
        guard let span else { return nil }
        let start = max(span.lowerBound, dayStart), end = min(span.upperBound, dayStart + 86_400)
        return start < end ? start...end : nil
    }

    private func date(_ ts: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(ts)) }

    private var summary: String {
        guard let low = today.minBPM, let high = today.maxBPM else { return "Heart rate today: no samples yet" }
        return "Heart rate today, from \(low) to \(high) beats per minute"
    }
}

// MARK: - Recovery

// MARK: - Strap chip

/// The strap in one small control: link state and battery. Opens the strap sheet.
struct StrapChip: View {
    @Environment(AppModel.self) private var model
    let action: () -> Void

    var body: some View {
        let collector = model.collector
        Button(action: action) {
            HStack(spacing: 7) {
                Circle().fill(color(collector)).frame(width: 8, height: 8)
                Text(label(collector)).font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(TetherBrand.cardFill, in: .capsule)
            .overlay(Capsule().strokeBorder(TetherBrand.cardStroke))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility(collector))
        .accessibilityHint("Opens your strap")
    }

    private func label(_ collector: LiveCollector) -> String {
        guard collector.isPaired else { return "Pair" }
        guard collector.link == .connected else { return "Off" }
        return collector.batteryPercent.map { "\($0)%" } ?? "Live"
    }

    private func color(_ collector: LiveCollector) -> Color {
        switch collector.link {
        case .connected: TetherBrand.good
        case .connecting, .reconnecting, .scanning: TetherBrand.headsUp
        default: TetherBrand.sub
        }
    }

    private func accessibility(_ collector: LiveCollector) -> String {
        guard collector.isPaired else { return "No strap paired" }
        guard collector.link == .connected else { return "Strap not connected" }
        return collector.batteryPercent.map { "Strap connected, battery \($0) percent" } ?? "Strap connected"
    }
}

/// Under Today's title: whether the strap's memory is being read right now, or when it last was.
struct SyncLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let collector = model.collector
        if collector.isSyncingHistory {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Updating from your strap…")
            }
            .font(.caption).foregroundStyle(TetherBrand.sub)
            .accessibilityElement(children: .combine)
        } else if collector.isPaired, let last = collector.lastHistorySync {
            Text("Updated from your strap \(Self.when(last))")
                .font(.caption).foregroundStyle(TetherBrand.sub)
        }
    }

    private static func when(_ ts: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        let time = date.formatted(date: .omitted, time: .shortened)
        return Calendar.current.isDateInToday(date) ? "at \(time)" : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}
