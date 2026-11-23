import AppKit
import SwiftUI
import TetherCore

/// The window's root: first run shows onboarding in place of the app, never as a sheet over it.
struct MacWindowRoot: View {
    @AppStorage(OnboardingKeys.done) private var isDone = false

    var body: some View {
        if isDone { MacRootView() } else { OnboardingView() }
    }
}

// MARK: - Menu commands

/// Go menu: the four pages on ⌘1–⌘4, days on ⌘[ and ⌘], Today on ⌘T. The folder lives under File.
struct TetherCommands: Commands {
    let model: MacModel
    @FocusedValue(\.macSection) private var section

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Choose iPhone Folder…") { model.chooseFolder() }
        }
        CommandMenu("Go") {
            ForEach(Array(MacSection.allCases.enumerated()), id: \.element) { index, page in
                Button(page.rawValue) { section?.wrappedValue = page }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .disabled(section == nil)
            }
            Divider()
            Button("Previous Day") { model.moveDay(by: -1) }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!dated || !model.canGoBack)
            Button("Next Day") { model.moveDay(by: 1) }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!dated || model.isShowingToday)
            Button("Today") { model.goToToday() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(!dated || model.isShowingToday)
        }
    }

    /// Day moves only mean something on the Day and Sleep pages.
    private var dated: Bool { section?.wrappedValue.isDated ?? false }
}

// MARK: - Settings

struct MacSettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                Form { KeepRunningToggles() }.formStyle(.grouped)
            }
            Tab("iPhone", systemImage: "iphone") {
                Form { PhoneFolderSettings() }.formStyle(.grouped)
            }
        }
        .frame(width: 480, height: 300)
    }
}

private struct PhoneFolderSettings: View {
    @Environment(MacModel.self) private var model

    var body: some View {
        LabeledContent("Folder") {
            Text(model.folderName.map { "iCloud Drive › \($0)" } ?? "Not chosen").foregroundStyle(.secondary)
        }
        LabeledContent("Last file from iPhone") {
            if let synced = model.lastSyncedAt {
                Text(synced, format: .relative(presentation: .named)).foregroundStyle(.secondary)
            } else {
                Text("None yet").foregroundStyle(.secondary)
            }
        }
        if let error = model.readError {
            Text(error).font(.captionText).foregroundStyle(Theme.caution)
        }
        Button(model.folderName == nil ? "Choose Folder…" : "Choose a Different Folder…") { model.chooseFolder() }
        Text("Pick the same iCloud Drive folder you chose in Tether on your iPhone. This Mac only reads it, and writes its own recordings to the inbox inside.")
            .font(.captionText).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Menu bar

struct MenuBarLabel: View {
    @Environment(MacModel.self) private var model

    var body: some View {
        let status = StrapStatus.live(model.recorder, folderConnected: model.folderName != nil)
        if let bpm = status.bpm {
            Label("\(bpm)", systemImage: "heart.fill").labelStyle(.titleAndIcon).monospacedDigit()
        } else {
            Image(systemName: "heart")
        }
    }
}

struct MenuBarContent: View {
    @Environment(MacModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let status = StrapStatus.live(model.recorder, folderConnected: model.folderName != nil)
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                LiveTether(holder: status.holder, handedOver: status.handedOver).frame(width: 72)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.toolbarText).font(.bodyText.weight(.semibold)).monospacedDigit()
                    Text(status.sentence).font(.captionText).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let night = model.lastNight {
                Divider()
                HStack(spacing: Space.xl) {
                    figure("Charge", night.charge.map { "\(Int($0.rounded()))%" } ?? "Learning")
                    figure("Sleep", night.totalSleepMin.map(DayLine.duration) ?? "–")
                    if let rhr = night.restingHR { figure("Resting", "\(rhr) bpm") }
                }
            }
            Divider()
            Button("Open Tether") {
                openWindow(id: TetherMacApp.mainWindow)
                NSApp.activate()
            }
            SettingsLink { Text("Settings…") }
            Button("Quit Tether") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .padding(Space.l)
        .frame(width: 300, alignment: .leading)
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.captionText).foregroundStyle(.secondary)
            Text(value).font(.bodyText.weight(.semibold)).monospacedDigit()
        }
    }
}
