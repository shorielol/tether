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
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 18))
                                                  : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
        layout {
            DetailLink(.recovery) { chargeColumn }
            DetailLink(.sleep) { sleepColumn }
            DetailLink(.effort) { effortColumn }
        }
    }

    @ViewBuilder private var chargeColumn: some View {
        if let charge {
            let zone = ChargeZone(charge: charge)
            let rounded = Int(charge.rounded())
            ScoreColumn(label: "Charge", caption: zone.name, accessibility: "Charge \(rounded) percent, \(zone.name)") {
                Text("\(Text("\(rounded)"))\(Text("%").font(.title2.weight(.semibold)))")
                    .foregroundStyle(TetherBrand.charge(zone))
            } bar: {
                RangeBar(placement: RangePlacement(value: charge, band: chargeBand, domain: 0...100),
                         tint: TetherBrand.charge(zone))
            }
        } else {
            let done = min(progress.scoredNights, BaselineProgress.chargeNights)
            ScoreColumn(label: "Charge", caption: "\(done) of \(BaselineProgress.chargeNights) nights",
                        accessibility: "Charge is learning, \(done) of \(BaselineProgress.chargeNights) nights") {
                Text("Learning").font(.title3.bold()).foregroundStyle(TetherBrand.sub)
            } bar: {
                HStack(spacing: 3) {
                    ForEach(0..<BaselineProgress.chargeNights, id: \.self) { index in
                        Capsule().fill(index < done ? TetherBrand.dusk : TetherBrand.track).frame(height: 6)
                    }
                }
                .frame(height: 12)
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

    private var effortColumn: some View {
        ScoreColumn(label: "Effort", caption: "of 100 so far",
                    accessibility: "Effort \(effort.map { String(format: "%.1f", $0) } ?? "not started") of 100") {
            Text(effort.map { String(format: "%.1f", $0) } ?? "–")
        } bar: {
            RangeBar(placement: RangePlacement(value: effort ?? 0, band: nil, domain: 0...100), tint: TetherBrand.ember,
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
                .font(.system(.largeTitle, weight: .bold)).monospacedDigit()
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
                .frame(height: 96)
                .padding(.vertical, 6)
                .background(TetherBrand.cardFill, in: .rect(cornerRadius: 14))
        }
        .contentShape(.rect)
    }

    private var chart: some View {
        let domain = yDomain
        let stripTop = domain.lowerBound + (domain.upperBound - domain.lowerBound) * 0.06
        return Chart {
            if let sleep = clamped(sleep) {
                RectangleMark(xStart: .value("Asleep from", date(sleep.lowerBound)),
                              xEnd: .value("Asleep to", date(sleep.upperBound)))
                    .foregroundStyle(TetherBrand.dusk.opacity(0.16))
            }
            ForEach(today.minuteSeries) { point in
                LineMark(x: .value("Time", date(point.ts)), y: .value("Heart rate", point.bpm),
                         series: .value("Stretch", point.segment))
                    .foregroundStyle(Color(white: 0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            ForEach(zoneRuns, id: \.start) { run in
                RectangleMark(xStart: .value("Zone from", date(run.start)), xEnd: .value("Zone to", date(run.end)),
                              yStart: .value("Strip bottom", domain.lowerBound), yEnd: .value("Strip top", stripTop))
                    .foregroundStyle(TetherBrand.zone(run.zone))
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

/// What's behind Charge: last night's vitals against your normal, and which one moved it.
struct RecoveryCard: View {
    let detail: RecoveryDetail?
    let charge: Double?

    /// The vitals Charge reads. Sleep already has its own score at the top of Today.
    static let vitals: Set<String> = ["HRV", "Resting HR", "Breathing", "Skin temp"]
    @Environment(\.dynamicTypeSize) private var typeSize

    private var rows: [RecoveryDetail.Measure] { detail?.measures.filter { Self.vitals.contains($0.name) } ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recovery").font(.headline)
                Spacer()
                if let charge {
                    Text("why you're at \(Int(charge.rounded()))%").font(.footnote).foregroundStyle(TetherBrand.sub)
                }
                DetailChevron()
            }
            if rows.isEmpty {
                Text("Shows after your first scored night: HRV and resting heart rate against your normal.")
                    .font(.subheadline).foregroundStyle(TetherBrand.sub)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(rows) { row($0) }
                if let note = RecoveryNote.text(rows) {
                    Text(note).font(.footnote).foregroundStyle(TetherBrand.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .card(padding: 16)
        .contentShape(.rect)
    }

    @ViewBuilder private func row(_ measure: RecoveryDetail.Measure) -> some View {
        let placement = RangePlacement(value: measure.value, band: measure.band,
                                       domain: measure.band.map { RangePlacement.domain(around: $0, value: measure.value) }
                                           ?? (measure.value * 0.5)...(measure.value * 1.5))
        // Amber only for a night outside your normal in the worse direction; a good surprise stays neutral.
        let tint = placement.isInsideBand == false && measure.isBetter == false ? TetherBrand.headsUp : TetherBrand.text
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                                                  : AnyLayout(HStackLayout(spacing: 10))
        layout {
            if typeSize.isAccessibilitySize {
                Text(measure.name).foregroundStyle(TetherBrand.sub)
                Text(value(measure)).fontWeight(.semibold).monospacedDigit()
            } else {
                HStack(spacing: 10) {
                    Text(measure.name).foregroundStyle(TetherBrand.sub)
                        .frame(minWidth: 88, alignment: .leading)
                    Text(value(measure)).fontWeight(.semibold).monospacedDigit()
                        .frame(minWidth: 70, alignment: .leading)
                }
            }
            RangeBar(placement: placement, tint: tint)
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(measure.name) \(value(measure)), \(verdict(placement))")
    }

    private func value(_ measure: RecoveryDetail.Measure) -> String {
        let number = String(format: "%.\(measure.decimals)f", measure.value)
        return measure.unit.isEmpty ? number : "\(number) \(measure.unit)"
    }

    private func verdict(_ placement: RangePlacement) -> String {
        switch placement.isInsideBand {
        case true?: "in your normal"
        case false?: "outside your normal"
        case nil: "no normal yet"
        }
    }
}

// MARK: - Steps row

/// Today's steps from the strap's own counter. They arrive with each history sync, so the row says how
/// recent the count is.
struct StepsRow: View {
    let steps: DailySteps?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 10) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Steps").font(.headline)
                    reading
                }
                Spacer(minLength: 0)
            } else {
                Text("Steps").font(.headline)
                Spacer()
                reading
            }
            DetailChevron()
        }
        .card(padding: 14)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var reading: some View {
        if let steps, steps.hasData {
            VStack(alignment: .trailing, spacing: 1) {
                Text(steps.total.formatted()).font(.subheadline.weight(.semibold)).monospacedDigit()
                Text(asOf(steps)).font(.caption).foregroundStyle(TetherBrand.sub)
            }
        } else {
            Text("after the strap's next sync").font(.subheadline).foregroundStyle(TetherBrand.sub)
        }
    }

    private func asOf(_ steps: DailySteps) -> String {
        guard let ts = steps.lastSampleTs else { return "" }
        let time = Date(timeIntervalSince1970: TimeInterval(ts)).formatted(date: .omitted, time: .shortened)
        return steps.movingMinutes > 0 ? "\(steps.movingMinutes) min moving · as of \(time)" : "as of \(time)"
    }
}

// MARK: - Stress row

/// One line for stress: where it is now and since when. The hour-by-hour view opens from here.
struct StressRow: View {
    let today: TodaySnapshot

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 10) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stress").font(.headline)
                    reading
                }
                Spacer(minLength: 0)
            } else {
                Text("Stress").font(.headline)
                Spacer()
                reading
            }
            DetailChevron()
        }
        .card(padding: 14)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var reading: some View {
        HStack(spacing: 8) {
            if let current {
                Circle().fill(StressStyle.color(current.band)).frame(width: 8, height: 8)
            }
            Text(summary).font(.subheadline)
        }
    }

    /// The latest scored hour's band (the same Calm, Usual, High as the Stress screen), and when its run began.
    private var current: (band: StressBand, since: Int)? {
        let scored = today.stressHours.filter { !$0.wasActive && $0.level != nil }
        guard let last = scored.last, let value = last.level else { return nil }
        let band = StressBand(level: value)
        var since = last.hour
        for hour in scored.dropLast().reversed() {
            guard let level = hour.level, StressBand(level: level) == band, hour.hour == since - 1 else { break }
            since = hour.hour
        }
        return (band, since)
    }

    private var summary: String {
        guard let current else { return "Not enough data yet" }
        let hour = String(format: "%02d:00", current.since)
        return current.since == today.stressHours.last(where: { $0.level != nil })?.hour
            ? "\(current.band.name) at \(hour)" : "\(current.band.name) since \(hour)"
    }
}

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
            .background(Color.white.opacity(0.05), in: .capsule)
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
