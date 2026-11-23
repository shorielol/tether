import Charts
import SwiftUI
import TetherCore

/// Last night's vitals in one list: icon, value, and an arrow when it's outside your normal. A row opens
/// to its range and week. Blood oxygen is the strap's own nightly %, shown as experimental.
struct HealthView: View {
    @Environment(AppModel.self) private var model
    @State private var open: Set<String> = []

    var body: some View {
        let vitals = HealthVital.compute(latest: model.lastNight, history: model.nights)
        let monitor = model.healthMonitor
        TabScreen {
            ScreenHeader(eyebrow: "Last night", title: "Health")
            if let monitor { WarningRow(warning: monitor.warning) }
            VStack(spacing: 0) {
                ForEach(Array(vitals.enumerated()), id: \.element.id) { index, vital in
                    if index > 0 { Divider().overlay(TetherBrand.cardStroke) }
                    VitalRow(vital: vital, flag: monitor?.flags.first { $0.name == vital.name },
                             isOpen: open.contains(vital.name)) { toggle(vital.name) }
                }
                if let latest = model.spo2Nights.last {
                    if !vitals.isEmpty { Divider().overlay(TetherBrand.cardStroke) }
                    SpO2Row(latest: latest, week: Array(model.spo2Nights.suffix(7)),
                            isOpen: open.contains("Blood oxygen")) { toggle("Blood oxygen") }
                }
                if let fitness = model.fitnessAge {
                    if !vitals.isEmpty || !model.spo2Nights.isEmpty { Divider().overlay(TetherBrand.cardStroke) }
                    FitnessRow(reading: fitness)
                }
            }
            .card(padding: 0)
            if vitals.isEmpty {
                Text("Wear the strap to bed. Your vitals fill in in the morning.")
                    .font(.footnote).foregroundStyle(TetherBrand.sub)
            }
        }
        #if DEBUG
        // `-tether.debugOpen HRV` opens a row, for screenshots without taps.
        .onAppear { if let name = UserDefaults.standard.string(forKey: "tether.debugOpen") { open = [name] } }
        #endif
    }

    private func toggle(_ name: String) {
        withAnimation(.snappy(duration: 0.25)) {
            if open.contains(name) { open.remove(name) } else { open.insert(name) }
        }
    }
}

/// The early warning in one line. A short second line only when something is off.
private struct WarningRow: View {
    let warning: HealthMonitor.Warning

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                if let detail { Text(detail).font(.footnote).foregroundStyle(TetherBrand.sub) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch warning {
        case .learning(let nights): "Early warning starts in \(nights) \(nights == 1 ? "night" : "nights")"
        case .clear: "Nothing unusual last night"
        case .mild: "A little off your normal"
        case .raised: "Several signals off your normal"
        case .explained: "Off your normal, likely explained"
        }
    }

    private var detail: String? {
        switch warning {
        case .learning, .clear: nil
        case .mild(let signals), .explained(let signals): signals.joined(separator: ", ")
        case .raised(let signals): signals.joined(separator: ", ") + ". Take it easy today."
        }
    }

    private var icon: String {
        switch warning {
        case .raised, .mild: "exclamationmark.circle.fill"
        case .clear: "checkmark.circle.fill"
        default: "circle.dotted"
        }
    }

    private var tint: Color {
        switch warning {
        case .raised, .mild: TetherBrand.headsUp
        case .clear: TetherBrand.good
        default: TetherBrand.sub
        }
    }
}

enum VitalIcon {
    static func name(_ vital: String) -> String {
        switch vital {
        case "HRV": "waveform.path.ecg"
        case "Resting HR": "heart"
        case "Breathing": "lungs"
        case "Skin temp": "thermometer.medium"
        case "Asleep": "bed.double"
        case "Efficiency": "percent"
        default: "circle"
        }
    }
}

private struct VitalRow: View {
    let vital: HealthVital
    /// The health monitor's verdict: only an out-of-range flag turns the row amber.
    let flag: HealthMonitor.Flag?
    let isOpen: Bool
    let toggle: () -> Void

    private var flagged: Bool { flag?.outOfRange == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: toggle) {
                HStack(spacing: 12) {
                    Image(systemName: VitalIcon.name(vital.name)).frame(width: 24)
                        .foregroundStyle(flagged ? TetherBrand.headsUp : TetherBrand.sub)
                    Text(vital.name)
                    Spacer()
                    if let arrow { Image(systemName: arrow).font(.caption.weight(.bold)).foregroundStyle(flagged ? TetherBrand.headsUp : TetherBrand.sub) }
                    Text(vital.value.map { "\(format($0)) \(vital.unit)" } ?? "–")
                        .fontWeight(.semibold).monospacedDigit()
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(TetherBrand.sub)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(vital.name), \(vital.value.map { "\(format($0)) \(vital.unit)" } ?? "not measured"), \(verdict)")
            .accessibilityHint(isOpen ? "Hides the week" : "Shows the week")
            if isOpen {
                if let value = vital.value {
                    RangeBar(placement: placement(value), tint: flagged ? TetherBrand.headsUp : TetherBrand.text)
                }
                WeekChart(vital: vital).frame(height: 64)
                Text(normalText).font(.caption).foregroundStyle(TetherBrand.sub)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private var arrow: String? {
        guard let value = vital.value, let band = vital.band, !band.contains(value) else { return nil }
        return value < band.low ? "arrow.down" : "arrow.up"
    }

    private var verdict: String {
        guard let value = vital.value else { return "not measured last night" }
        if flagged { return "outside your usual range" }
        guard let band = vital.band else { return "learning your normal" }
        if band.contains(value) { return "in your normal" }
        return value < band.low ? "below your normal" : "above your normal"
    }

    private var normalText: String {
        guard let band = vital.band else { return "Learning your normal" }
        let low = format(band.low), high = format(band.high)
        return "Your normal \(low == high ? low : "\(low)–\(high)") \(vital.unit)"
    }

    private func placement(_ value: Double) -> RangePlacement {
        let domain = vital.band.map { RangePlacement.domain(around: $0, value: value) } ?? (value * 0.5)...(value * 1.5)
        return RangePlacement(value: value, band: vital.band, domain: domain)
    }

    private func format(_ value: Double) -> String { String(format: "%.\(vital.decimals)f", value) }
}

/// A list row with no week to open: an icon, a name, a value or a dash, and an optional short note.
private struct PlainRow: View {
    let icon: String
    let name: String
    let value: String?
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 24).foregroundStyle(TetherBrand.sub)
                Text(name)
                Spacer()
                Text(value ?? "–").fontWeight(.semibold).monospacedDigit()
            }
            if let note {
                Text(note).font(.caption).foregroundStyle(TetherBrand.sub).padding(.leading, 36)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

/// Fitness age as a row: an estimate, never a biological age.
private struct FitnessRow: View {
    let reading: FitnessAge.Reading

    var body: some View {
        switch reading {
        case .tooYoung(let startsAt):
            PlainRow(icon: "figure.run", name: "Fitness age", value: nil, note: "Starts at \(startsAt): the formula is for adults")
        case .needsMoreDays(let have, let need):
            PlainRow(icon: "figure.run", name: "Fitness age", value: nil, note: "\(have) of \(need) nights so far")
        case .estimate(let years, let band, _):
            PlainRow(icon: "figure.run", name: "Fitness age", value: "\(years)", note: "Estimate, ±\(band) years")
        }
    }
}

/// The last week of nights as a small line, with your normal as a band behind it.
private struct WeekChart: View {
    let vital: HealthVital

    private static let dayKey: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private var points: [(day: String, value: Double)] {
        vital.recent.compactMap { night in night.value.map { (night.day, $0) } }
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.value) + [vital.band?.low, vital.band?.high].compactMap { $0 }
        let low = values.min() ?? 0, high = values.max() ?? 1
        let pad = max((high - low) * 0.25, abs(high) * 0.05, 1)
        return (low - pad)...(high + pad)
    }

    var body: some View {
        Chart {
            if let band = vital.band {
                RectangleMark(yStart: .value("Normal low", band.low), yEnd: .value("Normal high", band.high))
                    .foregroundStyle(Color.white.opacity(0.07))
            }
            ForEach(points, id: \.day) { point in
                LineMark(x: .value("Night", weekday(point.day)), y: .value(vital.name, point.value))
                    .foregroundStyle(Color(white: 0.8))
                PointMark(x: .value("Night", weekday(point.day)), y: .value(vital.name, point.value))
                    .foregroundStyle(Color(white: 0.8))
                    .symbolSize(24)
            }
        }
        .chartXScale(domain: vital.recent.map { weekday($0.day) })
        .chartYScale(domain: yDomain)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel().foregroundStyle(TetherBrand.sub) }
        }
        .accessibilityLabel(summary)
    }

    /// "Sun" for a night key, falling back to the key itself.
    private func weekday(_ day: String) -> String {
        Self.dayKey.date(from: day).map { $0.formatted(.dateTime.weekday(.abbreviated)) } ?? day
    }

    private var summary: String {
        guard let low = points.map(\.value).min(), let high = points.map(\.value).max() else {
            return "\(vital.name): no nights measured this week"
        }
        return "\(vital.name) over the last \(points.count) nights, from \(Int(low.rounded())) to \(Int(high.rounded()))"
    }
}


/// Blood oxygen from the strap's own nightly reading. Experimental: not checked against a medical device,
/// and nothing else in Tether uses it.
private struct SpO2Row: View {
    let latest: NightSpO2
    let week: [NightSpO2]
    let isOpen: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: toggle) {
                HStack(spacing: 12) {
                    Image(systemName: "drop").frame(width: 24).foregroundStyle(TetherBrand.sub)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Blood oxygen")
                        Text("Experimental").font(.caption2).foregroundStyle(TetherBrand.sub)
                    }
                    Spacer()
                    Text("\(latest.median)%").fontWeight(.semibold).monospacedDigit()
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(TetherBrand.sub)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Blood oxygen, experimental, \(latest.median) percent")
            .accessibilityHint(isOpen ? "Hides the week" : "Shows the week")
            if isOpen {
                HStack(spacing: 24) {
                    figure("Lowest", "\(latest.low)%")
                    figure("Below 90%", "\(latest.minutesBelow90) min")
                }
                if week.count >= 2 {
                    Chart(week) { night in
                        LineMark(x: .value("Night", String(night.day.suffix(2))), y: .value("Blood oxygen", night.median))
                            .foregroundStyle(Color(white: 0.8))
                        PointMark(x: .value("Night", String(night.day.suffix(2))), y: .value("Blood oxygen", night.median))
                            .foregroundStyle(Color(white: 0.8)).symbolSize(24)
                    }
                    .chartYScale(domain: 88...100)
                    .chartYAxis { AxisMarks(values: [90, 95, 100]) }
                    .frame(height: 64)
                }
                Text("Your strap's own reading. Not checked against a medical device.")
                    .font(.caption).foregroundStyle(TetherBrand.sub)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption).foregroundStyle(TetherBrand.sub)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }
}
