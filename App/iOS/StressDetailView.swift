import Charts
import SwiftUI
import TetherCore

/// Stress in depth: today's overall band, the half-hourly line, time in each band, and every waking
/// hour with its heart rate and HRV.
struct StressDetailView: View {
    let detail: StressDetail

    @State private var selected: Date?

    var body: some View {
        TabScreen {
            if detail.hours.isEmpty {
                NotYet(title: "No stress reading yet",
                       detail: "Stress needs about 5 minutes of steady heart rate in an hour between 6 AM and 10 PM.")
                    .card()
            } else {
                hero
                if detail.sustainedHighHours > 0 { sustainedBanner }
                timeline
                split
                hours
                if detail.hours.contains(where: { $0.breakdown != nil }) { StressMathsCard(detail: detail) }
                howItsRead
            }
        }
        .navigationTitle("Stress")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: Hero

    private var hero: some View {
        DetailHero(label: "Stress today", meaning: heroLine) {
            if let band = detail.dayBand {
                Text(band.name).foregroundStyle(StressStyle.color(band))
            } else {
                Text("–").foregroundStyle(TetherBrand.sub)
            }
        }
    }

    private var heroLine: String {
        var parts: [String] = []
        if detail.highMinutes > 0 { parts.append("\(SleepFormat.duration(minutes: Double(detail.highMinutes))) high") }
        if let peak = detail.peak, peak.band == .high || peak.band == .usual {
            parts.append("peak around \(hourLabel(peak.startTs))")
        }
        return parts.isEmpty ? "Mostly calm so far" : parts.joined(separator: " · ")
    }

    private var sustainedBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(TetherBrand.ember)
            Text("High for the last \(detail.sustainedHighHours) hours. A few slow breaths or a short walk away from screens can bring it down.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: 14)
    }

    // MARK: Timeline

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Through the day").font(.headline)
                Spacer()
                Text(selectionText).font(.caption).foregroundStyle(TetherBrand.sub).monospacedDigit()
            }
            Chart {
                ForEach(movingHours) { hour in
                    RectangleMark(xStart: .value("From", date(hour.startTs)), xEnd: .value("To", date(hour.startTs + 3_600)),
                                  yStart: .value("Low", 0), yEnd: .value("High", 3))
                        .foregroundStyle(TetherBrand.track)
                }
                RuleMark(y: .value("Usual", 1)).foregroundStyle(TetherBrand.cardStroke)
                    .lineStyle(.init(lineWidth: 1, dash: [3, 3]))
                RuleMark(y: .value("High", 2)).foregroundStyle(TetherBrand.cardStroke)
                    .lineStyle(.init(lineWidth: 1, dash: [3, 3]))
                ForEach(detail.timeline) { point in
                    LineMark(x: .value("Time", middle(point)), y: .value("Stress", point.level))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(TetherBrand.text.opacity(0.8))
                    PointMark(x: .value("Time", middle(point)), y: .value("Stress", point.level))
                        .foregroundStyle(StressStyle.color(point.band))
                        .symbolSize(28)
                }
                if let point = selectedPoint {
                    RuleMark(x: .value("Time", middle(point))).foregroundStyle(TetherBrand.sub.opacity(0.6))
                }
            }
            .chartYScale(domain: 0...3)
            .chartYAxis {
                AxisMarks(values: [0.5, 1.5, 2.5]) { value in
                    AxisValueLabel {
                        if let level = value.as(Double.self) { Text(StressBand(level: level).name) }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                    AxisGridLine().foregroundStyle(TetherBrand.cardStroke)
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
            .chartXSelection(value: $selected)
            .frame(height: 180)
            .accessibilityLabel("Stress through the day. \(heroLine)")
            if !movingHours.isEmpty {
                Label("Grey hours looked like movement, so they aren't scored.", systemImage: "figure.walk")
                    .font(.caption).foregroundStyle(TetherBrand.sub)
            }
        }
        .card()
    }

    private var movingHours: [StressDetail.Hour] { detail.hours.filter(\.wasMoving) }

    private var selectedPoint: StressDetail.Point? {
        guard let selected else { return nil }
        let ts = Int(selected.timeIntervalSince1970) - Self.halfWindow
        return detail.timeline.min { abs($0.ts - ts) < abs($1.ts - ts) }
    }

    private var selectionText: String {
        guard let point = selectedPoint else { return "Hold to see a time" }
        return "\(middle(point).formatted(date: .omitted, time: .shortened)) · \(point.band.name)"
    }

    // MARK: Split

    private var split: some View {
        let total = max(1, detail.calmMinutes + detail.usualMinutes + detail.highMinutes)
        let bands: [(StressBand, Int)] = [(.calm, detail.calmMinutes), (.usual, detail.usualMinutes), (.high, detail.highMinutes)]
        return VStack(alignment: .leading, spacing: 12) {
            Text("Time in each band").font(.headline)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(bands.filter { $0.1 > 0 }, id: \.0) { band, minutes in
                        Rectangle().fill(StressStyle.color(band))
                            .frame(width: max(3, geo.size.width * Double(minutes) / Double(total) - 2))
                    }
                }
                .clipShape(.rect(cornerRadius: 5))
            }
            .frame(height: 12)
            .background(TetherBrand.track, in: .rect(cornerRadius: 5))
            ForEach(bands, id: \.0) { band, minutes in
                HStack(spacing: 10) {
                    Circle().fill(StressStyle.color(band)).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(band.name).font(.subheadline)
                        Text(StressStyle.meaning(band)).font(.caption).foregroundStyle(TetherBrand.sub)
                    }
                    Spacer()
                    Text(SleepFormat.duration(minutes: Double(minutes))).font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    // MARK: Hours

    private var hours: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Hour by hour").font(.headline)
                Spacer()
                Text("heart rate · HRV").font(.caption).foregroundStyle(TetherBrand.sub)
            }
            .padding(.bottom, 8)
            ForEach(detail.hours.reversed()) { hour in
                HStack(spacing: 10) {
                    Text(hourLabel(hour.startTs)).font(.subheadline).monospacedDigit()
                        .frame(width: 52, alignment: .leading)
                    bandChip(hour)
                    Spacer()
                    Text(hour.meanHR.map { "\($0) bpm" } ?? "–").font(.subheadline).monospacedDigit()
                    Text(hour.hrv.map { "\($0) ms" } ?? "–").font(.subheadline).foregroundStyle(TetherBrand.sub)
                        .monospacedDigit().frame(width: 56, alignment: .trailing)
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
                if hour.id != detail.hours.first?.id { Divider().overlay(TetherBrand.cardStroke) }
            }
        }
        .card()
    }

    @ViewBuilder private func bandChip(_ hour: StressDetail.Hour) -> some View {
        if hour.wasMoving {
            Label("Moving", systemImage: "figure.walk").font(.caption.weight(.semibold)).foregroundStyle(TetherBrand.sub)
        } else if let band = hour.band {
            HStack(spacing: 5) {
                Circle().fill(StressStyle.color(band)).frame(width: 7, height: 7)
                Text(band.name).font(.caption.weight(.semibold))
            }
        } else {
            Text("Not enough data").font(.caption).foregroundStyle(TetherBrand.sub)
        }
    }

    private var howItsRead: some View {
        HowItsWorkedOut(text: "Each hour's heart rate and HRV are compared with the calmest part of your own day. Usual is a normal hour for you; high means heart rate up and HRV down together. It needs about 5 minutes of steady heart rate in an hour between 6 AM and 10 PM. When your strap has sent its movement, hours you spent moving are left out rather than read as stress; without it, a workout or a brisk walk can still read as high.")
    }

    /// Each point reads a full hour, so it's drawn at the middle of that hour.
    private static let halfWindow = 1_800
    private func middle(_ point: StressDetail.Point) -> Date { date(point.ts + Self.halfWindow) }

    private func date(_ ts: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(ts)) }
    private func hourLabel(_ ts: Int) -> String { date(ts).formatted(.dateTime.hour()) }
}

/// The three stress bands' colours and plain-language meanings. Always shown with the band's name.
enum StressStyle {
    static func color(_ band: StressBand) -> Color {
        switch band {
        case .calm: TetherBrand.dusk
        case .usual: TetherBrand.bone
        case .high: TetherBrand.ember
        }
    }

    static func meaning(_ band: StressBand) -> String {
        switch band {
        case .calm: "Below your usual: relaxed, resting"
        case .usual: "A normal hour for you"
        case .high: "Heart rate up, HRV down"
        }
    }
}
