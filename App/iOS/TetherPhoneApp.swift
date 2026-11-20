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
        }
        .onChange(of: scenePhase) { _, phase in
            model.refreshDeviceState()
            if phase == .background { Task { await model.collector.flush() } }
            if phase == .active, model.onboarded { Task { await model.scheduleExpiryReminder() } }
        }
    }
}
