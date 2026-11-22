import SwiftUI
import TetherCore

/// Last night in depth, opened from the Sleep score on Today: how long, the stages, and the last few nights.
/// Its vitals live on Recovery and Health, so they aren't repeated here.
struct SleepView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabScreen {
            if let night = model.lastNight {
                DetailHero(label: eyebrow, meaning: meaning(night)) {
                    Text(SleepFormat.duration(minutes: night.totalSleepMin))
                }
                if let coach = model.sleepCoach { SleepCoachCard(coach: coach) }
                HypnogramCard(night: night)
                RecentNightsCard(nights: model.nights)
                if let breakdown = ScoreBreakdown.sleep(night) {
                    BreakdownCard(title: "How you got to \(DayLine.duration(breakdown.total)) asleep",
                                  startTitle: "In bed", startDetail: "from falling asleep to waking up",
                                  totalTitle: "Asleep", unit: "", breakdown: breakdown,
                                  footnote: "Awake counts every stretch your heart rate and movement say you were up, even ones too short to remember.",
                                  format: DayLine.duration)
                }
            } else {
                NotYet(title: "No nights yet",
                       detail: "Wear the strap to bed with the phone charging nearby. Your night is scored when you open Tether in the morning.")
                    .card()
            }
            HowItsWorkedOut(text: "Sleep is found from your heart rate settling and staying low. Stages are estimated from heart rate, its beat-to-beat changes and, when the strap has sent it, your movement, so they're labelled as estimates. Asleep is the time between falling asleep and waking, minus the minutes you were awake. Your normal is the middle half of your earlier nights.")
        }
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.large)
    }

    private var eyebrow: String {
        guard let end = model.lastNight?.sleepEnd else { return "Last night" }
        return "Night ending " + Date(timeIntervalSince1970: TimeInterval(end)).formatted(.dateTime.weekday(.wide).day().month())
    }

    /// When, how much of the time in bed was sleep, and how it sits against your normal.
    private func meaning(_ night: NightSummary) -> String {
        var parts = ["\(SleepFormat.time(night.sleepStart)) – \(SleepFormat.time(night.sleepEnd))"]
        if let efficiency = night.efficiency { parts.append("\(Int((efficiency * 100).rounded()))% asleep in bed") }
        let band = NormalBand(past: model.nights.filter { $0.day < night.day }.compactMap(\.totalSleepMin))
        if let band, let minutes = night.totalSleepMin {
            parts.append(minutes < band.low ? "short of your normal" : minutes > band.high ? "longer than your normal" : "in your normal")
        }
        return parts.joined(separator: " · ")
    }
}
