import SwiftUI

struct SleepView: View {
    var body: some View {
        TabScreen {
            ScreenHeader(eyebrow: "Last night", title: "Sleep")
            NotYet(title: "No nights yet",
                   detail: "Wear the strap to bed with the phone charging nearby. Your first night shows here the next morning.")
                .card()
            NotYet(title: "How stages are found",
                   detail: "Tether reads heart rate and R-R only, so sleep stages are estimates and are labelled that way.")
                .card()
        }
    }
}
