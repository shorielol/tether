import SwiftUI
import TetherCore

/// Phase 0 placeholder so both apps build and launch. Replaced by the real screens in Phase 4.
struct ScaffoldView: View {
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Text("Tether").font(.largeTitle.bold())
            Text(subtitle).foregroundStyle(.secondary)
            Text("Core \(TetherCore.version)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TetherBrand.ink)
        .foregroundStyle(TetherBrand.text)
    }
}
