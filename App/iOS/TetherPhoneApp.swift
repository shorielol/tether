import SwiftUI

@main
struct TetherPhoneApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(TetherBrand.ember)
                .task { model.startTodayUpdates() }
        }
        .onChange(of: scenePhase) { _, phase in
            model.refreshDeviceState()
            if phase == .background { Task { await model.collector.flush(); await model.syncFolder(force: true) } }
            if phase == .active, model.onboarded { Task { await model.scheduleExpiryReminder() } }
            if phase == .active { model.startTodayUpdates() } else { model.stopTodayUpdates() }
        }
    }
}
