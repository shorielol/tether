import SwiftUI
import TetherCore

/// Tonight's plan: how much sleep you need and why, when to be in bed, and how last night measured up.
struct SleepCoachCard: View {
    @Environment(AppModel.self) private var model
    let coach: SleepCoach

    @State private var showsWhy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Tonight", systemImage: "moon.stars").font(.subheadline.weight(.semibold))
                    .foregroundStyle(TetherBrand.sub)
                Text("Bed by \(clock(coach.bedtimeMinute))").font(.title2.weight(.bold)).monospacedDigit()
                Text("Need \(DayLine.duration(coach.need.totalMin)) · wake \(clock(coach.wakeMinute))\(coach.wakeFromAlarm ? " (alarm)" : "")")
                    .font(.subheadline).foregroundStyle(TetherBrand.sub)
            }
            if let last = coach.lastNight {
                HStack(alignment: .top, spacing: 12) {
                    Metric(label: "Of your need", value: "\(Int((last.performance * 100).rounded()))%", note: nil)
                    Metric(label: "Deep + REM", value: DayLine.duration(last.restorativeMin), note: nil)
                    if let consistency = coach.consistency {
                        Metric(label: "Consistency", value: "\(consistency)", note: nil)
                    }
                }
            }
            Toggle(isOn: Binding(get: { model.bedtimeReminder }, set: { model.bedtimeReminder = $0 })) {
                Label("Remind me 30 min before", systemImage: "bell").font(.subheadline)
            }
            .tint(TetherBrand.ember)
            DisclosureGroup(isExpanded: $showsWhy) {
                VStack(spacing: 0) {
                    line("For your age", DayLine.duration(coach.need.baseMin))
                    if coach.need.debtMin > 0 { line("Catching up", "+" + DayLine.duration(coach.need.debtMin)) }
                    if coach.need.effortMin > 0 { line("After today's effort", "+" + DayLine.duration(coach.need.effortMin)) }
                }
                .padding(.top, 6)
            } label: {
                Text("Why \(DayLine.duration(coach.need.totalMin))").font(.subheadline).foregroundStyle(TetherBrand.text)
            }
            .tint(TetherBrand.sub)
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
