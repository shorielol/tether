import SwiftUI
import TetherCore

@main
struct TetherMacApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 8) {
                Text("Tether").font(.largeTitle.bold())
                Text("The Mac viewer reads your day files from iCloud Drive. It arrives with the file writer.")
                    .foregroundStyle(TetherBrand.sub)
                Text("Core \(TetherCore.version)").font(.footnote.monospacedDigit()).foregroundStyle(TetherBrand.sub)
            }
            .padding(40)
            .frame(minWidth: 900, minHeight: 600)
            .background(TetherBrand.ink)
            .foregroundStyle(TetherBrand.text)
            .preferredColorScheme(.dark)
        }
    }
}
