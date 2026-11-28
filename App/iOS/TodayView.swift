import SwiftUI
import TetherCore

/// The screens a Today card opens.
enum TodayDetail: String, Hashable {
    case stress, effort, recovery, sleep, marks, breathe, coach, energy
}

struct TodayView: View {
    @Environment(AppModel.self) private var model
    /// Owned by the tab bar, so links from widgets can open a detail screen or the strap sheet.
    @Binding var path: [TodayDetail]
    @Binding var showingStrap: Bool
    @State private var showingCheckUp = false
    /// The day the check up last popped up on its own, so it does that once a morning.
    @AppStorage("tether.checkUp.offeredDay") private var offeredDay = ""
    /// Detail screens zoom out of the card that opened them.
    @Namespace private var zoom
    @State private var zoomSource = ""

    var body: some View {
        NavigationStack(path: $path) {
            content
                .environment(\.detailZoom, zoom)
                .environment(\.openDetail) { detail, source in
                    zoomSource = source
                    path.append(detail)
                }
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: TodayDetail.self) { detail in
                    destination(detail)
                        .navigationTransition(.zoom(sourceID: zoomSource, in: zoom))
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
        .sheet(isPresented: $showingCheckUp) {
            CheckUpSheet().presentationBackground(TetherBrand.ink)
        }
        .task(id: model.journalDue) {
            let day = Date.now.formatted(.iso8601.year().month().day())
            guard model.journalDue, offeredDay != day, !showingStrap else { return }
            try? await Task.sleep(for: .seconds(1))
            offeredDay = day
            showingCheckUp = true
        }
    }

    @ViewBuilder private func destination(_ detail: TodayDetail) -> some View {
        switch detail {
        case .stress:
            StressDetailView(detail: model.stress ?? .empty)
        case .effort:
            if let today = model.today, let effort = model.effort {
                EffortDetailView(today: today, detail: effort, steps: model.steps)
            } else {
                TabScreen { NotYet(title: "No heart rate yet today", detail: "Effort and zones fill in as the strap records.").card() }
            }
        case .recovery:
            RecoveryDetailView(detail: model.recovery, progress: model.baseline)
        case .sleep:
            SleepView()
        case .marks:
            MarksView()
        case .breathe:
            BreatheView()
        case .coach:
            CoachView()
        case .energy:
            EnergyView()
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
                HStack(spacing: 8) {
                    AskButton()
                    StrapChip { showingStrap = true }
                }
            }
            ScoreStrip(charge: charge, chargeBand: Self.band(model.nights, before: chargeNight) { $0.charge },
                       progress: model.baseline, night: night, sleepBand: sleepBand, effort: model.today?.effort)
                .padding(.top, 6)
            StreamedText(text: DayLine.sentence(zone: charge.map(ChargeZone.init(charge:)),
                                                nightsUntilCharge: model.baseline.nightsUntilCharge,
                                                sleptMinutes: night?.totalSleepMin, sleepBand: sleepBand,
                                                effort: model.today?.effort))
                .font(.title3.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
            if model.journalDue {
                Button { showingCheckUp = true } label: {
                    Label("Quick check up", systemImage: "checklist").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered).tint(TetherBrand.ember)
            }
            if let today = model.today, !today.isEmpty {
                DetailLink(.effort, source: "effort-ribbon") {
                    TodayRibbon(today: today, sleep: Self.sleepSpan(night), now: Int(Date.now.timeIntervalSince1970),
                                live: model.liveHeartRate, beat: model.collector.lastSampleAt, marks: model.marksToday)
                }
            }
            TodayTiles()
            SyncLine().frame(maxWidth: .infinity)
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
/// On Today the screen zooms out of the card; `source` tells apart two cards that open the same screen.
struct DetailLink<Label: View>: View {
    let detail: TodayDetail
    let source: String
    /// The card's corner radius for the zoom, or nil to leave the source unclipped (the orb's glow).
    let cornerRadius: CGFloat?
    @ViewBuilder var label: Label
    @Environment(\.openDetail) private var openDetail
    @Environment(\.detailZoom) private var zoom

    init(_ detail: TodayDetail, source: String? = nil, cornerRadius: CGFloat? = 24, @ViewBuilder label: () -> Label) {
        self.detail = detail
        self.source = source ?? detail.rawValue
        self.cornerRadius = cornerRadius
        self.label = label()
    }

    var body: some View {
        Group {
            if let openDetail, let zoom {
                Button { openDetail(detail, source) } label: {
                    if let cornerRadius {
                        label.environment(\.opensDetail, true)
                            .matchedTransitionSource(id: source, in: zoom) { $0.clipShape(.rect(cornerRadius: cornerRadius)) }
                    } else {
                        label.environment(\.opensDetail, true).matchedTransitionSource(id: source, in: zoom)
                    }
                }
            } else {
                NavigationLink(value: detail) { label.environment(\.opensDetail, true) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens more detail")
    }
}

extension EnvironmentValues {
    /// Today's zoom namespace, so a card can be the source its detail screen grows from.
    @Entry var detailZoom: Namespace.ID?
    /// Opens a detail screen from a card, remembering which card for the zoom.
    @Entry var openDetail: ((TodayDetail, String) -> Void)?
}
