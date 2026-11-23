import SwiftUI
import TetherCore
import TetherFiles

/// One day at a glance, as in the approved mockup: one hero number with three metrics beside it,
/// the day ribbon, then stress by hour and last night in two quiet panels.
struct DayView: View {
    @Environment(MacModel.self) private var model
    var openSleep: () -> Void

    var body: some View {
        let record = model.selectedRecord
        let minutes = model.dayMinutes
        if record == nil && minutes.isEmpty {
            ContentUnavailableView {
                Label(model.isShowingToday ? "Nothing from today yet" : "No file for this day", systemImage: "calendar")
            } description: {
                Text(model.isShowingToday
                     ? "Your iPhone saves today's file every 15 minutes while Tether is open. This Mac adds the hours it records."
                     : "Your iPhone didn't save a file for this day.")
            }
            .frame(maxWidth: .infinity, minHeight: 420)
        } else {
            heroRow(record)
            ribbon(record, minutes: minutes)
            HStack(alignment: .top, spacing: Space.xl) {
                Panel { StressStrip(hours: record?.today?.stressHours ?? []) }
                Panel { LastNightSummary(night: record?.night, openSleep: openSleep) }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Hero row

    private func heroRow(_ record: DayRecord?) -> some View {
        let hero = heroNumber(record)
        let metrics = metricRow(record)
        return VStack(alignment: .leading, spacing: Space.s) {
            ViewThatFits(in: .horizontal) {
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
            if let note = freshnessNote(record) {
                Label(note, systemImage: "iphone").font(.captionText).foregroundStyle(.secondary)
            }
        }
    }

    /// Charge leads once it exists. Before that, Effort takes the hero spot.
    @ViewBuilder private func heroNumber(_ record: DayRecord?) -> some View {
        if let charge = record?.night?.charge {
            let zone = ChargeZone(charge: charge)
            HeroNumber(label: "Charge", value: "\(Int(charge.rounded()))%",
                       caption: "\(zone.name) · \(zone.advice)", tint: Theme.charge(zone))
        } else {
            HeroNumber(label: "Effort", value: record?.today?.effort.map { "\(Int($0.rounded()))" } ?? "0",
                       caption: effortCaption(record?.today))
        }
    }

    private func metricRow(_ record: DayRecord?) -> some View {
        let today = record?.today
        let night = record?.night
        return HStack(alignment: .top, spacing: Space.section - 8) {
            if night?.charge != nil {
                MetricView(label: "Effort", value: today?.effort.map { "\(Int($0.rounded()))" } ?? "0",
                           caption: effortCaption(today))
            } else {
                MetricView(label: "Charge", value: "\(model.baseline.scoredNights)/\(BaselineProgress.chargeNights)",
                           caption: "nights to learn your normal")
            }
            MetricView(label: "Calories", value: today?.caloriesTotal.map { $0.formatted() } ?? "—",
                       caption: today?.caloriesActive.map { "\($0.formatted()) active" })
            sleepMetric(night)
        }
    }

    private func sleepMetric(_ night: NightSummary?) -> MetricView {
        guard let minutes = night?.totalSleepMin else {
            return MetricView(label: "Sleep", value: "—", caption: "scored the morning after")
        }
        let total = Int(minutes.rounded())
        return MetricView(label: "Sleep", value: "\(total / 60):\(String(format: "%02d", total % 60))", unit: "h",
                          caption: night?.efficiency.map { "\(Int(($0 * 100).rounded()))% efficient" })
    }

    private func effortCaption(_ today: TodaySnapshot?) -> String? {
        guard let today else { return nil }
        let above = today.zoneMinutes.dropFirst().reduce(0, +)
        return above > 0 ? "\(above) min above easy" : "builds as your heart rate rises"
    }

    /// Today's scores come from the iPhone. While this Mac fills in the hours, say how old they are.
    private func freshnessNote(_ record: DayRecord?) -> String? {
        guard model.isShowingToday, let record, !model.macMinutes.isEmpty else { return nil }
        let saved = Date(timeIntervalSince1970: TimeInterval(record.savedAt))
        guard Date().timeIntervalSince(saved) > 20 * 60 else { return nil }
        return "Scores as of \(saved.formatted(date: .omitted, time: .shortened)) on your iPhone. They catch up when it's back."
    }

    // MARK: Ribbon

    private func ribbon(_ record: DayRecord?, minutes: [TodaySnapshot.MinutePoint]) -> some View {
        let sleep = sleepWindow(record?.night)
        let macSpans = model.dayMacSpans
        return VStack(alignment: .leading, spacing: Space.l) {
            SectionHeader(title: "Heart rate") {
                DayLegend(showSleep: sleep != nil, showMac: !macSpans.isEmpty)
            }
            DayRibbon(dayStart: model.selectedStart, minutes: minutes,
                      maxHR: record?.today?.maxHR ?? model.phoneProfile?.profile.maxHR ?? 190,
                      sleep: sleep, macSpans: macSpans)
            if let coverage = record?.today?.coverage {
                Text(coverageText(coverage)).font(.captionText).foregroundStyle(.secondary)
            }
        }
    }

    private func sleepWindow(_ night: NightSummary?) -> ClosedRange<Int>? {
        guard let start = night?.sleepStart, let end = night?.sleepEnd, start < end else { return nil }
        return start...end
    }

    private func coverageText(_ coverage: CoverageReport) -> String {
        let style = Duration.UnitsFormatStyle(allowedUnits: [.hours, .minutes], width: .narrow)
        let captured = Duration.seconds(coverage.capturedSeconds).formatted(style)
        let window = Duration.seconds(coverage.window.count).formatted(style)
        let gaps = coverage.gaps.count
        return "Captured \(captured) of \(window)" + (gaps > 0 ? " · \(gaps) gap\(gaps == 1 ? "" : "s")" : "")
    }
}

/// Waking hours as short bars: taller is more stressed. Hours without enough data show as dots.
struct StressStrip: View {
    let hours: [TodaySnapshot.StressHour]

    var body: some View {
        SectionHeader(title: "Stress by hour") { Text(peakText) }
        if hours.isEmpty {
            Text("Needs a few waking hours of heart rate.").font(.bodyText).foregroundStyle(.secondary)
        } else {
            VStack(spacing: Space.s) {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(hours, id: \.hour) { hour in
                        bar(hour).frame(maxWidth: .infinity).help(helpText(hour))
                    }
                }
                .frame(height: 56, alignment: .bottom)
                HStack {
                    ForEach(axisHours, id: \.self) { hour in
                        Text(hourLabel(hour))
                        if hour != axisHours.last { Spacer() }
                    }
                }
                .font(.captionText).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Stress by hour. \(peakText)")
        }
    }

    private var axisHours: [Int] {
        guard let first = hours.first?.hour, let last = hours.last?.hour else { return [] }
        return [first, (first + last) / 2, last]
    }

    @ViewBuilder private func bar(_ hour: TodaySnapshot.StressHour) -> some View {
        if let level = hour.level {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.primary.opacity(hour.wasActive ? 0.25 : 0.5))
                .frame(height: 6 + 50 * min(max(level / 3, 0), 1))
        } else {
            Circle().fill(Theme.grid).frame(width: 3, height: 3)
        }
    }

    private var peakText: String {
        guard let peak = hours.filter({ $0.level != nil }).max(by: { ($0.level ?? 0) < ($1.level ?? 0) }) else { return "" }
        return "Highest around \(hourLabel(peak.hour))"
    }

    private func helpText(_ hour: TodaySnapshot.StressHour) -> String {
        guard let level = hour.level else { return "\(hourLabel(hour.hour)): not enough data" }
        let word = level < 1 ? "calm" : level < 2 ? "moderate" : "high"
        return "\(hourLabel(hour.hour)): \(word)" + (hour.wasActive ? ", moving" : "")
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(from: DateComponents(hour: hour)) ?? .now
        return date.formatted(.dateTime.hour())
    }
}

/// The night that ended on this day, with a way into the Sleep page.
struct LastNightSummary: View {
    let night: NightSummary?
    var openSleep: () -> Void

    var body: some View {
        SectionHeader(title: "Last night") {
            if night?.sleepStart != nil {
                Button("Open Sleep ›", action: openSleep)
                    .buttonStyle(.plain).foregroundStyle(Theme.ember).font(.bodyText)
            }
        }
        if let night, let start = night.sleepStart, let end = night.sleepEnd {
            Text("\(time(start)) – \(time(end))").font(.system(size: 20, weight: .semibold)).monospacedDigit()
            VStack(alignment: .leading, spacing: Space.xs) {
                if let line = sleepLine(night) { Text(line).font(.bodyText) }
                Text(vitals(night)).font(.bodyText).foregroundStyle(.secondary).lineLimit(1)
            }
        } else {
            Text("Tonight's sleep is scored the morning after.").font(.bodyText).foregroundStyle(.secondary)
        }
    }

    private func time(_ ts: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(ts)).formatted(date: .omitted, time: .shortened)
    }

    private func sleepLine(_ night: NightSummary) -> String? {
        guard let minutes = night.totalSleepMin else { return nil }
        let total = Int(minutes.rounded())
        var line = "\(total / 60) h \(total % 60) m asleep"
        if let efficiency = night.efficiency { line += " · \(Int((efficiency * 100).rounded()))% efficient" }
        return line
    }

    private func vitals(_ night: NightSummary) -> String {
        var parts: [String] = []
        if let resting = night.restingHR { parts.append("Resting \(resting) bpm") }
        if let hrv = night.hrv { parts.append("HRV \(Int(hrv.rounded())) ms") }
        if let resp = night.respRate { parts.append(String(format: "%.1f breaths a minute", resp)) }
        return parts.isEmpty ? "Vitals need a longer night" : parts.joined(separator: " · ")
    }
}
