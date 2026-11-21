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
            BaselineRow(progress: model.baseline)
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

/// Charge and sleep need nights; until then they take one quiet row instead of the whole screen.
private struct BaselineRow: View {
    let progress: BaselineProgress

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(TetherBrand.track, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: Double(progress.scoredNights) / Double(BaselineProgress.chargeNights))
                    .stroke(TetherBrand.ember, style: .init(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(progress.chargeLabel) · \(progress.scoredNights)/\(BaselineProgress.chargeNights)")
                    .font(.subheadline.weight(.semibold))
                Text("Sleep and Charge are scored each morning from the night before.")
                    .font(.caption).foregroundStyle(TetherBrand.sub)
            }
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}
