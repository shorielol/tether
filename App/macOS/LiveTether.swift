import SwiftUI
import TetherCore

/// Tether's signature: iPhone and Mac joined by a line, with the strap's heart sitting toward
/// whichever one holds it. While this Mac records, a pulse runs from the heart to the Mac at the
/// wearer's real heart rate. With Reduce Motion on it holds still.
struct LiveTether: View {
    enum Scale { case compact, large }

    let holder: LinkHolder
    var handedOver = false
    var scale: Scale = .compact

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var glyphFont: Font { scale == .compact ? .system(size: 13, weight: .regular) : .system(size: 40, weight: .light) }
    private var heartSize: CGFloat { scale == .compact ? 11 : 34 }
    private var lineWidth: CGFloat { scale == .compact ? 1.5 : 3 }
    private var height: CGFloat { scale == .compact ? 18 : 64 }

    /// Where the heart sits along the line, 0 = iPhone end, 1 = Mac end.
    private var heartPosition: CGFloat {
        if handedOver { return 0.28 }
        switch holder {
        case .thisDevice: return 0.72
        case .otherDevice: return 0.28
        case .nobody, .bluetoothOff: return 0.5
        }
    }

    private var bpm: Int? { if case .thisDevice(let bpm) = holder { bpm } else { nil } }
    private var beating: Bool { bpm != nil && !reduceMotion && !handedOver }
    private var isOnThisMac: Bool { if case .thisDevice = holder { !handedOver } else { false } }
    private var isWithPhone: Bool { holder == .otherDevice || handedOver }

    var body: some View {
        HStack(spacing: scale == .compact ? 6 : 18) {
            Image(systemName: "iphone")
                .font(glyphFont)
                .foregroundStyle(isWithPhone ? .primary : .tertiary)
            GeometryReader { geo in
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !beating)) { context in
                    let phase = beatPhase(at: context.date)
                    ZStack(alignment: .topLeading) {
                        lines(width: geo.size.width, midY: geo.size.height / 2)
                        if beating { pulse(width: geo.size.width, midY: geo.size.height / 2, phase: phase) }
                        heart(phase: phase)
                            .position(x: geo.size.width * heartPosition, y: geo.size.height / 2)
                    }
                }
            }
            .frame(height: height)
            Image(systemName: "laptopcomputer")
                .font(glyphFont)
                .foregroundStyle(isOnThisMac ? .primary : .tertiary)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: heartPosition)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func lines(width: CGFloat, midY: CGFloat) -> some View {
        let heartX = width * heartPosition
        return ZStack {
            segment(from: 0, to: heartX, midY: midY, live: isWithPhone)
            segment(from: heartX, to: width, midY: midY, live: isOnThisMac)
        }
    }

    private func segment(from start: CGFloat, to end: CGFloat, midY: CGFloat, live: Bool) -> some View {
        Path { $0.move(to: CGPoint(x: start, y: midY)); $0.addLine(to: CGPoint(x: end, y: midY)) }
            .stroke(live ? AnyShapeStyle(Theme.ember) : AnyShapeStyle(Theme.grid),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: live ? [] : [3, 4]))
    }

    private func pulse(width: CGFloat, midY: CGFloat, phase: Double) -> some View {
        let start = width * heartPosition
        let eased = 1 - pow(1 - phase, 3)
        let size = lineWidth * 2.6
        return Circle()
            .fill(Theme.ember)
            .frame(width: size, height: size)
            .opacity(1 - phase * 0.8)
            .position(x: start + (width - start) * eased, y: midY)
    }

    private func heart(phase: Double) -> some View {
        let filled = isOnThisMac || isWithPhone
        let beat = beating ? max(0, 1 - phase * 5) : 0
        return Image(systemName: filled ? "heart.fill" : "heart")
            .font(.system(size: heartSize, weight: .semibold))
            .foregroundStyle(filled ? AnyShapeStyle(Theme.ember) : AnyShapeStyle(.secondary))
            .scaleEffect(1 + 0.12 * beat)
    }

    /// 0 at each beat, rising to 1 just before the next.
    private func beatPhase(at date: Date) -> Double {
        guard let bpm, bpm > 0 else { return 0 }
        let period = 60 / Double(bpm)
        return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
    }

    private var accessibilityText: String {
        if handedOver { return "Strap handed to your iPhone" }
        switch holder {
        case .thisDevice(let bpm?): return "Strap recording on this Mac, \(bpm) beats per minute"
        case .thisDevice(nil): return "Strap connected to this Mac, waiting for a beat"
        case .otherDevice: return "Strap is with your iPhone"
        case .bluetoothOff: return "Bluetooth is off on this Mac"
        case .nobody: return "Looking for your strap"
        }
    }
}
