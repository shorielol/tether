import ActivityKit
import SwiftUI
import TetherSnapshot
import WidgetKit

/// "Recording your night": the lock-screen card and Dynamic Island while the phone holds the strap.
/// The app starts it when the strap links with Tether open and updates it every minute (AppModel).
struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingAttributes.self) { context in
            RecordingCard(start: context.attributes.startedAt, status: context.state)
                .activityBackgroundTint(Palette.card.opacity(0.92))
                .activitySystemActionForegroundColor(Palette.text)
                .widgetURL(URL(string: "tether://strap"))
        } dynamicIsland: { context in
            let status = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        LinkMark(size: 26)
                        HeartRate(bpm: status.heartRate).font(.title3)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Elapsed(start: context.attributes.startedAt).font(.title3)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(status.subtitle).font(.caption).foregroundStyle(Palette.sub)
                        NightProgress(start: context.attributes.startedAt)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                LinkMark(size: 18)
            } compactTrailing: {
                HeartRate(bpm: status.heartRate).font(.caption.weight(.semibold))
            } minimal: {
                LinkMark(size: 18)
            }
            .keylineTint(Palette.ember)
            .widgetURL(URL(string: "tether://strap"))
        }
    }
}

// MARK: - Lock screen card

private struct RecordingCard: View {
    let start: Date
    let status: RecordingStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                LinkMark(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(status.title).font(.subheadline.weight(.semibold))
                    Text(status.subtitle).font(.caption).foregroundStyle(Palette.sub).lineLimit(1)
                }
                Spacer(minLength: 8)
                Elapsed(start: start).font(.title2)
            }
            HStack(alignment: .top) {
                Stat(label: "Heart rate", value: status.heartRate.map(String.init))
                Stat(label: "Coverage", value: status.coveragePercent.map { "\($0)%" })
                Stat(label: "Strap", value: status.strapBattery.map { "\($0)%" })
            }
            NightProgress(start: start)
        }
        .foregroundStyle(Palette.text)
        .padding(16)
    }
}

private struct Stat: View {
    let label: String
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.medium)).foregroundStyle(Palette.sub)
            Text(value ?? "–").font(.headline).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Pieces

/// Time since the card started, ticking on its own without app updates.
private struct Elapsed: View {
    let start: Date

    var body: some View {
        Text(timerInterval: start...Date.distantFuture, countsDown: false)
            .fontWeight(.semibold)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 110, alignment: .trailing)
    }
}

/// Fills over the card's 8-hour life, which is about a night.
private struct NightProgress: View {
    let start: Date

    var body: some View {
        let end = start.addingTimeInterval(TimeInterval(RecordingStatus.cardHours * 3_600))
        ProgressView(timerInterval: start...end, countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .tint(Palette.text)
    }
}

private struct HeartRate: View {
    let bpm: Int?

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "heart.fill").font(.caption2).foregroundStyle(Palette.ember)
            Text(bpm.map(String.init) ?? "–").monospacedDigit()
        }
    }
}

/// The app icon's two linked rings, small: dusk for the strap, ember for the phone.
struct LinkMark: View {
    let size: CGFloat

    var body: some View {
        let ring = size * 0.42, line = size * 0.12
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26).fill(Palette.navy)
            Circle().stroke(Palette.dusk, lineWidth: line).frame(width: ring, height: ring).offset(x: -size * 0.13)
            Circle().stroke(Palette.ember, lineWidth: line).frame(width: ring, height: ring).offset(x: size * 0.13)
        }
        .frame(width: size, height: size)
    }
}

/// Brand colours (App/Shared/TetherBrand isn't part of the extension).
private enum Palette {
    static let text = Color(red: 242 / 255, green: 244 / 255, blue: 247 / 255)
    static let sub = Color(red: 163 / 255, green: 169 / 255, blue: 181 / 255)
    static let ember = Color(red: 1, green: 138 / 255, blue: 76 / 255)
    static let dusk = Color(red: 140 / 255, green: 155 / 255, blue: 1)
    static let navy = Color(red: 27 / 255, green: 31 / 255, blue: 58 / 255)
    static let card = Color(red: 20 / 255, green: 23 / 255, blue: 32 / 255)
}

// MARK: - Previews

private let previewAttributes = RecordingAttributes(startedAt: .now.addingTimeInterval(-71 * 60))

#Preview("Card", as: .content, using: previewAttributes) {
    RecordingLiveActivity()
} contentStates: {
    RecordingStatus(heartRate: 57, link: .solid, missedMinutes: 0, coveragePercent: 100, strapBattery: 58, isNight: true)
    RecordingStatus(heartRate: nil, link: .reconnecting, missedMinutes: 6, coveragePercent: 92, strapBattery: 57, isNight: true)
}

#Preview("Island", as: .dynamicIsland(.expanded), using: previewAttributes) {
    RecordingLiveActivity()
} contentStates: {
    RecordingStatus(heartRate: 57, link: .solid, missedMinutes: 0, coveragePercent: 100, strapBattery: 58, isNight: true)
}
