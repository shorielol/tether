import SwiftUI

@main
struct TetherMacApp: App {
    static let mainWindow = "main"

    @State private var model = MacModel()
    @AppStorage(OnboardingKeys.menuBar) private var showsMenuBar = true

    init() {
        OnboardingKeys.adoptExistingSetup()
    }

    var body: some Scene {
        WindowGroup(id: Self.mainWindow) {
            MacWindowRoot()
                .environment(model)
                // 608 of content plus the 52 pt toolbar: the window's minimum is 980×660.
                .frame(minWidth: 980, minHeight: 608)
        }
        .defaultSize(width: 1240, height: 820)
        .commands { TetherCommands(model: model) }

        Settings {
            MacSettingsView().environment(model)
        }

        MenuBarExtra(isInserted: $showsMenuBar) {
            MenuBarContent().environment(model)
        } label: {
            MenuBarLabel().environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}
