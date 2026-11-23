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
                if let inputs = detail.night.chargeInputs, let breakdown = ScoreBreakdown.charge(inputs),
                   breakdown.total == detail.night.charge.map({ $0.rounded() }) {
                    ChargeMathsCard(inputs: inputs, breakdown: breakdown)
                } else if !detail.drivers.isEmpty {
                    drivers(detail)
                }
                measures(detail)
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
            ForEach(detail.measures) { measure in
                HStack(spacing: 12) {
                    Image(systemName: VitalIcon.name(measure.name)).frame(width: 24).foregroundStyle(TetherBrand.sub)
                    Text(measure.name).font(.subheadline)
                    Spacer()
                    Text("\(format(measure.value, measure.decimals)) \(measure.unit)")
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                .padding(.top, 10)
                .padding(.bottom, measure.band == nil ? 10 : 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(measure.name) \(format(measure.value, measure.decimals)) \(measure.unit), \(normalText(measure))")
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

    private var notMeasured: some View {
        HowItsWorkedOut(text: "Charge compares last night with your own normal: HRV counts most, then resting heart rate, sleep and breathing. Your normal is built from your earlier nights, and the grey band on each bar is the middle half of them. Charge starts after \(BaselineProgress.chargeNights) nights. Zones: Green 67–100, Yellow 34–66, Red 0–33. Skin temperature is your skin's average while asleep; once it has a normal, a night well away from it in either direction pulls Charge down a little.")
    }

    private func format(_ value: Double, _ decimals: Int) -> String {
        String(format: "%.\(decimals)f", value)
    }
}
