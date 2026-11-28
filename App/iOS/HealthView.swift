import Charts
import SwiftUI
import TetherCore

/// Last night's vitals, Aurora style: the early warning as a chip, HRV as the hero with its week, then
/// the other vitals as glass tiles, each on its own normal band. A tile opens its week below the grid.
/// Blood oxygen is the strap's own nightly %, shown as experimental.
struct HealthView: View {
    @Environment(AppModel.self) private var model
    @State private var open: String?

    var body: some View {
        let vitals = HealthVital.compute(latest: model.lastNight, history: model.nights)
        let monitor = model.healthMonitor
        let hrv = vitals.first { $0.name == "HRV" }
        let others = vitals.filter { $0.name != "HRV" }
        TabScreen {
            ScreenHeader(eyebrow: "Last night", title: "Health")
            if let monitor { WarningChip(warning: monitor.warning).staggered(0) }
            if let hrv {
                HRVHero(vital: hrv, flagged: flag(hrv, monitor)).staggered(1)
            }
            if !others.isEmpty || model.spo2Nights.last != nil {
                tiles(others, monitor: monitor)
            }
            if let name = open { detail(name, vitals: vitals, monitor: monitor) }
            if let fitness = model.fitnessAge { FitnessCard(reading: fitness).staggered(7) }
            if vitals.isEmpty {
                Text("Wear the strap to bed. Your vitals fill in in the morning.")
                    .font(.footnote).foregroundStyle(TetherBrand.sub)
            }
        }
        #if DEBUG
        // `-tether.debugOpen "Resting HR"` opens a tile, for screenshots without taps.
        .onAppear { if let name = UserDefaults.standard.string(forKey: "tether.debugOpen") { open = name } }
        #endif
    }

    private func tiles(_ vitals: [HealthVital], monitor: HealthMonitor?) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(Array(vitals.enumerated()), id: \.element.id) { index, vital in
                VitalTile(vital: vital, flagged: flag(vital, monitor), isOpen: open == vital.name) { toggle(vital.name) }
                    .staggered(2 + index)
            }
            if let latest = model.spo2Nights.last {
                SpO2Tile(latest: latest, isOpen: open == SpO2Detail.name) { toggle(SpO2Detail.name) }
                    .staggered(2 + vitals.count)
            }
        }
    }

    @ViewBuilder
    private func detail(_ name: String, vitals: [HealthVital], monitor: HealthMonitor?) -> some View {
        if name == SpO2Detail.name, let latest = model.spo2Nights.last {
            SpO2Detail(latest: latest, week: Array(model.spo2Nights.suffix(7)))
                .transition(.opacity.combined(with: .move(edge: .top)))
        } else if let vital = vitals.first(where: { $0.name == name }), vital.name != "HRV" {
            VitalDetail(vital: vital, flagged: flag(vital, monitor))
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    /// The health monitor's verdict: only an out-of-range flag turns a vital amber.
    private func flag(_ vital: HealthVital, _ monitor: HealthMonitor?) -> Bool {
        monitor?.flags.first { $0.name == vital.name }?.outOfRange == true
    }

    private func toggle(_ name: String) {
        withAnimation(Motion.quick) { open = open == name ? nil : name }
    }
}

// MARK: - Warning chip

/// The early warning in one glass chip. A short second line only when something is off.
private struct WarningChip: View {
    let warning: HealthMonitor.Warning

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                if let detail { Text(detail).font(.footnote).foregroundStyle(TetherBrand.sub) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glass(cornerRadius: 20)
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
        default: TetherBrand.dusk
        }
    }
}

// MARK: - HRV hero

/// HRV large, its change against the rest of the week, and the week as a line over your normal band.
private struct HRVHero: View {
    let vital: HealthVital
    let flagged: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("HRV", systemImage: VitalIcon.name("HRV"))
                    .font(.footnote.weight(.semibold)).textCase(.uppercase).tracking(0.6)
                    .foregroundStyle(TetherBrand.sub)
                Spacer()
                if let change = VitalFormat.weekChange(vital) {
                    Text(change).font(.footnote.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(TetherBrand.sub)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(vital.value.map { VitalFormat.number($0, vital) } ?? "–")
                    .font(.system(size: 52, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(flagged ? TetherBrand.headsUp : TetherBrand.text)
                Text(vital.unit).font(.title3.weight(.semibold)).foregroundStyle(TetherBrand.sub)
            }
            WeekChart(vital: vital, tint: flagged ? TetherBrand.headsUp : TetherBrand.dusk).frame(height: 84)
            Text(VitalFormat.normal(vital)).font(.caption).foregroundStyle(TetherBrand.sub)
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Tiles

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

/// Shared wording for vitals: the number, your normal, and the change across the week.
enum VitalFormat {
    static func number(_ value: Double, _ vital: HealthVital) -> String {
        String(format: "%.\(vital.decimals)f", value)
    }

    static func normal(_ vital: HealthVital) -> String {
        guard let band = vital.band else { return "Learning your normal" }
        let low = number(band.low, vital), high = number(band.high, vital)
        return "Your normal \(low == high ? low : "\(low)–\(high)") \(vital.unit)"
    }

    /// "↑ 2 ms vs your week": last night against the mean of the nights before it in the week.
    static func weekChange(_ vital: HealthVital) -> String? {
        let before = vital.recent.dropLast().compactMap(\.value)
        guard let value = vital.value, before.count >= 2 else { return nil }
        let change = value - before.reduce(0, +) / Double(before.count)
        let size = number(abs(change), vital)
        if size == number(0, vital) { return "Level with your week" }
        return "\(change > 0 ? "↑" : "↓") \(size) \(vital.unit) vs your week"
    }

    static func placement(_ value: Double, _ vital: HealthVital) -> RangePlacement {
        let domain = vital.band.map { RangePlacement.domain(around: $0, value: value) } ?? (value * 0.5)...(value * 1.5)
        return RangePlacement(value: value, band: vital.band, domain: domain)
    }
}

/// A glass tile: icon and name, the value, and where it sits on your normal band.
private struct VitalTile: View {
    let vital: HealthVital
    let flagged: Bool
    let isOpen: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            TileFrame(icon: VitalIcon.name(vital.name), name: vital.name, isOpen: isOpen, flagged: flagged) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(vital.value.map { VitalFormat.number($0, vital) } ?? "–")
                        .font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit()
                    Text(vital.unit).font(.caption).foregroundStyle(TetherBrand.sub)
                }
            } bar: {
                if let value = vital.value {
                    RangeBar(placement: VitalFormat.placement(value, vital),
                             tint: flagged ? TetherBrand.headsUp : TetherBrand.good)
                        .shadow(color: (flagged ? TetherBrand.headsUp : TetherBrand.good).opacity(0.5), radius: 4)
                } else {
                    RangeBar(placement: RangePlacement(value: 0, band: nil, domain: 0...1), showsValue: false)
                }
            } caption: {
                Text(caption)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(vital.name), \(vital.value.map { "\(VitalFormat.number($0, vital)) \(vital.unit)" } ?? "not measured"), \(verdict)")
        .accessibilityHint(isOpen ? "Hides the week" : "Shows the week")
    }

    private var caption: String {
        guard let band = vital.band else { return "Learning your normal" }
        let low = VitalFormat.number(band.low, vital), high = VitalFormat.number(band.high, vital)
        return "typical \(low == high ? low : "\(low)–\(high)")"
    }

    private var verdict: String {
        guard let value = vital.value else { return "not measured last night" }
        if flagged { return "outside your usual range" }
        guard let band = vital.band else { return "learning your normal" }
        if band.contains(value) { return "in your normal" }
        return value < band.low ? "below your normal" : "above your normal"
    }
}

/// Blood oxygen's tile: the night's middle reading on a fixed 88–100 scale.
private struct SpO2Tile: View {
    let latest: NightSpO2
    let isOpen: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            TileFrame(icon: "drop", name: "Blood oxygen", isOpen: isOpen, flagged: false) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(latest.median)").font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit()
                    Text("%").font(.caption).foregroundStyle(TetherBrand.sub)
                }
            } bar: {
                RangeBar(placement: RangePlacement(value: Double(latest.median), band: nil, domain: 88...100),
                         tint: TetherBrand.dusk)
                    .shadow(color: TetherBrand.dusk.opacity(0.5), radius: 4)
            } caption: {
                Text("Experimental")
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Blood oxygen, experimental, \(latest.median) percent")
        .accessibilityHint(isOpen ? "Hides the week" : "Shows the week")
    }
}

/// The tile layout every vital shares. An open tile gets a brighter edge.
private struct TileFrame<Value: View, Bar: View, Caption: View>: View {
    let icon: String
    let name: String
    let isOpen: Bool
    let flagged: Bool
    @ViewBuilder var value: Value
    @ViewBuilder var bar: Bar
    @ViewBuilder var caption: Caption

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(flagged ? TetherBrand.headsUp : TetherBrand.sub)
                Text(name).font(.footnote.weight(.semibold)).foregroundStyle(TetherBrand.sub)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            value.lineLimit(1).minimumScaleFactor(0.7)
            bar
            caption.font(.caption).foregroundStyle(TetherBrand.sub).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 22)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Color.white.opacity(isOpen ? 0.35 : 0), lineWidth: 1))
    }
}

// MARK: - Details

/// An open tile's week: where last night sits, the line, and your normal in words.
private struct VitalDetail: View {
    let vital: HealthVital
    let flagged: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(vital.name).font(.headline)
                Spacer()
                if let change = VitalFormat.weekChange(vital) {
                    Text(change).font(.footnote).monospacedDigit().foregroundStyle(TetherBrand.sub)
                }
            }
            if let value = vital.value {
                RangeBar(placement: VitalFormat.placement(value, vital), tint: flagged ? TetherBrand.headsUp : TetherBrand.text)
            }
            WeekChart(vital: vital, tint: flagged ? TetherBrand.headsUp : TetherBrand.good).frame(height: 72)
            Text(VitalFormat.normal(vital)).font(.caption).foregroundStyle(TetherBrand.sub)
        }
        .card()
    }
}

/// Blood oxygen from the strap's own nightly reading. Experimental: not checked against a medical device,
/// and nothing else in Tether uses it.
private struct SpO2Detail: View {
    static let name = "Blood oxygen"
    let latest: NightSpO2
    let week: [NightSpO2]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Self.name).font(.headline)
            HStack(spacing: 24) {
                figure("Middle", "\(latest.median)%")
                figure("Lowest", "\(latest.low)%")
                figure("Below 90%", "\(latest.minutesBelow90) min")
            }
            if week.count >= 2 {
                Chart(week) { night in
                    LineMark(x: .value("Night", String(night.day.suffix(2))), y: .value("Blood oxygen", night.median))
                        .foregroundStyle(TetherBrand.dusk).interpolationMethod(.catmullRom)
                    PointMark(x: .value("Night", String(night.day.suffix(2))), y: .value("Blood oxygen", night.median))
                        .foregroundStyle(TetherBrand.dusk).symbolSize(24)
                }
                .chartYScale(domain: 88...100)
                .chartYAxis { AxisMarks(values: [90, 95, 100]) }
                .frame(height: 72)
            }
            Text("Your strap's own reading. Not checked against a medical device.")
                .font(.caption).foregroundStyle(TetherBrand.sub)
        }
        .card()
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption).foregroundStyle(TetherBrand.sub)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }
}

/// Fitness age as a glass row: an estimate, never a biological age.
private struct FitnessCard: View {
    let reading: FitnessAge.Reading

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.run").frame(width: 24).foregroundStyle(TetherBrand.sub)
            VStack(alignment: .leading, spacing: 2) {
                Text("Fitness age")
                Text(note).font(.caption).foregroundStyle(TetherBrand.sub)
            }
            Spacer()
            Text(value ?? "–").font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
        }
        .card(padding: 16)
        .accessibilityElement(children: .combine)
    }

    private var value: String? {
        if case .estimate(let years, _, _) = reading { return "\(years)" }
        return nil
    }

    private var note: String {
        switch reading {
        case .tooYoung(let startsAt): "Starts at \(startsAt): the formula is for adults"
        case .needsMoreDays(let have, let need): "\(have) of \(need) nights so far"
        case .estimate(_, let band, _): "Estimate, ±\(band) years"
        }
    }
}

/// The last week of nights as a soft line, with your normal as a band behind it. Draws in on appear.
private struct WeekChart: View {
    let vital: HealthVital
    var tint: Color = TetherBrand.dusk
    @State private var drawn = false

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
                    .foregroundStyle(TetherBrand.good.opacity(0.12))
            }
            ForEach(points, id: \.day) { point in
                AreaMark(x: .value("Night", weekday(point.day)), yStart: .value("Floor", yDomain.lowerBound),
                         yEnd: .value(vital.name, point.value))
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Night", weekday(point.day)), y: .value(vital.name, point.value))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.catmullRom)
            }
            if let last = points.last {
                PointMark(x: .value("Night", weekday(last.day)), y: .value(vital.name, last.value))
                    .foregroundStyle(tint).symbolSize(50)
            }
        }
        .chartXScale(domain: vital.recent.map { weekday($0.day) })
        .chartYScale(domain: yDomain)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel().foregroundStyle(TetherBrand.sub) }
        }
        .mask(alignment: .leading) {
            GeometryReader { geo in Rectangle().frame(width: drawn ? geo.size.width : 0) }
        }
        .entrance($drawn, Motion.draw, delay: 0.25)
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
