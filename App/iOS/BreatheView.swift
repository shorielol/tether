import SwiftUI
import TetherCore
import StrandAnalytics

/// A minute of slow breathing: in for about four seconds, out for six, paced by NOOP's `BreathPacer`.
/// Your live heart rate shows underneath so you can watch it settle.
struct BreatheView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt: Date?

    static let breathsPerMinute = 6.0
    static let cycles = 6
    private var cues: [BreathCue] { BreathPacer.schedule(bpm: Self.breathsPerMinute, cycles: Self.cycles) }
    private var totalMs: Int { BreathPacer.sessionDurationMs(bpm: Self.breathsPerMinute, cycles: Self.cycles) }

    var body: some View {
        TabScreen {
            TimelineView(.animation(paused: startedAt == nil)) { context in
                let elapsed = startedAt.map { Int(context.date.timeIntervalSince($0) * 1_000) } ?? -1
                session(elapsedMs: elapsed)
            }
            .card()
            Text("Slow breathing, about six breaths a minute, is one of the quickest ways to bring your heart rate down and your HRV up. Breathe in through your nose, and let the out-breath be longer.")
                .font(.subheadline).foregroundStyle(TetherBrand.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .navigationTitle("Breathe")
        .navigationBarTitleDisplayMode(.large)
    }

    @ViewBuilder private func session(elapsedMs: Int) -> some View {
        let running = elapsedMs >= 0 && elapsedMs < totalMs
        let cue = cues.last { $0.offsetMs <= max(elapsedMs, 0) }
        let inhaling = cue?.phase == .inhale
        let progress = phaseProgress(elapsedMs)
        VStack(spacing: 18) {
            ZStack {
                Circle().stroke(TetherBrand.cardStroke, lineWidth: 2)
                Circle()
                    .fill(TetherBrand.ember.opacity(0.25))
                    .scaleEffect(reduceMotion || !running ? 0.75 : (inhaling ? 0.45 + 0.55 * progress : 1 - 0.55 * progress))
                Text(running ? (inhaling ? "Breathe in" : "Breathe out") : (elapsedMs >= totalMs ? "Done" : "Ready"))
                    .font(.title2.weight(.semibold))
            }
            .frame(width: 220, height: 220)
            .accessibilityElement(children: .combine)
            if running {
                Text("\(max(0, (totalMs - elapsedMs) / 1_000 + 1)) s left").font(.subheadline).monospacedDigit()
                    .foregroundStyle(TetherBrand.sub)
            } else {
                Button(elapsedMs >= totalMs ? "Again" : "Start a minute") { startedAt = .now }
                    .buttonStyle(.borderedProminent).tint(TetherBrand.ember)
            }
            if let bpm = model.liveHeartRate {
                Text("Heart rate \(bpm) bpm").font(.subheadline).monospacedDigit().foregroundStyle(TetherBrand.sub)
            }
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.impact(weight: .light), trigger: cue?.offsetMs ?? -1) { _, _ in running }
    }

    /// How far through the current inhale or exhale, 0…1.
    private func phaseProgress(_ elapsedMs: Int) -> Double {
        guard elapsedMs >= 0, let index = cues.lastIndex(where: { $0.offsetMs <= elapsedMs }) else { return 0 }
        let start = cues[index].offsetMs
        let end = index + 1 < cues.count ? cues[index + 1].offsetMs : totalMs
        return min(1, Double(elapsedMs - start) / Double(max(1, end - start)))
    }
}
