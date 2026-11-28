import Combine
import SwiftUI

/// Motion tokens for the Aurora design. Every animated view reads `calmMotion` and falls back to a
/// plain fade (or no motion) when Reduce Motion or Low Power Mode is on.
enum Motion {
    /// Numbers and cards arriving.
    static let reveal = Animation.spring(duration: 0.7, bounce: 0.16)
    /// Rings and chart lines drawing in.
    static let draw = Animation.easeOut(duration: 1.1)
    /// The DayLine sentence streaming in.
    static let stream = Animation.easeOut(duration: 1.4)
    /// Taps: segmented pills, toggles.
    static let quick = Animation.snappy(duration: 0.28)
    /// The calm fallback for everything above.
    static let fade = Animation.easeInOut(duration: 0.2)
    /// Delay between items that arrive in sequence.
    static let stagger = 0.07
    /// The ambient backdrop's frame rate: slow drift doesn't need more.
    static let ambientFPS = 15.0
}

extension EnvironmentValues {
    /// True when Reduce Motion or Low Power Mode is on: no drift, no draw-ins, fades only.
    @Entry var calmMotion = false
}

/// Sets `calmMotion` for everything inside, and keeps it current as Low Power Mode changes.
struct MotionGate: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    func body(content: Content) -> some View {
        content
            .environment(\.calmMotion, reduceMotion || lowPower)
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
    }
}

extension View {
    func motionGate() -> some View { modifier(MotionGate()) }
}

/// Plays a one-shot entrance once per appearance: `shown` flips to true with `animation`, after
/// `delay`. With calm motion it's true straight away.
struct Entrance: ViewModifier {
    @Binding var shown: Bool
    var animation: Animation = Motion.reveal
    var delay: Double = 0
    @Environment(\.calmMotion) private var calm

    func body(content: Content) -> some View {
        content.onAppear {
            guard !shown else { return }
            if calm { shown = true } else { withAnimation(animation.delay(delay)) { shown = true } }
        }
    }
}

extension View {
    func entrance(_ shown: Binding<Bool>, _ animation: Animation = Motion.reveal, delay: Double = 0) -> some View {
        modifier(Entrance(shown: shown, animation: animation, delay: delay))
    }
}

/// Fades and lifts text in glyph by glyph, left to right, line by line. `progress` runs 0 → 1.
struct WordStream: TextRenderer, Animatable {
    var progress: Double
    /// How much of the run each glyph's own fade takes.
    private let spread = 0.35
    private let lift: CGFloat = 8

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let count = layout.reduce(0) { lines, line in lines + line.reduce(0) { $0 + $1.count } }
        guard count > 0 else { return }
        var index = 0
        for line in layout {
            for run in line {
                for slice in run {
                    let start = Double(index) / Double(count) * (1 - spread)
                    let local = min(max((progress - start) / spread, 0), 1)
                    var copy = context
                    copy.opacity = local
                    copy.translateBy(x: 0, y: (1 - local) * lift)
                    copy.draw(slice)
                    index += 1
                }
            }
        }
    }
}
