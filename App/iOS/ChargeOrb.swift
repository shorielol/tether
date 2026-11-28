import SwiftUI
import TetherCore

/// Today's hero: Charge in a glass orb. The ring draws to the value, your normal sits as a faint arc on
/// the track, and the number rolls in from a dash. Before Charge exists the ring counts learning nights.
struct ChargeOrb: View {
    let charge: Double?
    let band: NormalBand?
    let progress: BaselineProgress

    @State private var shown = false

    static let size: CGFloat = 216
    private static let line: CGFloat = 10
    private static let inset: CGFloat = 16

    private var zone: ChargeZone? { charge.map(ChargeZone.init(charge:)) }
    private var tint: Color { zone.map(TetherBrand.charge) ?? TetherBrand.dusk }
    private var learned: Int { min(progress.scoredNights, BaselineProgress.chargeNights) }

    /// How far round the ring goes: the Charge value, or the share of learning nights done.
    private var fraction: Double {
        if let charge { return min(max(charge / 100, 0), 1) }
        return Double(learned) / Double(BaselineProgress.chargeNights)
    }

    var body: some View {
        ZStack {
            bead
            ring
            centre
        }
        .frame(width: Self.size, height: Self.size)
        // The glow spills past the orb without taking any layout space.
        .background { glow.allowsHitTesting(false) }
        .frame(maxWidth: .infinity)
        .entrance($shown, Motion.draw, delay: 0.1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    private var glow: some View {
        Circle()
            .fill(RadialGradient(colors: [tint.opacity(0.32), tint.opacity(0.08), .clear],
                                 center: .center, startRadius: Self.size * 0.2, endRadius: Self.size * 0.7))
            .frame(width: Self.size * 1.4, height: Self.size * 1.4)
            .opacity(shown ? 1 : 0)
    }

    private var bead: some View {
        Circle()
            .fill(LinearGradient(colors: [Color.white.opacity(0.11), Color.white.opacity(0.02)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(Circle().strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.04)],
                               startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .overlay(alignment: .top) {
                // A soft highlight on the upper edge, as on a glass bead.
                Ellipse().fill(Color.white.opacity(0.07))
                    .frame(width: Self.size * 0.62, height: Self.size * 0.22)
                    .blur(radius: 10)
                    .offset(y: Self.size * 0.07)
            }
    }

    private var ring: some View {
        let stroke = StrokeStyle(lineWidth: Self.line, lineCap: .round)
        return ZStack {
            Circle().inset(by: Self.inset).stroke(TetherBrand.track, lineWidth: Self.line)
            if let band, charge != nil {
                Circle().inset(by: Self.inset)
                    .trim(from: min(max(band.low / 100, 0), 1), to: min(max(band.high / 100, 0), 1))
                    .stroke(Color.white.opacity(0.22), style: stroke)
            }
            Circle().inset(by: Self.inset)
                .trim(from: 0, to: shown ? fraction : 0)
                .stroke(tint, style: stroke)
                .shadow(color: tint.opacity(0.55), radius: 8)
        }
        .rotationEffect(.degrees(-90))
    }

    @ViewBuilder private var centre: some View {
        if let charge, let zone {
            let rounded = Int(charge.rounded())
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(shown ? "\(rounded)" : "–")
                        .font(.system(size: 64, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText(value: shown ? Double(rounded) : 0))
                    Text("%").font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(TetherBrand.sub)
                }
                .monospacedDigit()
                Text("Charge · \(zone.name)")
                    .font(.caption.weight(.semibold)).textCase(.uppercase).tracking(1.2)
                    .foregroundStyle(tint)
            }
        } else {
            VStack(spacing: 4) {
                Text("Learning").font(.title2.weight(.semibold))
                Text("\(learned) of \(BaselineProgress.chargeNights) nights")
                    .font(.footnote).foregroundStyle(TetherBrand.sub).monospacedDigit()
                Text("Charge").font(.caption.weight(.semibold)).textCase(.uppercase).tracking(1.2)
                    .foregroundStyle(TetherBrand.dusk)
            }
        }
    }

    private var accessibility: String {
        guard let charge, let zone else {
            return "Charge is learning, \(learned) of \(BaselineProgress.chargeNights) nights"
        }
        return "Charge \(Int(charge.rounded())) percent, \(zone.name)"
    }
}

/// Text that streams in glyph by glyph the first time it appears.
struct StreamedText: View {
    let text: String
    @State private var shown = false

    var body: some View {
        Text(text)
            .textRenderer(WordStream(progress: shown ? 1 : 0))
            .entrance($shown, Motion.stream, delay: 0.45)
    }
}
