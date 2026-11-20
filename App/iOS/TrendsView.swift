import SwiftUI
import TetherCore

struct TrendsView: View {
    var body: some View {
        TabScreen {
            ScreenHeader(eyebrow: "Last 14 days", title: "Trends")
            NotYet(title: "Trends start after a week",
                   detail: "Charge, hours asleep, HRV and resting heart rate appear here once there are 7 scored nights.")
                .card()
        }
    }
}
