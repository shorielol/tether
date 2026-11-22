import Charts
import SwiftUI
import TetherCore

/// Effort and heart rate in depth: the day's heart rate coloured by zone, your own bpm range for
/// each zone, the hard stretches and how fast your heart came down after them, and Effort as it built.
struct EffortDetailView: View {
    let today: TodaySnapshot
    let detail: EffortDetail
    var steps: DailySteps?

    @State private var selected: Date?

    var body: some View {
        TabScreen {
            hero
            if let steps, steps.hasData { stepsCard(steps) }
            heartRate
            zones
            stretches
            if detail.effortCurve.count >= 2 { effortBuild }
            HowItsWorkedOut(text: method)
        }
        .navigationTitle("Effort")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: Hero

    private var hero: some View {
        DetailHero(label: "Effort so far", meaning: heroMeaning) {
            Text(today.effort.map { String(format: "%.1f", $0) } ?? "–")
        }
    }

    /// Out of 100, plus calories when the profile has a weight to estimate them from.
    private var heroMeaning: String {
        guard let total = today.caloriesTotal else { return "out of 100 · add your weight in the profile for calories" }
        return "out of 100 · \(total.formatted()) kcal, \((today.caloriesActive ?? 0).formatted()) active"
    }

    private var method: String {
        let resting = switch today.restingSource {
        case .profile: "your profile"
        case .lowestFiveMinutes: "your lowest 5 minutes today"
        case .defaultValue: "a default until you've rested"
        }
        return "Effort adds up the time your heart rate spends above resting, weighting harder zones more, on a 0–100 scale. Zones are shares of your max heart rate (\(today.maxHR), from your age); resting is \(today.restingHR) bpm, from \(resting). Heart-rate recovery is how far your heart rate falls in the minutes after hard work: a bigger drop is a fitter heart. Calories are an estimate from heart rate, age and weight."
    }

    // MARK: Steps

    private func stepsCard(_ steps: DailySteps) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Steps").font(.headline)
                Spacer()
                Text("\(steps.total.formatted()) · \(steps.movingMinutes) min moving")
                    .font(.caption).foregroundStyle(TetherBrand.sub).monospacedDigit()
            }
            Chart(steps.hours) { hour in
                BarMark(x: .value("Hour", hour.hour), y: .value("Steps", hour.steps), width: .fixed(7))
                    .foregroundStyle(TetherBrand.bone)
                    .clipShape(.rect(cornerRadii: .init(topLeading: 3, topTrailing: 3)))
            }
            .chartXScale(domain: -0.5...23.5)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18]) { value in
                    AxisValueLabel {
                        if let hour = value.as(Int.self) { Text(hourLabel(hour)) }
                    }
                }
            }
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
            .frame(height: 120)
            .accessibilityLabel("Steps by hour today, \(steps.total) in all")
            Text("From your strap's own step counter. New steps arrive each time Tether syncs the strap's history, about every 30 minutes.")
                .font(.caption).foregroundStyle(TetherBrand.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private func hourLabel(_ hour: Int) -> String {
        var parts = DateComponents()
        parts.hour = hour
        return (Calendar.current.date(from: parts) ?? .now).formatted(.dateTime.hour())
    }

    // MARK: Heart rate

    private var heartRate: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Heart rate").font(.headline)
                Spacer()
                Text(selectionText).font(.caption).foregroundStyle(TetherBrand.sub).monospacedDigit()
            }
            Chart {
                ForEach(today.minuteSeries) { point in
                    LineMark(x: .value("Time", date(point.ts)), y: .value("BPM", point.bpm),
                             series: .value("Run", point.segment))
                        .foregroundStyle(TetherBrand.sub.opacity(0.55))
                        .lineStyle(.init(lineWidth: 1.2))
                }
                ForEach(zonedMinutes) { point in
                    PointMark(x: .value("Time", date(point.ts)), y: .value("BPM", point.bpm))
                        .foregroundStyle(TetherBrand.zone(zone(point.bpm)))
                        .symbolSize(14)
                }
                if let point = selectedPoint {
                    RuleMark(x: .value("Time", date(point.ts))).foregroundStyle(TetherBrand.sub.opacity(0.6))
                    PointMark(x: .value("Time", date(point.ts)), y: .value("BPM", point.bpm))
                        .foregroundStyle(TetherBrand.text).symbolSize(50)
                }
            }
            .chartYScale(domain: bpmDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                    AxisGridLine().foregroundStyle(TetherBrand.cardStroke)
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
            .chartXSelection(value: $selected)
            .frame(height: 200)
            .accessibilityLabel("Heart rate today, from \(today.minBPM ?? 0) to \(today.maxBPM ?? 0) beats per minute")
            Grid(alignment: .leading, horizontalSpacing: 16) {
                GridRow {
                    Metric(label: "Lowest", value: today.minBPM.map { "\($0)" } ?? "–")
                    Metric(label: "Average", value: today.avgBPM.map { "\($0)" } ?? "–")
                    Metric(label: "Highest", value: today.maxBPM.map { "\($0)" } ?? "–")
                    Metric(label: "Resting", value: "\(today.restingHR)", note: restingNote)
                }
            }
        }
        .card()
    }

    /// The day's own range with a little room, so the line uses the whole chart.
    private var bpmDomain: ClosedRange<Double> {
        let values = today.minuteSeries.map(\.bpm)
        let low = ((values.min() ?? 50) - 8).rounded(.down)
        return low...max(low + 40, ((values.max() ?? 120) + 8).rounded(.up))
    }

    /// Minutes in Zone 1 or above, coloured by zone over the grey line.
    private var zonedMinutes: [TodaySnapshot.MinutePoint] { today.minuteSeries.filter { zone($0.bpm) > 0 } }

    private func zone(_ bpm: Double) -> Int { TodayAnalytics.zone(bpm: Int(bpm.rounded()), maxHR: today.maxHR) }

    private var selectedPoint: TodaySnapshot.MinutePoint? {
        guard let selected else { return nil }
        let ts = Int(selected.timeIntervalSince1970)
        return today.minuteSeries.min { abs($0.ts - ts) < abs($1.ts - ts) }
    }

    private var selectionText: String {
        guard let point = selectedPoint else { return "Hold to see a time" }
        let number = zone(point.bpm)
        let zoneText = number == 0 ? "below zones" : "Zone \(number)"
        return "\(date(point.ts).formatted(date: .omitted, time: .shortened)) · \(Int(point.bpm.rounded())) bpm · \(zoneText)"
    }

    private var restingNote: String {
        switch today.restingSource {
        case .profile: "from your profile"
        case .lowestFiveMinutes: "lowest 5 min"
        case .defaultValue: "default"
        }
    }

    // MARK: Zones

    private var zones: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your zones").font(.headline)
                Spacer()
                Text("max HR \(today.maxHR)").font(.caption).foregroundStyle(TetherBrand.sub).monospacedDigit()
            }
            ForEach(detail.zones.reversed()) { zone in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(TetherBrand.zone(zone.number)).frame(width: 8, height: 8).padding(.top, 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Zone \(zone.number) · \(TetherBrand.zoneNames[zone.number])").font(.subheadline)
                        Text("\(zone.lowerBPM)–\(zone.upperBPM) bpm · \(ZoneStyle.meaning(zone.number))")
                            .font(.caption).foregroundStyle(TetherBrand.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Text("\(zone.minutes) min").font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    // MARK: Hard stretches

    private var stretches: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hard stretches").font(.headline)
            if detail.stretches.isEmpty {
                Text("No stretch of 5 minutes or more in Zone 3 or above today.")
                    .font(.subheadline).foregroundStyle(TetherBrand.sub)
            }
            ForEach(detail.stretches.reversed()) { stretch in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(time(stretch.start)) – \(time(stretch.end + 60))").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(stretch.minutes) min").font(.subheadline).monospacedDigit()
                    }
                    Text("Average \(stretch.averageBPM) · peak \(stretch.peakBPM) bpm · up to Zone \(stretch.topZone)")
                        .font(.caption).foregroundStyle(TetherBrand.sub)
                    if let recovery = recoveryText(stretch) {
                        Label(recovery, systemImage: "arrow.down.heart")
                            .font(.caption).foregroundStyle(TetherBrand.good)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    private func recoveryText(_ stretch: EffortDetail.Stretch) -> String? {
        switch (stretch.dropAfterOneMinute, stretch.dropAfterTwoMinutes) {
        case let (one?, two?): "Down \(one) bpm after 1 min, \(two) after 2"
        case let (one?, nil): "Down \(one) bpm after 1 min"
        default: nil
        }
    }

    // MARK: Effort through the day

    private var effortBuild: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How Effort built up").font(.headline)
            Chart(detail.effortCurve) { point in
                AreaMark(x: .value("Time", date(point.ts)), y: .value("Effort", point.effort))
                    .foregroundStyle(TetherBrand.ember.opacity(0.18))
                LineMark(x: .value("Time", date(point.ts)), y: .value("Effort", point.effort))
                    .foregroundStyle(TetherBrand.ember)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                    AxisGridLine().foregroundStyle(TetherBrand.cardStroke)
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
            .frame(height: 140)
            .accessibilityLabel("Effort through the day, reaching \(today.effort.map { String(format: "%.1f", $0) } ?? "0")")
        }
        .card()
    }

    private func date(_ ts: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(ts)) }
    private func time(_ ts: Int) -> String { date(ts).formatted(date: .omitted, time: .shortened) }
}

/// What each heart-rate zone feels like, in a few words.
enum ZoneStyle {
    static func meaning(_ zone: Int) -> String {
        switch zone {
        case 1: "light movement, walking"
        case 2: "easy, you could chat"
        case 3: "steady work that builds fitness"
        case 4: "hard, talking is tough"
        case 5: "all-out"
        default: ""
        }
    }
}
