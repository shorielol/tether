import SwiftUI
import TetherCore

/// The screens a Today card opens.
enum TodayDetail: String, Hashable {
    case stress, effort, recovery
}

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var path = TodayView.initialPath

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
        }
    }

    private var content: some View {
        TabScreen {
            ScreenHeader(eyebrow: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)), title: "Today") {
                if model.collector.isPaired { LivePill() }
            }
            if let today = model.today, !today.isEmpty {
                LiveHeroCard(today: today, liveBPM: model.liveHeartRate)
                HStack(alignment: .top, spacing: 14) {
                    DetailLink(.effort) { EffortCard(today: today) }
                    CaloriesCard(today: today)
                }
                .fixedSize(horizontal: false, vertical: true)
                DetailLink(.effort) { HeartRateDayCard(today: today) }
                DetailLink(.effort) { ZonesCard(today: today) }
                DetailLink(.stress) { StressCard(today: today) }
                CoverageRow(today: today)
            } else if model.collector.isPaired {
                NotYet(title: "Collecting your first minutes",
                       detail: "Live numbers, Effort and your heart-rate chart appear here within a minute of recording.")
                    .card()
            } else {
                NotYet(title: "Not recording yet", detail: "Pair your strap from the Strap tab to start your history.")
                    .card()
            }
            if let night = model.lastNight {
                LastNightRow(night: night)
            }
            if let charge = (model.latestNight ?? model.lastNight)?.charge {
                DetailLink(.recovery) {
                    ChargeCard(charge: charge, drivers: (model.latestNight ?? model.lastNight)?.drivers ?? [])
                }
            } else {
                DetailLink(.recovery) { BaselineRow(progress: model.baseline) }
            }
            if let saved = model.lastSavedAt, let folder = model.folderName {
                Text("Saved to iCloud Drive / \(folder) at \(saved.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(TetherBrand.sub)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private static var initialPath: [TodayDetail] {
        #if DEBUG
        // Screenshot runs pass `-tether.debugDetail stress` to open a detail screen directly.
        if let name = UserDefaults.standard.string(forKey: "tether.debugDetail"), let detail = TodayDetail(rawValue: name) {
            return [detail]
        }
        #endif
        return []
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

private struct LivePill: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let collector = model.collector
        HStack(spacing: 6) {
            Image(systemName: "heart.fill").foregroundStyle(TetherBrand.ember)
                .symbolEffect(.bounce, value: collector.lastSampleAt)
            Text(collector.link == .connected ? live(collector) : "Not connected")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06), in: .capsule)
        .accessibilityElement(children: .combine)
    }

    private func live(_ collector: LiveCollector) -> String {
        collector.batteryPercent.map { "Live · \($0)%" } ?? "Live"
    }
}
