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
    enum Section: String { case today, health, trends }

    /// Where a `tether://` link or a screenshot launch lands. Sleep and the strap live behind Today.
    struct Destination {
        var section: Section
        var path: [TodayDetail] = []
        var strap = false
    }

    static func destination(_ name: String) -> Destination? {
        switch name {
        case "today": Destination(section: .today)
        case "health": Destination(section: .health)
        case "trends": Destination(section: .trends)
        case "sleep": Destination(section: .today, path: [.sleep])
        case "strap": Destination(section: .today, strap: true)
        case "marks": Destination(section: .today, path: [.marks])
        case "breathe": Destination(section: .today, path: [.stress, .breathe])
        case "coach": Destination(section: .today, path: [.coach])
        default: nil
        }
    }

    @State private var selection: Section
    @State private var todayPath: [TodayDetail]
    @State private var showingStrap: Bool

    init() {
        var start = Destination(section: .today)
        #if DEBUG
        // Screenshot runs pass `-tether.debugTab health`, `-tether.debugDetail stress` or `-tether.debugSheet strap`.
        let defaults = UserDefaults.standard
        if let name = defaults.string(forKey: "tether.debugTab"), let destination = Self.destination(name) { start = destination }
        if let name = defaults.string(forKey: "tether.debugDetail"), let detail = TodayDetail(rawValue: name) { start.path = [detail] }
        if defaults.string(forKey: "tether.debugSheet") == "strap" { start.strap = true }
        #endif
        _selection = State(initialValue: start.section)
        _todayPath = State(initialValue: start.path)
        _showingStrap = State(initialValue: start.strap)
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.max", value: .today) {
                TodayView(path: $todayPath, showingStrap: $showingStrap)
            }
            Tab("Health", systemImage: "waveform.path.ecg", value: .health) { HealthView() }
            Tab("Trends", systemImage: "chart.bar", value: Section.trends) { TrendsView() }
        }
        // Lock-screen widgets open `tether://today` or `tether://sleep`; the recording card opens `tether://strap`.
        .onOpenURL { url in
            guard url.scheme == "tether", let destination = url.host().flatMap(Self.destination) else { return }
            selection = destination.section
            todayPath = destination.path
            showingStrap = destination.strap
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
