import SwiftUI
import TetherSnapshot
import WidgetKit

/// The Now widget, the Charge ring for under the clock, and the recording card. They show this morning's numbers once the phone
/// has seen the night end (AppModel.morningPass), and dashes from 04:00 until the next night is scored.
@main
struct TetherWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowWidget()
        ChargeWidget()
        RecordingLiveActivity()
    }
}

// MARK: - Timeline

struct MorningEntry: TimelineEntry {
    let date: Date
    let snapshot: MorningSnapshot?

    /// The snapshot only while it belongs to this wake day; yesterday's numbers never show as today's.
    var fresh: MorningSnapshot? {
        guard let snapshot, snapshot.isFresh(at: date) else { return nil }
        return snapshot
    }
}

struct MorningProvider: TimelineProvider {
    static let sample = MorningSnapshot(wakeDay: WakeDay.key(for: .now), savedAt: 0, sleepMin: 437, rest: 81,
                                        charge: 67, baselineNights: 6, restingHR: 52)

    func placeholder(in context: Context) -> MorningEntry {
        MorningEntry(date: .now, snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (MorningEntry) -> Void) {
        let stored = SnapshotStore.shared()?.read()
        completion(MorningEntry(date: .now, snapshot: context.isPreview && stored == nil ? Self.sample : stored))
    }

    /// Now, then dashes at the next 04:00. The app reloads the timeline when it publishes a new morning.
    func getTimeline(in context: Context, completion: @escaping (Timeline<MorningEntry>) -> Void) {
        let now = Date()
        let stored = SnapshotStore.shared()?.read()
        let boundary = WakeDay.nextBoundary(after: now)
        let entries = [MorningEntry(date: now, snapshot: stored), MorningEntry(date: boundary, snapshot: stored)]
        completion(Timeline(entries: entries, policy: .after(boundary)))
    }
}

// MARK: - Widgets

struct ChargeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "tether.charge", provider: MorningProvider()) { entry in
            ChargeView(snapshot: entry.fresh)
                .containerBackground(for: .widget) {}
                .widgetURL(URL(string: "tether://today"))
        }
        .configurationDisplayName("Charge")
        .description("This morning's Charge, once you're up.")
        .supportedFamilies([.accessoryCircular])
    }
}

// MARK: - Views

private let dash = "–"

struct ChargeView: View {
    let snapshot: MorningSnapshot?

    var body: some View {
        if let snapshot, let charge = snapshot.charge {
            ring(value: charge / 100, centre: "\(Int(charge.rounded()))")
        } else if let snapshot {
            // Baseline still filling: show how many of the 4 nights are in.
            let needed = MorningSnapshot.chargeNightsNeeded
            ring(value: snapshot.chargeProgress, centre: "\(min(snapshot.baselineNights, needed))/\(needed)", small: true)
        } else {
            ring(value: 0, centre: dash)
        }
    }

    private func ring(value: Double, centre: String, small: Bool = false) -> some View {
        Gauge(value: value) {
            Image(systemName: "bolt.fill")
        } currentValueLabel: {
            Text(centre).font(small ? .caption : .title3).fontWeight(.semibold).monospacedDigit()
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }
}

// MARK: - Previews

private let previewEntries: [MorningEntry] = [
    MorningEntry(date: .now, snapshot: MorningProvider.sample),
    MorningEntry(date: .now, snapshot: MorningSnapshot(wakeDay: WakeDay.key(for: .now), savedAt: 0, sleepMin: 402,
                                                       rest: 70, charge: nil, baselineNights: 2, restingHR: 55)),
    MorningEntry(date: .now, snapshot: nil),
]

#Preview("Charge", as: .accessoryCircular) { ChargeWidget() } timeline: { for e in previewEntries { e } }
