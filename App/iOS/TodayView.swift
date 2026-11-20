import SwiftUI
import TetherCore

struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabScreen {
            ScreenHeader(eyebrow: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)), title: "Today") {
                if model.collector.isPaired { LivePill() }
            }
            ChargeCard(progress: model.baseline)
            HStack(spacing: 14) {
                NotYet(title: "Sleep", detail: "Your first night shows here the morning after.").card()
                NotYet(title: "Effort", detail: "Builds through the day once you're recording.").card()
            }
            .fixedSize(horizontal: false, vertical: true)
            RecordingCard()
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
        let hr = collector.heartRate.map { "\($0) bpm" } ?? "Live"
        return collector.batteryPercent.map { "\(hr) · \($0)%" } ?? hr
    }
}

private struct ChargeCard: View {
    let progress: BaselineProgress

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(TetherBrand.track, lineWidth: 11)
                Circle()
                    .trim(from: 0, to: Double(progress.scoredNights) / Double(BaselineProgress.chargeNights))
                    .stroke(TetherBrand.ember.opacity(0.45), style: .init(lineWidth: 11, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(min(progress.scoredNights, BaselineProgress.chargeNights))/\(BaselineProgress.chargeNights)")
                        .font(.title2.bold()).monospacedDigit()
                    Text("nights").font(.caption).foregroundStyle(TetherBrand.sub)
                }
            }
            .frame(width: 104, height: 104)
            .accessibilityElement()
            .accessibilityLabel("\(progress.scoredNights) of \(BaselineProgress.chargeNights) baseline nights recorded")
            NotYet(title: progress.chargeLabel,
                   detail: "Charge compares each night with your own baseline, so it waits until it has one.")
        }
        .card()
    }
}

private struct RecordingCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let pairedAt = model.collector.pairedAt {
            let since = Date(timeIntervalSince1970: TimeInterval(pairedAt))
            NotYet(title: "Recording since \(since.formatted(date: .abbreviated, time: .shortened))",
                   detail: "Heart rate and R-R are saved on this phone every 30 seconds.")
                .card()
        } else {
            NotYet(title: "Not recording yet", detail: "Pair your strap from the Strap tab to start your history.")
                .card()
        }
    }
}
