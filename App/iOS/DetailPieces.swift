import SwiftUI

/// The top of every detail screen, in one shape: what it is, the number, and one line on what it means.
struct DetailHero<Value: View>: View {
    let label: String
    let meaning: String?
    @ViewBuilder var value: Value

    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: label)
            value
                .font(.system(size: size, weight: .bold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5)
            if let meaning {
                Text(meaning).font(.body).foregroundStyle(TetherBrand.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// Method notes, folded away at the bottom of a detail screen. Show the maths fills this in later.
struct HowItsWorkedOut: View {
    let text: String

    @State private var open = false

    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            Text(text)
                .font(.subheadline).foregroundStyle(TetherBrand.sub)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
        } label: {
            Label { Text("How this is worked out").font(.subheadline.weight(.semibold)) } icon: {
                Image(systemName: "info.circle").foregroundStyle(TetherBrand.sub)
            }
            .foregroundStyle(TetherBrand.text)
        }
        .tint(TetherBrand.sub)
        .card()
    }
}
