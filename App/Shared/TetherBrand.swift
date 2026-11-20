import SwiftUI

/// Colour tokens from the approved Brand board (dark first).
enum TetherBrand {
    static let ink = Color(red: 10 / 255, green: 12 / 255, blue: 16 / 255)
    static let text = Color(red: 242 / 255, green: 244 / 255, blue: 247 / 255)
    static let sub = Color(red: 163 / 255, green: 169 / 255, blue: 181 / 255)
    static let ember = Color(red: 1, green: 138 / 255, blue: 76 / 255)
    static let dusk = Color(red: 140 / 255, green: 155 / 255, blue: 1)
    static let deep = Color(red: 79 / 255, green: 91 / 255, blue: 208 / 255)
    static let bone = Color(red: 233 / 255, green: 225 / 255, blue: 207 / 255)
    static let good = Color(red: 127 / 255, green: 214 / 255, blue: 168 / 255)
    static let headsUp = Color(red: 242 / 255, green: 184 / 255, blue: 75 / 255)
    static let cardFill = Color.white.opacity(0.05)
    static let cardStroke = Color.white.opacity(0.09)
    static let track = Color.white.opacity(0.10)
    /// Text on an ember button. White on ember fails contrast; this dark brown passes.
    static let onEmber = Color(red: 26 / 255, green: 14 / 255, blue: 6 / 255)
}

/// The one tinted glass button per screen: ember glass with dark text.
struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var fullWidth = true

    init(_ title: String, fullWidth: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.fullWidth = fullWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(TetherBrand.onEmber)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
    }
}

/// Content cards are plain fills. Glass is kept for navigation and the primary buttons.
struct CardStyle: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TetherBrand.cardFill, in: .rect(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(TetherBrand.cardStroke))
    }
}

extension View {
    func card(padding: CGFloat = 18) -> some View { modifier(CardStyle(padding: padding)) }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(TetherBrand.sub)
    }
}

/// A screen title with the small date or context line above it, as on the canvas.
struct ScreenHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(text: eyebrow)
                Text(title).font(.largeTitle.bold())
            }
            Spacer()
            trailing
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String) {
        self.init(eyebrow: eyebrow, title: title) { EmptyView() }
    }
}

/// An honest placeholder for a number that doesn't exist yet.
struct NotYet: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(TetherBrand.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
