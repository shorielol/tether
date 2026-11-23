import SwiftUI
import TetherCore

/// The strap's silent alarm: on or off, the time, and what the strap said. Only claims "set" once the
/// strap has confirmed it.
struct AlarmCard: View {
    let alarm: AlarmKeeper

    private static let defaultHour = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: isOn) {
                Label("Silent alarm", systemImage: "alarm").font(.headline)
            }
            .tint(TetherBrand.ember)
            if alarm.setting?.isOn == true {
                DatePicker("Wake at", selection: wakeTime, displayedComponents: .hourAndMinute)
                    .font(.subheadline)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Smart window").font(.subheadline)
                    Picker("Smart window", selection: window) {
                        ForEach(SmartWake.windowChoices, id: \.self) { minutes in
                            Text(minutes == 0 ? "Off" : "\(minutes) min").tag(minutes)
                        }
                    }
                    .pickerStyle(.segmented)
                    if (alarm.setting?.windowMinutes ?? 0) > 0 {
                        Text("Buzzes early if you're surfacing from deep sleep. Needs your phone nearby.")
                            .font(.footnote).foregroundStyle(TetherBrand.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            statusLine
            if case .refused = alarm.status, let setting = alarm.setting {
                Button("Try again") { alarm.set(hour: setting.hour, minute: setting.minute) }
                    .buttonStyle(.bordered)
            }
            Text("Keep a phone alarm too for the first few mornings.")
                .font(.footnote).foregroundStyle(TetherBrand.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    @ViewBuilder private var statusLine: some View {
        switch alarm.status {
        case .off:
            note("Buzzes you awake, silently.")
        case .waitingForStrap:
            note("Goes to your strap when it next connects.")
        case .sending:
            note("Sent to your strap, waiting for it to confirm.")
        case .set(let wake) where alarm.wokeEarly:
            Label("Moved to \(describe(wake)): you were surfacing, so your strap buzzes then.",
                  systemImage: "sparkles")
                .font(.subheadline).foregroundStyle(TetherBrand.good)
                .fixedSize(horizontal: false, vertical: true)
        case .set(let wake):
            Label("Set on your strap for \(describe(wake)). It buzzes even if your phone is away.",
                  systemImage: "checkmark.circle.fill")
                .font(.subheadline).foregroundStyle(TetherBrand.good)
                .fixedSize(horizontal: false, vertical: true)
        case .refused:
            Text("Your strap didn't accept the alarm, so it's off.")
                .font(.subheadline).foregroundStyle(TetherBrand.headsUp)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(TetherBrand.sub).fixedSize(horizontal: false, vertical: true)
    }

    private func describe(_ wake: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(wake))
        let time = date.formatted(date: .omitted, time: .shortened)
        return Calendar.current.isDateInToday(date) ? "\(time) today" : "\(time) tomorrow"
    }

    private var isOn: Binding<Bool> {
        Binding(
            get: { alarm.setting?.isOn == true },
            set: { on in
                if on {
                    alarm.set(hour: alarm.setting?.hour ?? Self.defaultHour, minute: alarm.setting?.minute ?? 0)
                } else {
                    alarm.turnOff()
                }
            })
    }

    private var window: Binding<Int> {
        Binding(get: { alarm.setting?.windowMinutes ?? 0 }, set: { alarm.setWindow($0) })
    }

    private var wakeTime: Binding<Date> {
        Binding(
            get: {
                var parts = DateComponents()
                parts.hour = alarm.setting?.hour ?? Self.defaultHour
                parts.minute = alarm.setting?.minute ?? 0
                return Calendar.current.date(from: parts) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                alarm.set(hour: parts.hour ?? Self.defaultHour, minute: parts.minute ?? 0)
            })
    }
}
