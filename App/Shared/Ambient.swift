import SwiftUI
import TetherCore

/// The Aurora backdrop: a slow mesh gradient tinted by today's Charge zone, a fine grain, and ink at
/// the bottom so content and the tab bar sit on near-black. It drifts at a low frame rate, and stops
/// with calm motion or when the app isn't active.
struct AuroraBackdrop: View {
    /// Nil before Charge exists: a neutral dusk and navy aurora.
    var zone: ChargeZone?

    @Environment(\.calmMotion) private var calm
    @Environment(\.scenePhase) private var phase

    var body: some View {
        let paused = calm || phase != .active
        TimelineView(.animation(minimumInterval: 1 / Motion.ambientFPS, paused: paused)) { context in
            let time = paused ? 0 : context.date.timeIntervalSinceReferenceDate
            MeshGradient(width: 3, height: 3, points: Self.points(time), colors: colors)
        }
        .overlay { Grain().opacity(0.5) }
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [TetherBrand.ink.opacity(0), TetherBrand.ink], startPoint: .top, endPoint: .bottom)
                .frame(height: 260)
        }
        .background(TetherBrand.ink)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: 1.2), value: zone)
    }

    /// Three tints per zone, from the brand board: green leans mint and teal, yellow amber and
    /// ember, red ember and rose.
    private var palette: (Color, Color, Color) {
        switch zone {
        case .green: (TetherBrand.good, TetherBrand.dusk, Self.teal)
        case .yellow: (TetherBrand.headsUp, TetherBrand.ember, TetherBrand.dusk)
        case .red: (TetherBrand.ember, Self.rose, TetherBrand.navy)
        case nil: (TetherBrand.dusk, TetherBrand.navy, TetherBrand.deep)
        }
    }

    private var colors: [Color] {
        let (a, b, c) = palette
        let ink = TetherBrand.ink
        return [
            ink.mix(with: a, by: 0.42), ink.mix(with: b, by: 0.34), ink.mix(with: c, by: 0.40),
            ink.mix(with: c, by: 0.16), ink.mix(with: a, by: 0.20), ink.mix(with: b, by: 0.12),
            ink, ink, ink,
        ]
    }

    /// Corners stay put; the middle points wander a little, each on its own slow cycle.
    private static func points(_ time: TimeInterval) -> [SIMD2<Float>] {
        func wave(_ period: Double, _ phase: Double, _ size: Double) -> Float {
            Float(sin(time * 2 * .pi / period + phase) * size)
        }
        return [
            [0, 0], [0.5 + wave(23, 0, 0.12), 0], [1, 0],
            [0, 0.42 + wave(29, 1, 0.08)], [0.5 + wave(19, 2, 0.14), 0.38 + wave(31, 3, 0.08)], [1, 0.46 + wave(27, 4, 0.08)],
            [0, 1], [0.5, 1], [1, 1],
        ]
    }

    private static let teal = Color(red: 47 / 255, green: 125 / 255, blue: 116 / 255)
    private static let rose = Color(red: 194 / 255, green: 87 / 255, blue: 122 / 255)
}

/// A fixed film grain: thousands of faint specks from a seeded generator, drawn once.
private struct Grain: View {
    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x7E7_4E2
            func next() -> Double {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double(seed >> 33) / Double(1 << 31)
            }
            let specks = Int(size.width * size.height / 90)
            for _ in 0..<specks {
                let rect = CGRect(x: next() * size.width, y: next() * size.height, width: 1, height: 1)
                context.fill(Path(rect), with: .color(.white.opacity(0.03 + next() * 0.05)))
            }
        }
        .drawingGroup()
    }
}
