import Charts
import SwiftUI
import TetherCore

enum SleepFormat {
    static func duration(minutes: Double?) -> String {
        guard let minutes else { return "–" }
        return DayLine.duration(minutes)
    }

    static func time(_ ts: Int?) -> String {
        guard let ts else { return "–" }
        return Date(timeIntervalSince1970: TimeInterval(ts)).formatted(date: .omitted, time: .shortened)
    }

    static func color(_ kind: NightSummary.Stage.Kind) -> Color {
        switch kind {
        case .wake: TetherBrand.headsUp
        case .rem: Color(red: 195 / 255, green: 203 / 255, blue: 1)
        case .light: TetherBrand.dusk
        case .deep: TetherBrand.deep
        }
    }

    static func name(_ kind: NightSummary.Stage.Kind) -> String {
        switch kind {
        case .wake: "Awake"
        case .rem: "REM"
        case .light: "Light"
        case .deep: "Deep"
        }
    }
}

struct NightHeroCard: View {
    let night: NightSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(SleepFormat.duration(minutes: night.totalSleepMin))
                .font(.system(size: 44, weight: .bold)).monospacedDigit()
            Text("\(SleepFormat.time(night.sleepStart)) – \(SleepFormat.time(night.sleepEnd))")
                .font(.headline).foregroundStyle(TetherBrand.sub).monospacedDigit()
            if let efficiency = night.efficiency {
                Text("\(Int((efficiency * 100).rounded()))% of the time in bed asleep")
                    .font(.subheadline).foregroundStyle(TetherBrand.sub)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// The night as one stepped path: a lane per stage (Awake at the top, Deep at the bottom), thin
/// lines joining each change, then each stage's share of the night in the same top-to-bottom order.
struct HypnogramCard: View {
    let night: NightSummary
    /// Top to bottom, as the lanes are drawn and the totals are listed.
    private static let order: [NightSummary.Stage.Kind] = [.wake, .rem, .light, .deep]
    private static let barHalfHeight = 0.34

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Stages").font(.headline)
                Spacer()
                Text("estimated from heart rate").font(.caption).foregroundStyle(TetherBrand.sub)
            }
            chart.frame(height: 150)
            if total > 0 {
                splitBar.frame(height: 8)
                totals
            }
        }
        .card()
    }

    // MARK: Chart

    private var chart: some View {
        Chart {
            ForEach(Self.order, id: \.self) { kind in
                RectangleMark(yStart: .value("Lane low", lane(kind) - 0.45), yEnd: .value("Lane high", lane(kind) + 0.45))
                    .foregroundStyle(Color.white.opacity(0.035))
            }
            ForEach(Array(zip(night.stages, night.stages.dropFirst())), id: \.0.id) { before, after in
                if before.kind != after.kind {
                    RuleMark(x: .value("Change", date(after.start)),
                             yStart: .value("From", lane(before.kind)), yEnd: .value("To", lane(after.kind)))
                        .foregroundStyle(Color.white.opacity(0.28))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            ForEach(night.stages) { stage in
                RectangleMark(xStart: .value("Start", date(stage.start)), xEnd: .value("End", date(stage.end)),
                              yStart: .value("Low", lane(stage.kind) - Self.barHalfHeight),
                              yEnd: .value("High", lane(stage.kind) + Self.barHalfHeight))
                    .foregroundStyle(SleepFormat.color(stage.kind))
                    .clipShape(.rect(cornerRadius: 2))
            }
        }
        .chartYScale(domain: -0.5...3.5)
        .chartYAxis {
            AxisMarks(position: .leading, values: Self.order.map(lane)) { value in
                AxisValueLabel {
                    if let index = value.as(Double.self), let kind = Self.order.first(where: { lane($0) == index }) {
                        Text(SleepFormat.name(kind)).font(.caption).foregroundStyle(TetherBrand.sub)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                AxisGridLine().foregroundStyle(TetherBrand.cardStroke)
                AxisValueLabel(format: .dateTime.hour()).foregroundStyle(TetherBrand.sub)
            }
        }
        .accessibilityLabel(summary)
    }

    /// Deep sits on the bottom lane (0), Awake on the top (3).
    private func lane(_ kind: NightSummary.Stage.Kind) -> Double {
        Double(Self.order.count - 1 - (Self.order.firstIndex(of: kind) ?? 0))
    }

    // MARK: Totals

    private func minutes(_ kind: NightSummary.Stage.Kind) -> Double {
        Double(night.stages.filter { $0.kind == kind }.reduce(0) { $0 + ($1.end - $1.start) }) / 60
    }

    private var total: Double { Self.order.reduce(0) { $0 + minutes($1) } }

    private func share(_ kind: NightSummary.Stage.Kind) -> Int { Int((minutes(kind) / max(total, 1) * 100).rounded()) }

    private var splitBar: some View {
        GeometryReader { geo in
            let kinds = Self.order.filter { minutes($0) > 0 }
            let gaps = CGFloat(max(kinds.count - 1, 0)) * 2
            HStack(spacing: 2) {
                ForEach(kinds, id: \.self) { kind in
                    Rectangle().fill(SleepFormat.color(kind))
                        .frame(width: max(2, (geo.size.width - gaps) * minutes(kind) / total))
                }
            }
            .clipShape(.capsule)
        }
        .accessibilityHidden(true)
    }

    private var totals: some View {
        Grid(alignment: .leading, horizontalSpacing: 8) {
            GridRow {
                ForEach(Self.order, id: \.self) { kind in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2).fill(SleepFormat.color(kind)).frame(width: 8, height: 8)
                            Text(SleepFormat.name(kind)).font(.caption).foregroundStyle(TetherBrand.sub)
                        }
                        Text(DayLine.duration(minutes(kind))).font(.subheadline.weight(.semibold)).monospacedDigit()
                        Text("\(share(kind))%").font(.caption).foregroundStyle(TetherBrand.sub).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func date(_ ts: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(ts)) }

    private var summary: String {
        let parts = Self.order.map { "\(SleepFormat.name($0)) \(DayLine.duration(minutes($0)))" }
        return "Sleep stages through the night: " + parts.joined(separator: ", ")
    }
}

struct NightVitalsCard: View {
    let night: NightSummary

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 14) {
            GridRow {
                Metric(label: "Resting HR", value: night.restingHR.map { "\($0) bpm" } ?? "–")
                Metric(label: "HRV", value: night.hrv.map { "\(Int($0.rounded())) ms" } ?? "–")
            }
            GridRow {
                Metric(label: "Breathing", value: night.respRate.map { String(format: "%.1f /min", $0) } ?? "–",
                       note: "from R-R")
                Metric(label: "Disturbances", value: night.disturbances.map(String.init) ?? "–")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct ChargeOrCountdown: View {
    let night: NightSummary
    let progress: BaselineProgress

    var body: some View {
        if let charge = night.charge {
            ChargeCard(charge: charge, drivers: night.drivers)
        } else {
            NotYet(title: progress.chargeLabel,
                   detail: "\(progress.scoredNights) of \(BaselineProgress.chargeNights) nights recorded. Charge compares each night with your own baseline, so it waits until it has one.")
                .card()
        }
    }
}

struct ChargeCard: View {
    let charge: Double
    let drivers: [NightSummary.Driver]

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ZStack {
                Circle().stroke(TetherBrand.track, lineWidth: 12)
                Circle().trim(from: 0, to: charge / 100)
                    .stroke(TetherBrand.charge(zone), style: .init(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(charge.rounded()))").font(.system(size: 34, weight: .bold)).monospacedDigit()
                    Text("Charge").font(.caption.weight(.semibold)).foregroundStyle(TetherBrand.sub)
                }
            }
            .frame(width: 112, height: 112)
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(TetherBrand.charge(zone)).frame(width: 8, height: 8)
                    Text(zone.name).font(.subheadline.weight(.semibold)).foregroundStyle(TetherBrand.charge(zone))
                    Spacer(minLength: 0)
                    DetailChevron()
                }
                .accessibilityElement(children: .combine)
                Text(zone.advice).font(.headline)
                ForEach(drivers.prefix(3)) { driver in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: driver.deltaPoints >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(driver.deltaPoints >= 0 ? TetherBrand.good : TetherBrand.headsUp)
                        Text("\(driver.label): \(driver.valueText)").font(.subheadline).foregroundStyle(TetherBrand.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .card()
    }

    private var zone: ChargeZone { ChargeZone(charge: charge) }
}

struct RecentNightsCard: View {
    let nights: [NightSummary]

    var body: some View {
        let recent = Array(nights.suffix(7))
        VStack(alignment: .leading, spacing: 12) {
            Text("Last \(recent.count) nights").font(.headline)
            Chart(recent) { night in
                BarMark(x: .value("Night", String(night.day.suffix(2))),
                        y: .value("Hours", (night.totalSleepMin ?? 0) / 60))
                    .foregroundStyle(TetherBrand.dusk)
                    .clipShape(.rect(cornerRadius: 3))
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(TetherBrand.track)
                    AxisValueLabel().foregroundStyle(TetherBrand.sub)
                }
            }
            .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(TetherBrand.sub) } }
            .frame(height: 110)
            .accessibilityLabel("Hours asleep for the last nights")
        }
        .card()
    }
}
