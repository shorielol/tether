import SwiftUI
import TetherCore

/// Colour tokens from the approved Brand board (dark first).
enum TetherBrand {
    static let ink = Color(red: 10 / 255, green: 12 / 255, blue: 16 / 255)
    static let text = Color(red: 242 / 255, green: 244 / 255, blue: 247 / 255)
    static let sub = Color(red: 163 / 255, green: 169 / 255, blue: 181 / 255)
    static let ember = Color(red: 1, green: 138 / 255, blue: 76 / 255)
    static let dusk = Color(red: 140 / 255, green: 155 / 255, blue: 1)
    static let deep = Color(red: 79 / 255, green: 91 / 255, blue: 208 / 255)
    static let bone = Color(red: 233 / 255, green: 225 / 255, blue: 207 / 255)
    static let navy = Color(red: 27 / 255, green: 31 / 255, blue: 58 / 255)
    static let good = Color(red: 127 / 255, green: 214 / 255, blue: 168 / 255)
    static let headsUp = Color(red: 242 / 255, green: 184 / 255, blue: 75 / 255)
    static let cardFill = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.12)
    static let track = Color.white.opacity(0.10)
    /// Text on an ember button. White on ember fails contrast; this dark brown passes.
    static let onEmber = Color(red: 26 / 255, green: 14 / 255, blue: 6 / 255)

    /// Zones ramp Dusk → Bone → Ember: lightness and hue both change, and there's no red/green.
    static func zone(_ number: Int) -> Color {
        switch number {
        case 1: dusk
        case 2: Color(red: 187 / 255, green: 188 / 255, blue: 231 / 255)
        case 3: bone
        case 4: Color(red: 244 / 255, green: 180 / 255, blue: 140 / 255)
        case 5: ember
        default: track
        }
    }

    static let zoneNames = ["Below zones", "Easy", "Steady", "Aerobic", "Threshold", "Max"]

    /// Charge's three zones. Checked against the dark surfaces for contrast and colour-blind
    /// separation; always shown with the zone's name, never colour alone.
    static func charge(_ zone: ChargeZone) -> Color {
        switch zone {
        case .green: good
        case .yellow: headsUp
        case .red: Color(red: 1, green: 112 / 255, blue: 136 / 255)
        }
    }
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

/// Aurora glass: a faint white fill over the backdrop, with an edge that catches light at the top.
/// No blur: the backdrop is already soft, and a material per card costs frames while scrolling.
struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(TetherBrand.cardFill, in: shape)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.20), Color.white.opacity(0.06)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            )
            .contentShape(shape)
    }
}

/// Content cards are Aurora glass panels with the standard padding.
struct CardStyle: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(GlassPanel())
    }
}

extension View {
    func card(padding: CGFloat = 18) -> some View { modifier(CardStyle(padding: padding)) }
    func glass(cornerRadius: CGFloat = 24) -> some View { modifier(GlassPanel(cornerRadius: cornerRadius)) }
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

extension EnvironmentValues {
    /// Set on a card wrapped in a link to a detail screen, so it shows a chevron.
    @Entry var opensDetail = false
}

/// The small chevron on a card that opens a detail screen. Hidden everywhere else.
struct DetailChevron: View {
    @Environment(\.opensDetail) private var opensDetail

    var body: some View {
        if opensDetail {
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(TetherBrand.sub)
                .accessibilityHidden(true)
        }
    }
}
