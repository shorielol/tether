import SwiftUI

@main
struct TetherMacApp: App {
    @State private var model = MacModel()

    var body: some Scene {
        WindowGroup {
            MacRootView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 640)
                .preferredColorScheme(.dark)
        }
    }
}
