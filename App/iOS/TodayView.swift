import SwiftUI
import TetherCore

/// The screens a Today card opens.
enum TodayDetail: String, Hashable {
    case stress, effort, recovery, sleep
}

struct TodayView: View {
    @Environment(AppModel.self) private var model
    /// Owned by the tab bar, so links from widgets can open a detail screen or the strap sheet.
    @Binding var path: [TodayDetail]
    @Binding var showingStrap: Bool

    var body: some View {
        NavigationStack(path: $path) {
            content
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: TodayDetail.self) { detail in
                    destination(detail)
                        .background(TetherBrand.ink)
                        .toolbarBackground(TetherBrand.ink, for: .navigationBar)
                }
        }
        .sheet(isPresented: $showingStrap) {
            StrapView()
                .safeAreaPadding(.top, 16)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(TetherBrand.ink)
        }
    }

    @ViewBuilder private func destination(_ detail: TodayDetail) -> some View {
        switch detail {
        case .stress:
            StressDetailView(detail: model.stress ?? .empty)
        case .effort:
            if let today = model.today, let effort = model.effort {
                EffortDetailView(today: today, detail: effort)
            } else {
                TabScreen { NotYet(title: "No heart rate yet today", detail: "Effort and zones fill in as the strap records.").card() }
            }
        case .recovery:
            RecoveryDetailView(detail: model.recovery, progress: model.baseline)
        case .sleep:
            SleepView()
        }
    }

    /// Glance first: the three scores, one sentence, the day, what's behind Charge, then stress.
    private var content: some View {
        let night = model.lastNight
        let chargeNight = model.latestNight ?? night
        let charge = chargeNight?.charge
        let sleepBand = Self.band(model.nights, before: night) { $0.totalSleepMin }
        return TabScreen {
            ScreenHeader(eyebrow: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)), title: "Today") {
                StrapChip { showingStrap = true }
            }
            ScoreStrip(charge: charge, chargeBand: Self.band(model.nights, before: chargeNight) { $0.charge },
                       progress: model.baseline, night: night, sleepBand: sleepBand, effort: model.today?.effort)
                .padding(.top, 6)
            Text(DayLine.sentence(zone: charge.map(ChargeZone.init(charge:)),
                                  nightsUntilCharge: model.baseline.nightsUntilCharge,
                                  sleptMinutes: night?.totalSleepMin, sleepBand: sleepBand, effort: model.today?.effort))
                .font(.title3.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 6)
            if let today = model.today, !today.isEmpty {
                DetailLink(.effort) {
                    TodayRibbon(today: today, sleep: Self.sleepSpan(night), now: Int(Date.now.timeIntervalSince1970),
                                live: model.liveHeartRate, beat: model.collector.lastSampleAt)
                }
            } else {
                NotYet(title: model.collector.isPaired ? "Collecting your first minutes" : "Not recording yet",
                       detail: model.collector.isPaired
                           ? "Your day's heart rate appears here within a minute of recording."
                           : "Tap the strap button at the top to pair your strap and start your history.")
                    .card()
            }
            DetailLink(.recovery) { RecoveryCard(detail: model.recovery, charge: charge) }
            if let today = model.today, !today.isEmpty {
                DetailLink(.stress) { StressRow(today: today) }
            }
        }
    }

    /// Your normal for a night measure, from the nights before the one shown.
    private static func band(_ nights: [NightSummary], before night: NightSummary?,
                             _ read: (NightSummary) -> Double?) -> NormalBand? {
        guard let night else { return nil }
        return NormalBand(past: nights.filter { $0.day < night.day }.compactMap(read))
    }

    private static func sleepSpan(_ night: NightSummary?) -> ClosedRange<Int>? {
        guard let start = night?.sleepStart, let end = night?.sleepEnd, start < end else { return nil }
        return start...end
    }

}

/// A Today card that opens a detail screen: the whole card is the tap target, and it shows a chevron.
struct DetailLink<Label: View>: View {
    let detail: TodayDetail
    @ViewBuilder var label: Label

    init(_ detail: TodayDetail, @ViewBuilder label: () -> Label) {
        self.detail = detail
        self.label = label()
    }

    var body: some View {
        NavigationLink(value: detail) {
            label.environment(\.opensDetail, true)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens more detail")
    }
}
