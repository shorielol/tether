import ServiceManagement
import SwiftUI
import TetherCore

/// First run, as in the approved mockup: four short steps in one centred column. The point of it is
/// step 2, your own heartbeat live on this Mac. The other steps only get you there or keep it going.
struct OnboardingView: View {
    @Environment(MacModel.self) private var model
    @AppStorage(OnboardingKeys.done) private var isDone = false
    @State private var step = OnboardingView.firstStep
    @State private var isLooking = false

    var body: some View {
        let status = StrapStatus.live(model.recorder, folderConnected: model.folderName != nil)
        VStack(spacing: 0) {
            Text("Step \(step) of 4").font(.captionText).foregroundStyle(.secondary)
                .padding(.top, Space.xl)
            Spacer(minLength: Space.xl)
            VStack(spacing: Space.xl) { page(status) }
                .frame(maxWidth: 520)
                .padding(.horizontal, Space.section)
            Spacer(minLength: Space.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: status.bpm != nil) { _, hasBeat in
            // The moment the strap's first beat arrives here, show it.
            if hasBeat && step == 1 { step = 2 }
        }
    }

    @ViewBuilder private func page(_ status: StrapStatus) -> some View {
        switch step {
        case 1: findStrap(status)
        case 2: yourHeart(status)
        case 3: phoneFiles
        default: keepRunning
        }
    }

    // MARK: 1. Find the strap

    @ViewBuilder private func findStrap(_ status: StrapStatus) -> some View {
        LiveTether(holder: status.holder, handedOver: status.handedOver, scale: .large).frame(maxWidth: 440)
        heading("Your strap, on this Mac too",
                "When your iPhone is off, this Mac records your strap's heart rate and passes it to your iPhone later.")
        if isLooking && !status.isPaired {
            StrapPicker(wantedName: model.phoneProfile?.strapName) { strap in model.recorder.pair(with: strap) }
            Button("Set Up the Strap Later") { step = 3 }.buttonStyle(.link)
        } else if status.isPaired {
            Text("Connecting to your strap…").font(.bodyText).foregroundStyle(.secondary)
            Button("Continue") { step = 2 }.buttonStyle(.link)
        } else {
            primary("Find My Strap") { isLooking = true }
            Button("Set Up the Strap Later") { step = 3 }.buttonStyle(.link)
        }
    }

    // MARK: 2. Your heart

    @ViewBuilder private func yourHeart(_ status: StrapStatus) -> some View {
        LiveTether(holder: status.holder, handedOver: status.handedOver, scale: .large).frame(maxWidth: 440)
        if let bpm = status.bpm {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(bpm)").font(.hero).monospacedDigit().contentTransition(.numericText())
                Text("bpm").font(.sectionTitle.weight(.medium)).foregroundStyle(.secondary)
            }
        }
        heading("That's your heart",
                "Live from your strap, straight to this Mac. Every beat is saved here until your iPhone takes it.")
        primary("Continue") { step = 3 }
    }

    // MARK: 3. The iPhone's files

    @ViewBuilder private var phoneFiles: some View {
        Image(systemName: "folder").font(.system(size: 44, weight: .light)).foregroundStyle(Theme.ember)
        heading("Connect to your iPhone's files",
                "Pick the iCloud Drive folder you chose in Tether on your iPhone. Your days and nights come from there.")
        if model.folderName == nil {
            primary("Choose Folder…") { model.chooseFolder() }
            Button("Skip for Now") { step = 4 }.buttonStyle(.link)
        } else {
            Panel { foundRow }
            primary("Continue") { step = 4 }
            Button("Choose a Different Folder…") { model.chooseFolder() }.buttonStyle(.link)
        }
    }

    private var foundRow: some View {
        HStack(spacing: Space.m) {
            Image(systemName: model.phoneProfile == nil ? "clock" : "checkmark.circle.fill")
                .font(.title2).foregroundStyle(model.phoneProfile == nil ? Color.secondary : Theme.good)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.phoneProfile == nil ? "Waiting for your iPhone's first file" : "Found your iPhone's files")
                    .font(.bodyText.weight(.medium))
                Text(foundDetail).font(.captionText).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var foundDetail: String {
        let folder = "iCloud Drive › \(model.folderName ?? "")"
        guard let profile = model.phoneProfile else { return folder }
        var parts = [folder]
        if let strap = profile.strapName { parts.append(strap) }
        if let start = profile.historyStarts {
            parts.append("since " + Date(timeIntervalSince1970: TimeInterval(start)).formatted(.dateTime.day().month(.abbreviated)))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: 4. Keep it running

    @ViewBuilder private var keepRunning: some View {
        Image(systemName: "menubar.rectangle").font(.system(size: 44, weight: .light)).foregroundStyle(Theme.ember)
        heading("Keep it running", "Tether records in the background. Close the window and it carries on from the menu bar.")
        Panel { KeepRunningToggles() }
        primary("Start Recording") { isDone = true }
    }

    // MARK: Pieces

    private func heading(_ title: String, _ sentence: String) -> some View {
        VStack(spacing: Space.s) {
            Text(title).font(.system(size: 28, weight: .semibold)).multilineTextAlignment(.center)
            Text(sentence).font(.bodyText).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
    }

    private static var firstStep: Int {
        #if DEBUG
        let wanted = UserDefaults.standard.integer(forKey: "tether.onboardingStep")
        if (1...4).contains(wanted) { return wanted }
        #endif
        return 1
    }
}

/// The three switches that keep recording going, shared by onboarding and Settings.
struct KeepRunningToggles: View {
    @Environment(MacModel.self) private var model
    @AppStorage(OnboardingKeys.menuBar) private var showsMenuBar = true
    @State private var opensAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var recorder = model.recorder
        VStack(alignment: .leading, spacing: Space.m) {
            toggle("Open Tether at login", "So recording starts when you open the lid.", isOn: Binding(
                get: { opensAtLogin },
                set: { wanted in
                    loginError = LoginItem.set(wanted)
                    opensAtLogin = LoginItem.isEnabled
                }))
            if let loginError {
                Text(loginError).font(.captionText).foregroundStyle(Theme.caution)
            }
            Divider()
            toggle("Show in the menu bar", "Who has the strap, and your heart rate, at a glance.", isOn: $showsMenuBar)
            Divider()
            toggle("Keep this Mac awake while recording", "Only while plugged in or the lid is open.", isOn: $recorder.keepAwake)
        }
    }

    private func toggle(_ title: String, _ detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.bodyText)
                Text(detail).font(.captionText).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }
}

enum OnboardingKeys {
    static let done = "tether.mac.onboarded"
    static let menuBar = "tether.mac.menuBar"
    private static let folder = "tether.folder"

    /// Someone who set Tether up before onboarding existed already has a folder: don't send them through it again.
    static func adoptExistingSetup(_ defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: done) == nil, defaults.data(forKey: folder) != nil else { return }
        defaults.set(true, forKey: done)
    }
}

/// Open at login, through the system's login items list.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns a sentence to show if the change didn't take.
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return "Couldn't change this. Add Tether in System Settings › General › Login Items."
        }
    }
}
