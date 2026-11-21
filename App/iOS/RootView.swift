import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.onboarded {
                MainTabs()
            } else {
                PairingFlow()
            }
        }
        .background(TetherBrand.ink)
        .foregroundStyle(TetherBrand.text)
    }
}

struct MainTabs: View {
    enum Section: String { case today, sleep, trends, strap }

    #if DEBUG
    // Screenshot runs pass `-tether.debugTab strap` to open on a given tab.
    @State private var selection = Section(rawValue: UserDefaults.standard.string(forKey: "tether.debugTab") ?? "") ?? .today
    #else
    @State private var selection = Section.today
    #endif

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.max", value: .today) { TodayView() }
            Tab("Sleep", systemImage: "moon", value: .sleep) { SleepView() }
            Tab("Trends", systemImage: "chart.bar", value: .trends) { TrendsView() }
            Tab("Strap", systemImage: "heart", value: Section.strap) { StrapView() }
        }
        // Lock-screen widgets open `tether://sleep` or `tether://today`.
        .onOpenURL { url in
            if url.scheme == "tether", let section = url.host().flatMap(Section.init(rawValue:)) {
                selection = section
            }
        }
    }
}

/// Shared scroll container so every tab has the same margins and background.
struct TabScreen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) { content }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        #if DEBUG
        // Screenshot runs pass `-tether.debugAnchor bottom` to open a tab scrolled to the end.
        .defaultScrollAnchor(UserDefaults.standard.string(forKey: "tether.debugAnchor") == "bottom" ? .bottom : .top)
        #endif
        .background(TetherBrand.ink)
    }
}
