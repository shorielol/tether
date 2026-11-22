import SwiftUI

/// A small labelled number, used in detail screens' stat rows.
/// The old Today cards that lived here went away with the 22 Nov redesign (see App/iOS/TodayPieces.swift).
struct Metric: View {
    let label: String
    let value: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(TetherBrand.sub)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            if let note { Text(note).font(.caption2).foregroundStyle(TetherBrand.sub) }
        }
        .accessibilityElement(children: .combine)
    }
}
