import Charts
import SwiftUI
import TetherCore

// MARK: - Live

struct LiveHeroCard: View {
    let today: TodaySnapshot
    let liveBPM: Int?

    var body: some View {
        let zone = liveBPM.map { TodayAnalytics.zone(bpm: $0, maxHR: today.maxHR) } ?? 0
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(liveBPM.map(String.init) ?? "–")
                    .font(.system(size: 64, weight: .bold)).monospacedDigit()
                    .contentTransition(.numericText())
                Text("bpm").font(.headline).foregroundStyle(TetherBrand.sub)
                Spacer()
                if let liveBPM {
                    ZoneChip(zone: zone, percent: Int(Double(liveBPM) / Double(today.maxHR) * 100))
                }
            }
            .animation(.smooth, value: liveBPM)
            Sparkline(points: Array(today.minuteSeries.suffix(10)))
                .frame(height: 44)
            HStack {
                Metric(label: "HRV now", value: today.hrvNow.map { "\(Int($0.rounded())) ms" } ?? "–",
                       note: "last 5 min")
                Spacer()
                Metric(label: "Max HR", value: "\(today.maxHR)", note: "from your age")
            }
        }
        .card()
    }
}

private struct ZoneChip: View {
    let zone: Int
    let percent: Int

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(zone == 0 ? "Resting" : "Zone \(zone) · \(TetherBrand.zoneNames[zone])")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(zone == 0 ? TetherBrand.sub : TetherBrand.zone(zone))
            Text("\(percent)% of max").font(.caption).foregroundStyle(TetherBrand.sub).monospacedDigit()
        }
    }
}

private struct Sparkline: View {
    let points: [TodaySnapshot.MinutePoint]

    var body: some View {
        Chart(points) { point in
            LineMark(x: .value("Time", Date(timeIntervalSince1970: TimeInterval(point.ts))),
                     y: .value("BPM", point.bpm), series: .value("Run", point.segment))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(TetherBrand.ember)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityLabel("Heart rate over the last 10 minutes")
    }
}

struct Metric: View {
    let label: String
    let value: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(TetherBrand.sub)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            if let note { Text(note).font(.caption2).foregroundStyle(TetherBrand.sub) }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Effort and calories

struct EffortCard: View {
    let today: TodaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Effort").font(.headline)
                Spacer(minLength: 0)
                DetailChevron()
            }
            ZStack {
                Circle().stroke(TetherBrand.track, lineWidth: 9)
                Circle()
                    .trim(from: 0, to: (today.effort ?? 0) / 100)
                    .stroke(TetherBrand.bone, style: .init(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(today.effort.map { String(format: "%.1f", $0) } ?? "…")
                    .font(.title2.bold()).monospacedDigit()
            }
            .frame(width: 86, height: 86)
            .frame(maxWidth: .infinity)
            Text(restingNote).font(.caption).foregroundStyle(TetherBrand.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Effort \(today.effort.map { String(format: "%.1f", $0) } ?? "building") out of 100")
    }

    private var restingNote: String {
        let source = switch today.restingSource {
        case .profile: "your profile"
        case .lowestFiveMinutes: "lowest 5 min today"
        case .defaultValue: "a default until you rest"
        }
        return "0–100 so far · resting \(today.restingHR) from \(source)"
    }
}

struct CaloriesCard: View {
    let today: TodaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calories").font(.headline)
            Spacer(minLength: 0)
            if let total = today.caloriesTotal {
                Text("\(total)").font(.system(size: 34, weight: .bold)).monospacedDigit()
                Text("kcal while recording").font(.caption).foregroundStyle(TetherBrand.sub)
                Text("\(today.caloriesActive ?? 0) active").font(.subheadline.weight(.semibold))
                    .foregroundStyle(TetherBrand.bone)
            } else {
                Text("Add your weight in the profile to estimate calories.")
                    .font(.caption).foregroundStyle(TetherBrand.sub)
            }
            Spacer(minLength: 0)
            Text("Estimate from heart rate").font(.caption2).foregroundStyle(TetherBrand.sub)
        }
        .card(padding: 14)
    }
}

// MARK: - Heart rate today

struct HeartRateDayCard: View {
    let today: TodaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Heart rate today").font(.headline)
                Spacer()
                Text("since \(start)").font(.caption).foregroundStyle(TetherBrand.sub)
                DetailChevron()
            }
            Chart(today.minuteSeries) { point in
                LineMark(x: .value("Time", Date(timeIntervalSince1970: TimeInterval(point.ts))),
                         y: .value("BPM", point.bpm), series: .value("Run", point.segment))
                    .interpolationMethod(.monotone)
                    .lineStyle(.init(lineWidth: 1.6))
                    .foregroundStyle(TetherBrand.ember)
            }
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                    AxisGridLine().foregroundStyle(TetherBrand.track)
                    AxisValueLabel(format: .dateTime.hour()).foregroundStyle(TetherBrand.sub)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(TetherBrand.track)
                    AxisValueLabel().foregroundStyle(TetherBrand.sub)
                }
            }
            .frame(height: 150)
            .accessibilityLabel("Heart rate chart for today")
            HStack {
                Metric(label: "Lowest", value: today.minBPM.map(String.init) ?? "–")
                Spacer()
                Metric(label: "Average", value: today.avgBPM.map(String.init) ?? "–")
                Spacer()
                Metric(label: "Highest", value: today.maxBPM.map(String.init) ?? "–")
            }
        }
        .card()
    }

    /// Fit the scale to the day so a hard effort isn't clipped and resting detail isn't flattened.
    private var yDomain: ClosedRange<Double> {
        let low = Double(today.minBPM ?? 40), high = Double(today.maxBPM ?? 120)
        return (low - 5)...(max(high, low + 20) + 5)
    }

    private var start: String {
        Date(timeIntervalSince1970: TimeInterval(today.window.lowerBound)).formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Zones

struct ZonesCard: View {
    let today: TodaySnapshot

    var body: some View {
        let total = max(1, today.zoneMinutes.reduce(0, +))
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Time in zones").font(.headline)
                Spacer()
                Text("\(today.zoneMinutes.reduce(0, +)) min above 50% of max")
                    .font(.caption).foregroundStyle(TetherBrand.sub).monospacedDigit()
                DetailChevron()
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { zone in
                        let minutes = today.zoneMinutes[zone - 1]
                        if minutes > 0 {
                            Rectangle().fill(TetherBrand.zone(zone))
                                .frame(width: max(3, geo.size.width * Double(minutes) / Double(total) - 2))
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 5))
            }
            .frame(height: 12)
            .background(TetherBrand.track, in: .rect(cornerRadius: 5))
            ForEach(1...5, id: \.self) { zone in
                HStack(spacing: 10) {
                    Circle().fill(TetherBrand.zone(zone)).frame(width: 8, height: 8)
                    Text("Zone \(zone) · \(TetherBrand.zoneNames[zone])").font(.subheadline)
                    Spacer()
                    Text("\(today.zoneMinutes[zone - 1]) min").font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }
}

// MARK: - Stress

struct StressCard: View {
    let today: TodaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Stress by hour").font(.headline)
                Spacer()
                Text(summary).font(.caption).foregroundStyle(TetherBrand.sub)
                DetailChevron()
            }
            if today.stressHours.isEmpty {
                Text("Needs about 5 minutes of steady heart rate in an hour to read it.")
                    .font(.subheadline).foregroundStyle(TetherBrand.sub)
            } else {
                HStack(spacing: 3) {
                    ForEach(today.stressHours) { hour in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color(hour))
                            .frame(height: 26)
                            .accessibilityLabel("\(hour.hour):00, \(label(hour))")
                    }
                }
                HStack {
                    Text(hourLabel(today.stressHours.first?.hour))
                    Spacer()
                    HStack(spacing: 10) {
                        legend(TetherBrand.dusk, "Calm")
                        legend(TetherBrand.ember, "High")
                        if today.stressHours.contains(where: \.wasActive) {
                            legend(TetherBrand.bone.opacity(0.5), "Active")
                        }
                    }
                    Spacer()
                    Text(hourLabel(today.stressHours.last?.hour))
                }
                .font(.caption2).foregroundStyle(TetherBrand.sub)
                Text("From heart rate and HRV against the rest of your day. Workouts also read as high here, because the heart-rate link carries no motion data.")
                    .font(.caption).foregroundStyle(TetherBrand.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }

    private var summary: String {
        let scored = today.stressHours.compactMap(\.level)
        guard let peak = today.stressHours.filter({ $0.level != nil }).max(by: { ($0.level ?? 0) < ($1.level ?? 0) }),
              !scored.isEmpty else { return "relative to your own day" }
        return "peak at \(hourLabel(peak.hour))"
    }

    private func color(_ hour: TodaySnapshot.StressHour) -> Color {
        if hour.wasActive { return TetherBrand.bone.opacity(0.5) }
        guard let level = hour.level else { return TetherBrand.track }
        let t = min(max(level / 3, 0), 1)
        return Color(red: (140 + (255 - 140) * t) / 255, green: (155 + (138 - 155) * t) / 255, blue: (255 + (76 - 255) * t) / 255)
    }

    private func label(_ hour: TodaySnapshot.StressHour) -> String {
        if hour.wasActive { return "active" }
        guard let level = hour.level else { return "not enough data" }
        return level < 1 ? "calm" : level < 2 ? "moderate" : "high"
    }

    private func hourLabel(_ hour: Int?) -> String {
        guard let hour else { return "" }
        return String(format: "%02d:00", hour)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(text)
        }
    }
}

// MARK: - Coverage

struct CoverageRow: View {
    let today: TodaySnapshot

    var body: some View {
        if let coverage = today.coverage {
            HStack(spacing: 12) {
                Image(systemName: coverage.fraction >= 0.95 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(coverage.fraction >= 0.95 ? TetherBrand.good : TetherBrand.headsUp)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Captured \(duration(coverage.capturedSeconds)) of \(duration(coverage.window.count))")
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                    Text(coverage.gaps.isEmpty ? "No gaps since recording began"
                         : "\(coverage.gaps.count) gap\(coverage.gaps.count == 1 ? "" : "s") · keep the phone within Bluetooth range")
                        .font(.caption).foregroundStyle(TetherBrand.sub)
                }
                Spacer()
                Text("\(Int((coverage.fraction * 100).rounded()))%").font(.headline).monospacedDigit()
            }
            .card(padding: 14)
            .accessibilityElement(children: .combine)
        }
    }

    private func duration(_ seconds: Int) -> String {
        let h = seconds / 3_600, m = (seconds % 3_600) / 60
        return h > 0 ? "\(h) h \(m) m" : "\(m) m"
    }
}

// MARK: - Baseline and last night

/// Charge and sleep need nights; until then they take one quiet row instead of the whole screen.
struct BaselineRow: View {
    let progress: BaselineProgress

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(TetherBrand.track, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: Double(progress.scoredNights) / Double(BaselineProgress.chargeNights))
                    .stroke(TetherBrand.ember, style: .init(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(progress.chargeLabel) · \(progress.scoredNights)/\(BaselineProgress.chargeNights)")
                    .font(.subheadline.weight(.semibold))
                Text("Sleep and Charge are scored each morning from the night before.")
                    .font(.caption).foregroundStyle(TetherBrand.sub)
            }
            Spacer(minLength: 0)
            DetailChevron()
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

struct LastNightRow: View {
    let night: NightSummary

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "moon.zzz.fill").foregroundStyle(TetherBrand.dusk)
                .frame(width: 34, height: 34)
                .background(TetherBrand.dusk.opacity(0.15), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text("Slept \(SleepFormat.duration(minutes: night.totalSleepMin))")
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                Text("\(SleepFormat.time(night.sleepStart)) – \(SleepFormat.time(night.sleepEnd)) · estimated from heart rate")
                    .font(.caption).foregroundStyle(TetherBrand.sub)
            }
            Spacer()
            if let hrv = night.hrv {
                Text("HRV \(Int(hrv.rounded()))").font(.subheadline.weight(.semibold)).monospacedDigit()
            }
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}
