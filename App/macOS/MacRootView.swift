import SwiftUI
import TetherCore

enum MacSection: String, CaseIterable, Identifiable {
    case day = "Day", sleep = "Sleep", trends = "Trends", strap = "Strap"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .day: "sun.horizon"
        case .sleep: "moon.zzz"
        case .trends: "chart.xyaxis.line"
        case .strap: "heart.circle"
        }
    }
    /// Day and Sleep follow the date navigator; Trends and Strap don't.
    var isDated: Bool { self == .day || self == .sleep }
}

struct MacRootView: View {
    @Environment(MacModel.self) private var model
    @SceneStorage("tether.section") private var section: MacSection = .day
    @AppStorage("tether.trends.measure") private var trendMeasure: TrendMeasure = .charge
    @AppStorage("tether.trends.days") private var trendDays = 14

    var body: some View {
        NavigationSplitView {
            List(MacSection.allCases, selection: Binding(get: { section }, set: { section = $0 ?? .day })) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
            .safeAreaInset(edge: .bottom) { SyncStatus().padding(.horizontal, 16).padding(.bottom, 14) }
        } detail: {
            PageScaffold { page }
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            .toolbar { toolbar }
        }
        .focusedSceneValue(\.macSection, $section)
        #if DEBUG
        .onAppear {
            // `-tether.fixtureSection sleep` opens a page directly, for screenshots without clicks.
            if DebugFixture.isOn, let name = UserDefaults.standard.string(forKey: "tether.fixtureSection"),
               let wanted = MacSection.allCases.first(where: { $0.rawValue.lowercased() == name }) {
                section = wanted
            }
        }
        #endif
    }

    @ViewBuilder private var page: some View {
        switch section {
        case .day: DayView(openSleep: { section = .sleep })
        case .sleep: MacSleepView()
        case .trends: TrendsView()
        case .strap: StrapPane()
        }
    }

    private var title: String {
        guard section.isDated else { return section.rawValue }
        if model.isShowingToday { return section == .sleep ? "Last night" : "Today" }
        return model.selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private var subtitle: String {
        guard section.isDated else { return "" }
        return model.isShowingToday ? model.selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide)) : ""
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if section.isDated {
            ToolbarItemGroup(placement: .navigation) {
                Button { model.moveDay(by: -1) } label: { Label("Previous Day", systemImage: "chevron.left") }
                    .disabled(!model.canGoBack)
                    .help("Previous day")
                Button { model.moveDay(by: 1) } label: { Label("Next Day", systemImage: "chevron.right") }
                    .disabled(model.isShowingToday)
                    .help("Next day")
            }
            ToolbarItem(placement: .navigation) {
                Button("Today") { model.goToToday() }
                    .disabled(model.isShowingToday)
                    .help("Go to today")
            }
        }
        if section == .trends {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: Space.m) {
                    Picker("Measure", selection: $trendMeasure) {
                        ForEach(TrendMeasure.allCases) { Text($0.shortTitle).tag($0) }
                    }
                    Picker("Range", selection: $trendDays) {
                        Text("14 days").tag(14)
                        Text("30 days").tag(30)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
        ToolbarItem(placement: .primaryAction) { HolderStatus() }
    }
}

/// The live tether plus a few words: who has the strap right now.
struct HolderStatus: View {
    @Environment(MacModel.self) private var model

    var body: some View {
        let status = StrapStatus.live(model.recorder, folderConnected: model.folderName != nil)
        HStack(spacing: 10) {
            LiveTether(holder: status.holder, handedOver: status.handedOver)
                .frame(width: 92)
            Text(status.toolbarText)
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .contentTransition(.numericText())
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }
}

/// Sidebar footer: when the iPhone last wrote, in plain text.
private struct SyncStatus: View {
    @Environment(MacModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let synced = model.lastSyncedAt {
                Text("Synced from iPhone").font(.caption.weight(.medium))
                Text(synced, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
            } else {
                Text(model.folderName == nil ? "Not connected to your iPhone" : "Waiting for your iPhone's first file")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.readError ?? model.recorder.exportError {
                Text(error).font(.caption).foregroundStyle(Theme.caution).lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Focused values for menu commands

extension FocusedValues {
    @Entry var macSection: Binding<MacSection>?
}
