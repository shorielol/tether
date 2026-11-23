import Charts
import SwiftUI
import TetherCore

/// The whole day in one strip: minute heart rate across 24 hours, sleep shaded and this Mac's
/// hours hatched behind it, and a thin zone strip under the plot. Labels live in the section
/// header's legend, so nothing sits inside the chart except the data and the hover readout.
struct DayRibbon: View {
    let dayStart: Int
    let minutes: [TodaySnapshot.MinutePoint]
    let maxHR: Int
    let sleep: ClosedRange<Int>?
    let macSpans: [ClosedRange<Int>]
    var height: CGFloat = 240

    @State private var hovered: TodaySnapshot.MinutePoint?
    /// Where the plot sits inside the chart, so the zone strip lines up with it exactly.
    @State private var plot: CGRect = .zero

    private var dayRange: ClosedRange<Date> { date(dayStart)...date(dayStart + 86_400) }
    private var yDomain: ClosedRange<Double> {
        let values = minutes.map(\.bpm)
        let low = max(30, ((values.min() ?? 50) - 10).rounded(.down))
        let high = max(low + 60, ((values.max() ?? 120) + 10).rounded(.up))
        return low...high
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            chart.frame(height: height)
            zoneStrip
                .frame(width: max(plot.width, 0), height: 6)
                .padding(.leading, plot.minX)
        }
    }

    // MARK: Chart

    private var chart: some View {
        Chart {
            if let sleep = clamped(sleep) {
                RectangleMark(xStart: .value("Asleep from", date(sleep.lowerBound)),
                              xEnd: .value("Asleep to", date(sleep.upperBound)))
                    .foregroundStyle(Theme.sleepBand)
            }
            ForEach(minutes, id: \.ts) { point in
                LineMark(x: .value("Time", date(point.ts)), y: .value("Heart rate", point.bpm),
                         series: .value("Stretch", point.segment))
                    .foregroundStyle(Theme.ember)
                    .lineStyle(StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
            }
            if let hovered {
                RuleMark(x: .value("Time", date(hovered.ts)))
                    .foregroundStyle(Color.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Time", date(hovered.ts)), y: .value("Heart rate", hovered.bpm))
                    .foregroundStyle(Theme.ember)
                    .symbolSize(50)
                    // Beside the point, never on it: right of it in the morning, left of it later on.
                    .annotation(position: hovered.ts < dayStart + 14 * 3_600 ? .trailing : .leading,
                                alignment: .center, spacing: 12,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        tooltip(for: hovered)
                    }
            }
        }
        .chartXScale(domain: dayRange)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisValueLabel(format: .dateTime.hour(), verticalSpacing: 18)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Theme.grid)
                AxisValueLabel()
            }
        }
        .chartBackground { proxy in
            GeometryReader { geo in
                if let frame = proxy.plotFrame.map({ geo[$0] }) {
                    MacHatch(spans: macSpans.compactMap(clamped).compactMap { span in
                        guard let start = proxy.position(forX: date(span.lowerBound)),
                              let end = proxy.position(forX: date(span.upperBound)) else { return nil }
                        return (start + frame.minX)...(end + frame.minX)
                    })
                    .frame(width: geo.size.width, height: frame.height)
                    .offset(y: frame.minY)
                    .onAppear { plot = frame }
                    .onChange(of: frame) { _, new in plot = new }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let frame = proxy.plotFrame else { return }
                            guard let when: Date = proxy.value(atX: location.x - geo[frame].origin.x) else { return }
                            hovered = nearest(to: Int(when.timeIntervalSince1970))
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
        .accessibilityLabel(accessibilitySummary)
    }

    private func tooltip(for point: TodaySnapshot.MinutePoint) -> some View {
        let zone = TodayAnalytics.zone(bpm: Int(point.bpm.rounded()), maxHR: maxHR)
        return VStack(alignment: .leading, spacing: 1) {
            Text(date(point.ts), format: .dateTime.hour().minute()).font(.captionText).foregroundStyle(.secondary)
            Text("\(Int(point.bpm.rounded())) bpm").font(.bodyText.weight(.semibold)).monospacedDigit()
            if zone > 0 {
                Text("Zone \(zone) · \(Theme.zoneNames[zone])").font(.captionText).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.regularMaterial, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline))
    }

    // MARK: Zone strip

    private var zoneStrip: some View {
        Canvas { context, size in
            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 2), with: .color(Theme.grid))
            let width = max(1, size.width / 1_440)
            for point in minutes {
                let zone = TodayAnalytics.zone(bpm: Int(point.bpm.rounded()), maxHR: maxHR)
                guard zone > 0 else { continue }
                let x = CGFloat(Double(point.ts - dayStart) / 86_400) * size.width
                context.fill(Path(CGRect(x: x, y: 0, width: width + 0.5, height: size.height)), with: .color(Theme.zone(zone)))
            }
        }
        .clipShape(.rect(cornerRadius: 2))
        .accessibilityHidden(true)
    }

    // MARK: Helpers

    /// Spans that start the evening before (sleep) or run past midnight stop at the day's edges,
    /// so nothing draws outside the plot.
    private func clamped(_ span: ClosedRange<Int>?) -> ClosedRange<Int>? {
        guard let span else { return nil }
        let start = max(span.lowerBound, dayStart), end = min(span.upperBound, dayStart + 86_400)
        return start < end ? start...end : nil
    }

    private func date(_ ts: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(ts)) }

    private func nearest(to ts: Int) -> TodaySnapshot.MinutePoint? {
        guard let closest = minutes.min(by: { abs($0.ts - ts) < abs($1.ts - ts) }), abs(closest.ts - ts) <= 180 else {
            return nil
        }
        return closest
    }

    private var accessibilitySummary: String {
        guard let low = minutes.map(\.bpm).min(), let high = minutes.map(\.bpm).max() else {
            return "Heart rate: no samples for this day"
        }
        return "Heart rate across the day, from \(Int(low)) to \(Int(high)) beats per minute"
    }
}

/// Diagonal hatching for the hours this Mac recorded: a texture, so it never relies on colour alone.
struct MacHatch: View {
    let spans: [ClosedRange<CGFloat>]

    var body: some View {
        Canvas { context, size in
            for span in spans {
                let rect = CGRect(x: span.lowerBound, y: 0, width: span.upperBound - span.lowerBound, height: size.height)
                context.drawLayer { layer in
                    layer.clip(to: Path(rect))
                    var lines = Path()
                    var x = rect.minX - size.height
                    while x < rect.maxX {
                        lines.move(to: CGPoint(x: x, y: size.height))
                        lines.addLine(to: CGPoint(x: x + size.height, y: 0))
                        x += 6
                    }
                    layer.stroke(lines, with: .color(Theme.macHatch), lineWidth: 1.5)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The Day page's legend, in the Heart rate header.
struct DayLegend: View {
    var showSleep: Bool
    var showMac: Bool

    var body: some View {
        HStack(spacing: Space.l) {
            item("Heart rate") { Capsule().fill(Theme.ember).frame(width: 14, height: 2) }
            if showSleep {
                item("Asleep") { RoundedRectangle(cornerRadius: 2).fill(Theme.dusk.opacity(0.35)).frame(width: 10, height: 10) }
            }
            if showMac {
                item("This Mac") { MacHatch(spans: [0...10]).frame(width: 10, height: 10).clipShape(.rect(cornerRadius: 2)) }
            }
            item("Zones 1–5") {
                HStack(spacing: 1) {
                    ForEach(1...5, id: \.self) { RoundedRectangle(cornerRadius: 1).fill(Theme.zone($0)).frame(width: 6, height: 6) }
                }
            }
        }
        .font(.captionText)
        .foregroundStyle(.secondary)
    }

    private func item<Swatch: View>(_ title: String, @ViewBuilder swatch: () -> Swatch) -> some View {
        HStack(spacing: 6) { swatch(); Text(title) }
    }
}
