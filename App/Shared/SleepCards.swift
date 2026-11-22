import Charts
import SwiftUI
import TetherCore

enum SleepFormat {
    static func duration(minutes: Double?) -> String {
        guard let minutes else { return "–" }
        let total = Int(minutes.rounded())
        return "\(total / 60) h \(String(format: "%02d", total % 60)) m"
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

struct HypnogramCard: View {
    let night: NightSummary
    private let order: [NightSummary.Stage.Kind] = [.wake, .rem, .light, .deep]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Stages").font(.headline)
                Spacer()
                Text("estimated from heart rate").font(.caption).foregroundStyle(TetherBrand.sub)
            }
            Chart(night.stages) { stage in
                RectangleMark(xStart: .value("Start", Date(timeIntervalSince1970: TimeInterval(stage.start))),
                              xEnd: .value("End", Date(timeIntervalSince1970: TimeInterval(stage.end))),
                              y: .value("Stage", SleepFormat.name(stage.kind)), height: 14)
                    .foregroundStyle(SleepFormat.color(stage.kind))
                    .clipShape(.rect(cornerRadius: 3))
            }
            .chartYScale(domain: order.map(SleepFormat.name))
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.hour()).foregroundStyle(TetherBrand.sub)
                }
            }
            .chartYAxis {
                AxisMarks { _ in AxisValueLabel().foregroundStyle(TetherBrand.sub) }
            }
            .frame(height: 150)
            .accessibilityLabel("Sleep stages through the night")
            HStack {
                ForEach([NightSummary.Stage.Kind.deep, .rem, .light], id: \.self) { kind in
                    stageTotal(kind)
                    if kind != .light { Spacer() }
                }
            }
        }
        .card()
    }

    private func stageTotal(_ kind: NightSummary.Stage.Kind) -> some View {
        let minutes: Double? = switch kind {
        case .deep: night.deepMin
        case .rem: night.remMin
        case .light: night.lightMin
        case .wake: nil
        }
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(SleepFormat.color(kind)).frame(width: 8, height: 8)
                Text(SleepFormat.name(kind)).font(.caption).foregroundStyle(TetherBrand.sub)
            }
            Text(SleepFormat.duration(minutes: minutes)).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
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
