import SwiftUI
import TetherSnapshot
import WidgetKit

/// One widget that changes with the day: Charge in the morning, the next thing on today's plan, bedtime for
/// the two hours before it, then the strap alarm. Its timeline holds an entry for every change, so it moves on
/// by itself; the app only reloads it when the plan changes.
struct NowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "tether.now", provider: NowProvider()) { entry in
            NowWidgetView(entry: entry)
                .containerBackground(for: .widget) { NowStyle.background }
                .widgetURL(URL(string: entry.link))
        }
        .configurationDisplayName("Now")
        .description("Charge in the morning, your plan through the day, bedtime in the evening.")
        .supportedFamilies([.accessoryRectangular, .systemSmall, .systemMedium])
    }
}

// MARK: - Timeline

struct NowEntry: TimelineEntry {
    let date: Date
    let plan: DayPlan?
    let morning: MorningSnapshot?
    let view: NowView
    let relevance: TimelineEntryRelevance?

    init(date: Date, plan: DayPlan?, morning: MorningSnapshot?) {
        self.date = date
        self.plan = plan
        let now = Int(date.timeIntervalSince1970)
        let fresh = morning.flatMap { $0.isFresh(at: date) ? $0 : nil }
        var view = NowView.at(now, plan: plan)
        // The app may not have been opened yet this morning; the background check's numbers still count.
        if view == .empty, fresh != nil, Calendar.current.component(.hour, from: date) < NowView.morningEndsHour {
            view = .morning
        }
        self.morning = fresh
        self.view = view
        relevance = switch view {
        case .morning: TimelineEntryRelevance(score: 0.9)
        case .evening: TimelineEntryRelevance(score: 1)
        case .night: TimelineEntryRelevance(score: 0.5)
        case .day: TimelineEntryRelevance(score: 0.3)
        case .empty: TimelineEntryRelevance(score: 0)
        }
    }

    var link: String {
        switch view {
        case .morning: "tether://today"
        case .evening, .night: "tether://sleep"
        case .day, .empty: "tether://today"
        }
    }

    var charge: Int? { plan?.chargePercent ?? morning?.charge.map { Int($0.rounded()) } }
    var sleepMin: Double? { plan?.sleepMin ?? morning?.sleepMin }
}

struct NowProvider: TimelineProvider {
    static let sample = DayPlan(day: WakeDay.key(for: .now), dayStart: Int(Calendar.current.startOfDay(for: .now).timeIntervalSince1970),
                                chargePercent: 76, zoneName: "Green", advice: "Ready for a harder day", sleepMin: 377,
                                targetLow: 55, targetHigh: 75, sharpest: 990...1095, dipMinute: 825, coffeeByMinute: 925,
                                napWindow: nil, energy: [40, 55, 66, 72, 74, 70, 62, 55, 52, 58, 66, 72, 74, 70, 62, 52, 40, 30, 22],
                                bedtimeAt: Int(Calendar.current.startOfDay(for: .now).timeIntervalSince1970) + 22 * 3_600 + 900,
                                needMin: 560, alarmAt: nil, alarmConfirmed: false)

    func placeholder(in context: Context) -> NowEntry { NowEntry(date: .now, plan: Self.sample, morning: nil) }

    func getSnapshot(in context: Context, completion: @escaping (NowEntry) -> Void) {
        let store = SnapshotStore.shared()
        let plan = store?.readPlan()
        completion(NowEntry(date: .now, plan: context.isPreview && plan == nil ? Self.sample : plan, morning: store?.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowEntry>) -> Void) {
        let store = SnapshotStore.shared()
        let plan = store?.readPlan(), morning = store?.read()
        let now = Date()
        let changes = NowView.changes(after: Int(now.timeIntervalSince1970), plan: plan).prefix(12)
            .map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let boundary = WakeDay.nextBoundary(after: now)
        let dates = [now] + changes + (changes.contains(boundary) ? [] : [boundary])
        let entries = dates.sorted().map { NowEntry(date: $0, plan: plan, morning: morning) }
        completion(Timeline(entries: entries, policy: .after(entries.last?.date ?? boundary)))
    }
}

// MARK: - Views

enum NowStyle {
    static let background = Color(red: 10 / 255, green: 12 / 255, blue: 16 / 255)
    static let sub = Color(red: 163 / 255, green: 169 / 255, blue: 181 / 255)
    static let ember = Color(red: 1, green: 138 / 255, blue: 76 / 255)

    static func zone(_ name: String?) -> Color {
        switch name {
        case "Green": Color(red: 127 / 255, green: 214 / 255, blue: 168 / 255)
        case "Yellow": Color(red: 242 / 255, green: 184 / 255, blue: 75 / 255)
        case "Red": Color(red: 1, green: 112 / 255, blue: 136 / 255)
        default: .white
        }
    }
}

/// The few words each moment needs: an icon, one headline, and up to two short lines.
struct NowContent {
    let icon: String
    let headline: Text
    let lines: [Text]
    let tint: Color

    init(entry: NowEntry) {
        let plan = entry.plan
        switch entry.view {
        case .morning:
            icon = "bolt.fill"
            tint = NowStyle.zone(plan?.zoneName ?? Self.zoneName(entry.charge))
            headline = Text(entry.charge.map { "\($0)%" } ?? "–") + Text(plan?.zoneName.map { "  \($0)" } ?? "")
            lines = [plan?.advice.map(Text.init) ?? Text("This morning's Charge"),
                     Text([entry.sleepMin.map { "Slept \(Self.duration($0))" }, Self.target(plan)].compactMap { $0 }.joined(separator: " · "))]
        case .day(let event):
            icon = event.map(Self.icon) ?? "figure.run"
            tint = event.map { Self.tint($0.kind) } ?? .white
            headline = event.map(Self.headline) ?? Text(Self.target(plan) ?? "Plan your day")
            lines = [event == nil ? nil : Self.target(plan).map(Text.init),
                     plan?.bedtimeAt.map { Text("Bed by ") + Text(Self.date($0), style: .time) }].compactMap { $0 }
        case .evening:
            icon = "bed.double.fill"
            tint = NowStyle.ember
            let bed = Self.date(plan?.bedtimeAt ?? 0)
            headline = Text("Bed in ") + Text(bed, style: .relative)
            lines = [Text(bed, style: .time) + Text(plan?.needMin.map { " · need \(Self.duration($0))" } ?? ""),
                     Self.alarmLine(plan)].compactMap { $0 }
        case .night:
            icon = "alarm.fill"
            tint = .white
            headline = plan?.alarmAt.map { Text(Self.date($0), style: .time) + Text(plan?.alarmConfirmed == true ? " ✓" : "") }
                ?? Text("No alarm set")
            lines = [Text(plan?.alarmAt == nil ? "Sleep well" : (plan?.alarmConfirmed == true ? "Set on your strap" : "Not on your strap yet")),
                     Text("Charge in the morning")]
        case .empty:
            icon = "circle.dotted"
            tint = NowStyle.sub
            headline = Text("Open Tether")
            lines = [Text("to plan today")]
        }
    }

    static func date(_ epoch: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(epoch)) }

    static func duration(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        return "\(total / 60)h \(String(format: "%02d", total % 60))m"
    }

    static func target(_ plan: DayPlan?) -> String? {
        guard let low = plan?.targetLow, let high = plan?.targetHigh else { return nil }
        return "Effort \(low)–\(high)"
    }

    static func zoneName(_ charge: Int?) -> String? {
        guard let charge else { return nil }
        return charge >= 67 ? "Green" : charge >= 34 ? "Yellow" : "Red"
    }

    static func alarmLine(_ plan: DayPlan?) -> Text? {
        guard let alarm = plan?.alarmAt else { return nil }
        return Text("Alarm ") + Text(date(alarm), style: .time) + Text(plan?.alarmConfirmed == true ? " ✓" : "")
    }

    static func icon(_ event: NowView.Event) -> String {
        switch event.kind {
        case .sharpestFrom, .sharpestTill: "bolt.fill"
        case .dip: "arrow.down.right"
        case .coffee: "cup.and.saucer.fill"
        case .napFrom, .napTill: "powersleep"
        }
    }

    static func tint(_ kind: NowView.Event.Kind) -> Color {
        switch kind {
        case .sharpestFrom, .sharpestTill: NowStyle.zone("Green")
        case .napFrom, .napTill: NowStyle.ember
        default: .white
        }
    }

    static func headline(_ event: NowView.Event) -> Text {
        let time = Text(date(event.at), style: .time)
        return switch event.kind {
        case .sharpestFrom: Text("Sharpest from ") + time
        case .sharpestTill: Text("Sharpest till ") + time
        case .dip: Text("Dip around ") + time
        case .coffee: Text("Last coffee by ") + time
        case .napFrom: Text("Nap window ") + time
        case .napTill: Text("Nap till ") + time
        }
    }
}

struct NowWidgetView: View {
    let entry: NowEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let content = NowContent(entry: entry)
        switch family {
        case .accessoryRectangular: rectangular(content)
        case .systemMedium: medium(content)
        default: small(content)
        }
    }

    private func rectangular(_ content: NowContent) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: content.icon).font(.caption.weight(.semibold))
                content.headline.font(.headline).lineLimit(1).minimumScaleFactor(0.7)
            }
            .widgetAccentable()
            ForEach(Array(content.lines.prefix(2).enumerated()), id: \.offset) { _, line in
                line.font(.caption).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func small(_ content: NowContent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: content.icon).font(.title3.weight(.semibold)).foregroundStyle(content.tint)
            Spacer(minLength: 0)
            content.headline.font(.title3.weight(.bold)).foregroundStyle(.white)
                .lineLimit(2).minimumScaleFactor(0.7)
            ForEach(Array(content.lines.prefix(2).enumerated()), id: \.offset) { _, line in
                line.font(.caption).foregroundStyle(NowStyle.sub).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ content: NowContent) -> some View {
        HStack(spacing: 16) {
            small(content)
            if let plan = entry.plan, plan.energy.count >= 2, case .day = entry.view {
                EnergyCurve(plan: plan, now: entry.date)
            } else {
                stats.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Outside the day: the three numbers that frame it.
    private var stats: some View {
        VStack(alignment: .leading, spacing: 8) {
            stat("bolt.fill", "Charge", entry.charge.map { "\($0)%" })
            stat("moon.fill", "Slept", entry.sleepMin.map(NowContent.duration))
            stat("bed.double.fill", "Bed", entry.plan?.bedtimeAt.map {
                NowContent.date($0).formatted(date: .omitted, time: .shortened)
            })
        }
    }

    private func stat(_ icon: String, _ label: String, _ value: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundStyle(NowStyle.sub).frame(width: 16)
            Text(label).font(.caption).foregroundStyle(NowStyle.sub)
            Spacer(minLength: 4)
            Text(value ?? "–").font(.subheadline.weight(.semibold)).foregroundStyle(.white).monospacedDigit()
        }
    }
}

/// Today's forecast alertness, 06:00 to midnight, with the sharpest window shaded and a dot for now.
struct EnergyCurve: View {
    let plan: DayPlan
    let now: Date

    var body: some View {
        GeometryReader { geo in
            let points = plan.energy.enumerated().map { index, level in
                CGPoint(x: geo.size.width * CGFloat(index) / CGFloat(plan.energy.count - 1),
                        y: geo.size.height * (1 - CGFloat(level) / 100))
            }
            ZStack(alignment: .topLeading) {
                if let sharp = plan.sharpest {
                    let x0 = x(sharp.lowerBound, geo.size.width), x1 = x(sharp.upperBound, geo.size.width)
                    Rectangle().fill(NowStyle.zone("Green").opacity(0.15))
                        .frame(width: max(2, x1 - x0)).offset(x: x0)
                }
                Path { path in path.addLines(points) }
                    .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                let nowX = x(Calendar.current.component(.hour, from: now) * 60 + Calendar.current.component(.minute, from: now), geo.size.width)
                if nowX >= 0, nowX <= geo.size.width {
                    Circle().fill(NowStyle.ember).frame(width: 8, height: 8)
                        .position(x: nowX, y: y(at: nowX, points: points))
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityLabel("Energy forecast for today")
    }

    /// Minutes after midnight to x, on a 06:00–24:00 axis.
    private func x(_ minute: Int, _ width: CGFloat) -> CGFloat { width * CGFloat(minute - 360) / CGFloat(18 * 60) }

    private func y(at x: CGFloat, points: [CGPoint]) -> CGFloat {
        guard let after = points.firstIndex(where: { $0.x >= x }), after > 0 else { return points.first?.y ?? 0 }
        let a = points[after - 1], b = points[after]
        let t = b.x == a.x ? 0 : (x - a.x) / (b.x - a.x)
        return a.y + (b.y - a.y) * t
    }
}

// MARK: - Previews

#Preview("Now", as: .systemMedium) { NowWidget() } timeline: {
    NowEntry(date: .now, plan: NowProvider.sample, morning: nil)
}
#Preview("Now", as: .accessoryRectangular) { NowWidget() } timeline: {
    NowEntry(date: .now, plan: NowProvider.sample, morning: nil)
}
