import SwiftUI
import TetherCore

struct SleepView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabScreen {
            ScreenHeader(eyebrow: eyebrow, title: "Sleep")
            if let night = model.lastNight {
                NightHeroCard(night: night)
                HypnogramCard(night: night)
                NightVitalsCard(night: night)
                ChargeOrCountdown(night: model.latestNight ?? night, progress: model.baseline)
                RecentNightsCard(nights: model.nights)
            } else {
                NotYet(title: "No nights yet",
                       detail: "Wear the strap to bed with the phone charging nearby. Your night is scored when you open Tether in the morning.")
                    .card()
                NotYet(title: "How stages are found",
                       detail: "Tether reads heart rate and R-R only, so sleep and its stages are estimated from heart rate and labelled that way.")
                    .card()
            }
        }
    }

    private var eyebrow: String {
        guard let end = model.lastNight?.sleepEnd else { return "Last night" }
        return "Night ending " + Date(timeIntervalSince1970: TimeInterval(end)).formatted(.dateTime.weekday(.wide).day().month())
    }
}

