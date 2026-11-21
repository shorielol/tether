import SwiftUI
import TetherCore

struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabScreen {
            ScreenHeader(eyebrow: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)), title: "Today") {
                if model.collector.isPaired { LivePill() }
            }
            if let today = model.today, !today.isEmpty {
                LiveHeroCard(today: today, liveBPM: model.liveHeartRate)
                HStack(alignment: .top, spacing: 14) {
                    EffortCard(today: today)
                    CaloriesCard(today: today)
                }
                .fixedSize(horizontal: false, vertical: true)
                HeartRateDayCard(today: today)
                ZonesCard(today: today)
                StressCard(today: today)
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
                ChargeCard(charge: charge, drivers: (model.latestNight ?? model.lastNight)?.drivers ?? [])
            } else {
                BaselineRow(progress: model.baseline)
            }
            if let saved = model.lastSavedAt, let folder = model.folderName {
                Text("Saved to iCloud Drive / \(folder) at \(saved.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(TetherBrand.sub)
                    .frame(maxWidth: .infinity)
            }
        }
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
