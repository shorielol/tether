import AppKit
import SwiftUI
import TetherCore

/// Tether for Mac's tokens. Surfaces and text are the system's, so the app sits in both Light and
/// Dark like any Mac app. Brand colour is kept for data: Ember for heart rate and Charge, Dusk for
/// sleep. Every step below was run through the dataviz palette validator against the Mac's window
/// surfaces (#FFFFFF light, #1E1E1E dark) and passes: lightness band, chroma, CVD separation and
/// contrast for the pair, and one-hue monotone ramps for the zones.
enum Theme {
    static let ember = Color(light: 0xCA5A1C, dark: 0xDF702E)
    static let dusk = Color(light: 0x575CBC, dark: 0x7F88E5)
    /// Status only, always with a label: "Synced", "Recording".
    static let good = Color(light: 0x2E8B5E, dark: 0x7FD6A8)
    static let caution = Color(light: 0xA86A00, dark: 0xF2B84B)

    static let sleepBand = dusk.opacity(0.16)
    static let macHatch = Color.secondary.opacity(0.35)
    static let grid = Color.secondary.opacity(0.18)
    static let hairline = Color(nsColor: .separatorColor)
    static let groupFill = Color(nsColor: .quaternarySystemFill)

    /// Zones 1–5 as one Ember ramp. Light mode runs pale→deep; Dark mode runs deep→pale, so the
    /// higher zone is always the one that stands out from the window.
    static func zone(_ number: Int) -> Color {
        let light: [UInt32] = [0xE5A06A, 0xD9834B, 0xCC652A, 0xB94A0B, 0x9C3209]
        let dark: [UInt32] = [0xCB5216, 0xE27135, 0xEE9460, 0xF6B386, 0xF8D3B5]
        guard (1...5).contains(number) else { return grid }
        return Color(light: light[number - 1], dark: dark[number - 1])
    }

    static let zoneNames = ["", "Easy", "Steady", "Aerobic", "Threshold", "Max"]

    /// Charge's three zones, validated in both modes (contrast, colour-blind and normal-vision
    /// separation). Always shown with the zone's name beside it.
    static func charge(_ zone: ChargeZone) -> Color {
        switch zone {
        case .green: good
        case .yellow: caution
        case .red: Color(light: 0xC8264B, dark: 0xFF7088)
        }
    }
}

extension Color {
    /// A colour that follows the window's appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua, .accessibilityHighContrastDarkAqua,
                                                     .accessibilityHighContrastAqua])
                .map { $0 == .darkAqua || $0 == .accessibilityHighContrastDarkAqua } ?? false
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Spacing and type (the approved spec: nothing off these scales)

enum Space {
    static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16
    static let xl: CGFloat = 24, xxl: CGFloat = 32, section: CGFloat = 48, huge: CGFloat = 64
    /// Content column: 960 pt of content plus 48 pt margins each side.
    static let contentMax: CGFloat = 960
    static let margin: CGFloat = 48
}

extension Font {
    /// Hero numbers: SF Pro Expanded, semibold. Wide figures read as instrument readouts, and the
    /// width axis keeps them distinct without a second typeface.
    static func readout(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold).width(.expanded)
    }

    /// One per page, the focal number.
    static let hero = readout(64)
    /// Secondary numbers, at most four in a row.
    static let metric = readout(28)
    static let sectionTitle = Font.system(size: 15, weight: .semibold)
    static let label = Font.system(size: 13, weight: .semibold)
    static let bodyText = Font.system(size: 13)
    static let captionText = Font.system(size: 11)
}

// MARK: - Building blocks

/// The page's one big number: label above, value, one line of context below.
struct HeroNumber: View {
    let label: String
    let value: String
    var unit: String?
    var caption: String?
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(label).font(.label).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.hero).monospacedDigit().foregroundStyle(tint)
                    .contentTransition(.numericText()).lineLimit(1)
                if let unit { Text(unit).font(.sectionTitle.weight(.medium)).foregroundStyle(.secondary) }
            }
            if let caption {
                Text(caption).font(.bodyText).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A secondary number: label, value, one short caption. Captions are written to fit one line.
struct MetricView: View {
    let label: String
    let value: String
    var unit: String?
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.label).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.metric).monospacedDigit().contentTransition(.numericText()).lineLimit(1)
                if let unit { Text(unit).font(.bodyText.weight(.medium)).foregroundStyle(.secondary) }
            }
            if let caption {
                Text(caption).font(.captionText).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            }
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// The only container: a quiet fill for secondary content. Never nested, never around a hero or the main chart.
struct Panel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) { content }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Theme.groupFill, in: .rect(cornerRadius: 14))
    }
}

/// A section title with whatever belongs on its right: a legend, a summary, a link.
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.l) {
            Text(title).font(.sectionTitle)
            Spacer(minLength: Space.l)
            trailing.font(.captionText).foregroundStyle(.secondary)
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) { self.init(title: title) { EmptyView() } }
}

/// Every page sits in the same column: 960 pt of content, 48 pt margins, 48 pt between sections.
struct PageScaffold<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) { content }
                .padding(.horizontal, Space.margin)
                .padding(.top, Space.xxl)
                .padding(.bottom, Space.section)
                .frame(maxWidth: Space.contentMax + Space.margin * 2, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
    }
}
