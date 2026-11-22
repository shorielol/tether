import SwiftUI
import TetherCore

/// Tonight's plan: how much sleep you need and why, when to be in bed, and how last night measured up.
struct SleepCoachCard: View {
    @Environment(AppModel.self) private var model
    let coach: SleepCoach

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tonight").font(.headline)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bed by \(clock(coach.bedtimeMinute))").font(.title2.weight(.bold)).monospacedDigit()
                    Text("to sleep \(DayLine.duration(coach.need.totalMin)) and wake at \(clock(coach.wakeMinute))\(coach.wakeFromAlarm ? " with your alarm" : ", your usual time")")
                        .font(.subheadline).foregroundStyle(TetherBrand.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(spacing: 0) {
                line("Recommended for your age", DayLine.duration(coach.need.baseMin))
                if coach.need.debtMin > 0 {
                    line(coach.need.owedMin > coach.need.debtMin
                         ? "Catching up (\(DayLine.duration(coach.need.owedMin)) owed, an hour a night)"
                         : "Catching up on short nights",
                         "+" + DayLine.duration(coach.need.debtMin))
                }
                if coach.need.effortMin > 0 { line("After today's effort", "+" + DayLine.duration(coach.need.effortMin)) }
            }
            if let last = coach.lastNight {
                Divider().overlay(TetherBrand.cardStroke)
                HStack(alignment: .top, spacing: 12) {
                    Metric(label: "Last night", value: "\(Int((last.performance * 100).rounded()))%", note: "of what you needed")
                    Metric(label: "Restorative", value: DayLine.duration(last.restorativeMin), note: "deep + REM")
                    if let consistency = coach.consistency {
                        Metric(label: "Consistency", value: "\(consistency)", note: "bed and wake times")
                    }
                }
            }
            Toggle(isOn: Binding(get: { model.bedtimeReminder }, set: { model.bedtimeReminder = $0 })) {
                Text("Remind me 30 min before").font(.subheadline)
            }
            .tint(TetherBrand.ember)
        }
        .card()
    }

    private func line(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(TetherBrand.sub)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private func clock(_ minute: Int) -> String {
        var parts = DateComponents()
        parts.hour = minute / 60
        parts.minute = minute % 60
        return (Calendar.current.date(from: parts) ?? .now).formatted(date: .omitted, time: .shortened)
    }
}
