import SwiftUI
import TetherSnapshot
import WidgetKit

/// Skin temp from this morning, and tonight's plan: sleep need with bedtime, and the strap's alarm.

// MARK: - Tonight timeline

struct TonightEntry: TimelineEntry {
    let date: Date
    let tonight: TonightSnapshot?
}

struct TonightProvider: TimelineProvider {
    static let sample = TonightSnapshot(savedAt: 0, needMin: 560, bedtimeMinute: 22 * 60 + 15,
                                        alarmMinute: 7 * 60, alarmConfirmed: true)

    func placeholder(in context: Context) -> TonightEntry { TonightEntry(date: .now, tonight: Self.sample) }

    func getSnapshot(in context: Context, completion: @escaping (TonightEntry) -> Void) {
        let stored = SnapshotStore.shared()?.readTonight()
        completion(TonightEntry(date: .now, tonight: context.isPreview && stored == nil ? Self.sample : stored))
    }

    /// The app reloads these when the need, bedtime or alarm moves.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TonightEntry>) -> Void) {
        completion(Timeline(entries: [TonightEntry(date: .now, tonight: SnapshotStore.shared()?.readTonight())],
                            policy: .never))
    }
}

/// Minutes after midnight as a time today, so it formats in the phone's own 12- or 24-hour style.
private func timeOfDay(_ minute: Int) -> Date {
    Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(((minute % 1_440) + 1_440) % 1_440 * 60))
}

private func hoursMinutes(_ minutes: Double) -> String {
    let total = Int(minutes.rounded())
    return "\(total / 60)h \(String(format: "%02d", total % 60))m"
}

// MARK: - Widgets

struct SkinTempWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "tether.skinTemp", provider: MorningProvider()) { entry in
            SkinTempView(delta: entry.fresh?.skinTempDevC)
                .containerBackground(for: .widget) {}
                .widgetURL(URL(string: "tether://health"))
        }
        .configurationDisplayName("Skin temperature")
        .description("Last night's skin temperature against your normal.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct TonightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "tether.tonight", provider: TonightProvider()) { entry in
            TonightView(tonight: entry.tonight)
                .containerBackground(for: .widget) {}
                .widgetURL(URL(string: "tether://sleep"))
        }
        .configurationDisplayName("Tonight")
        .description("When to be in bed, how much sleep you need, and your strap's alarm.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct AlarmWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "tether.alarm", provider: TonightProvider()) { entry in
            AlarmView(tonight: entry.tonight)
                .containerBackground(for: .widget) {}
                .widgetURL(URL(string: "tether://strap"))
        }
        .configurationDisplayName("Strap alarm")
        .description("The silent alarm on your strap, once the strap has confirmed it.")
        .supportedFamilies([.accessoryCircular])
    }
}

// MARK: - Views

struct SkinTempView: View {
    let delta: Double?

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "thermometer.medium").font(.caption2).widgetAccentable()
                Text(delta.map(MorningSnapshot.signedDelta) ?? "–")
                    .font(.headline).fontWeight(.semibold).monospacedDigit()
                    .minimumScaleFactor(0.7)
                Text("vs normal").font(.system(size: 8)).opacity(0.7)
            }
        }
        .accessibilityLabel(delta.map { "Skin temperature \(MorningSnapshot.signedDelta($0)) against your normal" }
                            ?? "Skin temperature not measured yet")
    }
}

struct TonightView: View {
    let tonight: TonightSnapshot?

    var body: some View {
        if let tonight {
            VStack(alignment: .leading, spacing: 1) {
                Label { Text("Bed by ") + Text(timeOfDay(tonight.bedtimeMinute), style: .time) } icon: {
                    Image(systemName: "bed.double.fill")
                }
                .font(.headline).widgetAccentable()
                Text("Sleep need \(hoursMinutes(tonight.needMin))").font(.caption)
                alarmLine(tonight).font(.caption).opacity(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Open Tether to plan tonight").font(.caption)
        }
    }

    private func alarmLine(_ tonight: TonightSnapshot) -> Text {
        guard let minute = tonight.alarmMinute else { return Text("Strap alarm off") }
        return Text("Alarm ") + Text(timeOfDay(minute), style: .time) + Text(tonight.alarmConfirmed ? " ✓" : " · not on strap yet")
    }
}

struct AlarmView: View {
    let tonight: TonightSnapshot?

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: tonight?.alarmMinute == nil ? "alarm" : "alarm.fill").font(.caption2).widgetAccentable()
                if let minute = tonight?.alarmMinute {
                    Text(timeOfDay(minute), style: .time)
                        .font(.caption).fontWeight(.semibold).monospacedDigit().minimumScaleFactor(0.6)
                    Text(tonight?.alarmConfirmed == true ? "on strap" : "waiting").font(.system(size: 8)).opacity(0.7)
                } else {
                    Text("Off").font(.callout).fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Skin temp", as: .accessoryCircular) { SkinTempWidget() } timeline: {
    MorningEntry(date: .now, snapshot: MorningSnapshot(wakeDay: WakeDay.key(for: .now), savedAt: 0, sleepMin: 420, rest: 80,
                                                       charge: 60, baselineNights: 5, restingHR: 50, skinTempDevC: 0.3))
}
#Preview("Tonight", as: .accessoryRectangular) { TonightWidget() } timeline: { TonightEntry(date: .now, tonight: TonightProvider.sample) }
#Preview("Alarm", as: .accessoryCircular) { AlarmWidget() } timeline: { TonightEntry(date: .now, tonight: TonightProvider.sample) }
