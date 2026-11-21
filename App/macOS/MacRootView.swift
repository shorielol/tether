import SwiftUI
import TetherCore

enum MacSection: String, CaseIterable, Identifiable {
    case today = "Today", sleep = "Sleep", trends = "Trends", strap = "Strap"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .sleep: "moon"
        case .trends: "chart.bar"
        case .strap: "heart"
        }
    }
}

struct MacRootView: View {
    @Environment(MacModel.self) private var model
    @State private var section: MacSection? = .today

    var body: some View {
        NavigationSplitView {
            List(MacSection.allCases, selection: $section) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .safeAreaInset(edge: .bottom) { SyncFooter().padding(12) }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { detail }
                    .padding(28)
                    .frame(maxWidth: 1_100, alignment: .leading)
            }
            .background(TetherBrand.ink)
        }
        .foregroundStyle(TetherBrand.text)
        .tint(TetherBrand.ember)
    }

    @ViewBuilder private var detail: some View {
        if model.folderName == nil {
            ChooseFolderCard()
        } else {
            switch section ?? .today {
            case .today: MacTodayView()
            case .sleep: MacSleepView()
            case .trends:
                ScreenHeader(eyebrow: "Last 14 days", title: "Trends")
                NotYet(title: "Trends are next on the roadmap",
                       detail: "Charge, hours asleep, HRV and resting heart rate over 14 and 30 days.").card()
            case .strap:
                ScreenHeader(eyebrow: "WHOOP 5.0", title: "Strap")
                NotYet(title: "Connecting from this Mac comes next",
                       detail: "Tether for Mac will hold the strap whenever your iPhone isn't, and send what it records to your phone.").card()
            }
        }
    }
}

private struct ChooseFolderCard: View {
    @Environment(MacModel.self) private var model

    var body: some View {
        ScreenHeader(eyebrow: "Tether for Mac", title: "Pair with your iPhone")
        VStack(alignment: .leading, spacing: 12) {
            NotYet(title: "Pick the folder your iPhone writes to",
                   detail: "On the iPhone: Strap → Your files → Choose folder, in iCloud Drive. Then pick the same folder here. Tether for Mac reads one file per day from it.")
            PrimaryButton("Choose folder", fullWidth: false) { model.chooseFolder() }
        }
        .card()
        if let error = model.readError {
            Text(error).font(.callout).foregroundStyle(TetherBrand.headsUp)
        }
    }
}

private struct SyncFooter: View {
    @Environment(MacModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let synced = model.lastSyncedAt {
                Label("Synced from iPhone", systemImage: "circle.fill")
                    .labelStyle(.titleAndIcon).font(.caption.weight(.semibold))
                    .foregroundStyle(TetherBrand.good)
                Text("\(synced.formatted(.relative(presentation: .named))) · iCloud Drive / \(model.folderName ?? "")")
                    .font(.caption).foregroundStyle(TetherBrand.sub)
            } else {
                Text(model.folderName == nil ? "Not paired with your iPhone yet" : "Waiting for your iPhone's first file")
                    .font(.caption).foregroundStyle(TetherBrand.sub)
            }
            if model.folderName != nil {
                Button("Change folder") { model.chooseFolder() }
                    .buttonStyle(.link).font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 12))
    }
}

private struct MacTodayView: View {
    @Environment(MacModel.self) private var model
    private let columns = [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)]

    var body: some View {
        ScreenHeader(eyebrow: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)), title: "Today")
        if let today = model.today, !today.isEmpty {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                if let night = model.lastNight, let charge = night.charge {
                    ChargeCard(charge: charge, drivers: night.drivers)
                } else {
                    BaselineRow(progress: model.baseline)
                }
                HStack(alignment: .top, spacing: 16) {
                    EffortCard(today: today)
                    CaloriesCard(today: today)
                }
                .fixedSize(horizontal: false, vertical: true)
                HeartRateDayCard(today: today)
                ZonesCard(today: today)
                StressCard(today: today)
                VStack(spacing: 16) {
                    if let night = model.lastNight { LastNightRow(night: night) }
                    CoverageRow(today: today)
                }
            }
        } else {
            NotYet(title: "Nothing from today yet",
                   detail: "Your iPhone writes today's file every 15 minutes while Tether is open, and when you leave the app.").card()
        }
    }
}

private struct MacSleepView: View {
    @Environment(MacModel.self) private var model
    private let columns = [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)]

    var body: some View {
        ScreenHeader(eyebrow: "Last night", title: "Sleep")
        if let night = model.lastNight {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                NightHeroCard(night: night)
                ChargeOrCountdown(night: night, progress: model.baseline)
                HypnogramCard(night: night)
                NightVitalsCard(night: night)
                RecentNightsCard(nights: model.nights)
            }
        } else {
            NotYet(title: "No nights yet", detail: "Nights appear here after your iPhone scores them each morning.").card()
        }
    }
}
