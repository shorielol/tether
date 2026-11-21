import SwiftUI
import WidgetKit

@main
struct TetherWidgetBundle: WidgetBundle {
    var body: some Widget {
        SpikeWidget()
    }
}

/// Signing spike only: proves the free team can sign a widget extension with an App Group.
struct SpikeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "spike", provider: SpikeProvider()) { _ in
            Text("T")
        }
        .supportedFamilies([.accessoryCircular])
    }
}

struct SpikeEntry: TimelineEntry { let date: Date }

struct SpikeProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpikeEntry { SpikeEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (SpikeEntry) -> Void) { completion(SpikeEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SpikeEntry>) -> Void) {
        completion(Timeline(entries: [SpikeEntry(date: .now)], policy: .never))
    }
}
