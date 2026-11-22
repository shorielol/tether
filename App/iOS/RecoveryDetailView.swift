import Charts
import SwiftUI
import TetherCore

/// Recovery in depth: Charge and its zone, what moved it, last night against your own normal, and
/// the last week of HRV and resting heart rate.
struct RecoveryDetailView: View {
    let detail: RecoveryDetail?
    let progress: BaselineProgress

    var body: some View {
        TabScreen {
            if let detail {
                hero(detail)
                if !detail.drivers.isEmpty { drivers(detail) }
                measures(detail)
                if detail.recent.count >= 2 { trend(detail) }
                notMeasured
            } else {
                NotYet(title: "No night scored yet",
                       detail: "Recovery is read from your sleep. Wear the strap tonight with Tether open, and it appears the morning after.")
                    .card()
            }
        }
        .navigationTitle("Recovery")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: Hero

    @ViewBuilder private func hero(_ detail: RecoveryDetail) -> some View {
        if let charge = detail.night.charge, let zone = detail.zone {
            DetailHero(label: "Charge", meaning: "\(zone.name) · \(zone.advice)") {
                Text("\(Text("\(Int(charge.rounded()))"))\(Text("%").font(.title.weight(.semibold)))")
                    .foregroundStyle(TetherBrand.charge(zone))
            }
        } else {
            DetailHero(label: "Charge",
                       meaning: "\(progress.scoredNights) of \(BaselineProgress.chargeNights) nights. Charge compares each night with your own normal, so it starts once it has one. \(detail.nightsUntilCharge) more to go.") {
                Text("Learning").foregroundStyle(TetherBrand.sub)
            }
        }
    }

    // MARK: Drivers

    private func drivers(_ detail: RecoveryDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What moved it").font(.headline)
            ForEach(detail.drivers) { driver in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: driver.deltaPoints >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(driver.deltaPoints >= 0 ? TetherBrand.good : TetherBrand.headsUp)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(driver.label).font(.subheadline.weight(.semibold))
                        Text(driver.valueText).font(.caption).foregroundStyle(TetherBrand.sub)
                    }
                    Spacer()
                    Text(driver.deltaPoints >= 0 ? "+\(driver.deltaPoints)" : "\(driver.deltaPoints)")
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    // MARK: Last night vs normal

    private func measures(_ detail: RecoveryDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last night vs your normal").font(.headline)
                Spacer()
            }
            .padding(.bottom, 8)
            ForEach(detail.measures) { measure in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(measure.name).font(.subheadline)
                        Text(normalText(measure)).font(.caption).foregroundStyle(TetherBrand.sub)
                    }
                    Spacer()
                    if let delta = measure.delta { deltaChip(measure, delta) }
                    Text("\(format(measure.value, measure.decimals)) \(measure.unit)")
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                        .frame(minWidth: 78, alignment: .trailing)
                }
                .padding(.top, 8)
                .padding(.bottom, measure.band == nil ? 8 : 6)
                .accessibilityElement(children: .combine)
                if let band = measure.band {
                    RangeBar(placement: RangePlacement(value: measure.value, band: band,
                                                       domain: RangePlacement.domain(around: band, value: measure.value)),
                             tint: !band.contains(measure.value) && measure.isBetter == false ? TetherBrand.headsUp : TetherBrand.text)
                        .padding(.bottom, 10)
                }
                if measure.id != detail.measures.last?.id { Divider().overlay(TetherBrand.cardStroke) }
            }
            if detail.measures.contains(where: { $0.normal == nil }) {
                Text("Your normal appears after \(RecoveryDetail.minNightsForNormal) earlier nights.")
                    .font(.caption).foregroundStyle(TetherBrand.sub).padding(.top, 6)
            }
        }
        .card()
    }

    private func normalText(_ measure: RecoveryDetail.Measure) -> String {
        guard let normal = measure.normal else { return "normal not set yet" }
        return "normal \(format(normal, measure.decimals)) \(measure.unit)"
    }

    private func deltaChip(_ measure: RecoveryDetail.Measure, _ delta: Double) -> some View {
        let sign = delta > 0 ? "+" : delta < 0 ? "−" : "±"
        let color: Color = switch measure.isBetter {
        case true?: TetherBrand.good
        case false?: TetherBrand.headsUp
        case nil: TetherBrand.sub
        }
        return Text("\(sign)\(format(abs(delta), measure.decimals))")
            .font(.caption.weight(.semibold)).monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.14), in: .capsule)
    }

    // MARK: Trend

    private func trend(_ detail: RecoveryDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Last \(detail.recent.count) nights").font(.headline)
            miniChart(title: "HRV", unit: "ms", color: TetherBrand.good, minSpan: 20,
                      points: detail.recent.compactMap { night in night.hrv.map { (night.day, $0) } })
            miniChart(title: "Resting HR", unit: "bpm", color: TetherBrand.ember, minSpan: 10,
                      points: detail.recent.compactMap { night in night.restingHR.map { (night.day, Double($0)) } })
        }
        .card()
    }

    /// `minSpan` keeps the axis at least that tall, so a one-beat wobble doesn't look like a swing.
    private func miniChart(title: String, unit: String, color: Color, minSpan: Double,
                           points: [(String, Double)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(points.last.map { "\(Int($0.1.rounded())) \(unit) last night" } ?? "–")
                    .font(.caption).foregroundStyle(TetherBrand.sub).monospacedDigit()
            }
            Chart(points, id: \.0) { day, value in
                LineMark(x: .value("Night", String(day.suffix(2))), y: .value(title, value))
                    .foregroundStyle(color)
                PointMark(x: .value("Night", String(day.suffix(2))), y: .value(title, value))
                    .foregroundStyle(color).symbolSize(24)
            }
            .chartYScale(domain: domain(points.map(\.1), minSpan: minSpan))
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
            .frame(height: 80)
            .accessibilityLabel("\(title) over the last \(points.count) nights")
        }
    }

    private func domain(_ values: [Double], minSpan: Double) -> ClosedRange<Double> {
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let pad = max(minSpan * 0.1, (minSpan - (high - low)) / 2)
        return (low - pad)...(high + pad)
    }

    private var notMeasured: some View {
        HowItsWorkedOut(text: "Charge compares last night with your own normal: HRV counts most, then resting heart rate, sleep and breathing. Your normal is built from your earlier nights, and the grey band on each bar is the middle half of them. Charge starts after \(BaselineProgress.chargeNights) nights. Zones: Green 67–100, Yellow 34–66, Red 0–33. Skin temperature joins once Tether reads it into a nightly value; your strap already records it.")
    }

    private func format(_ value: Double, _ decimals: Int) -> String {
        String(format: "%.\(decimals)f", value)
    }
}
