import SwiftUI

@main
struct TetherMacApp: App {
    var body: some Scene {
        WindowGroup {
            ScaffoldView(subtitle: "Mac viewer, read-only")
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(.dark)
        }
    }
}
