import SwiftUI
import TetherCore

/// Today below the scores: six icon tiles, one number each. Every tile opens its own screen, where the
/// detail lives.
struct TodayTiles: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: typeSize.isAccessibilitySize ? 1 : 3)
        LazyVGrid(columns: columns, spacing: 10) {
            DetailLink(.recovery) { hrv }
            DetailLink(.effort) {
                Tile(icon: "figure.walk", value: model.steps.flatMap { $0.hasData ? $0.total.formatted() : nil },
                     label: "Steps")
            }
            DetailLink(.stress) { stress }
            DetailLink(.energy) {
                Tile(icon: "bolt", value: model.energyForecast.map { clock($0.bestWindow.lowerBound) }, label: "Sharpest")
            }
            DetailLink(.sleep) {
                Tile(icon: "bed.double", value: model.sleepCoach.map { clock($0.bedtimeMinute) }, label: "Bedtime")
            }
            DetailLink(.marks) {
                Tile(icon: "bookmark", value: model.collector.isPaired ? "\(model.marksToday.count)" : nil, label: "Marks")
            }
        }
    }

    private var hrv: some View {
        let measure = model.recovery?.measures.first { $0.name == "HRV" }
        // Amber only for a night outside your normal in the worse direction.
        let low = measure.flatMap { m in m.band.map { (m.value < $0.low || m.value > $0.high) && m.isBetter == false } } ?? false
        return Tile(icon: "waveform.path.ecg", value: measure.map { "\(Int($0.value.rounded())) ms" }, label: "HRV",
                    dot: low ? TetherBrand.headsUp : nil)
    }

    private var stress: some View {
        let now = model.today.flatMap(StressNow.current)
        return Tile(icon: "gauge.with.needle", value: now?.band.name, label: "Stress",
                    dot: now.map { StressStyle.color($0.band) })
    }

    private func clock(_ minute: Int) -> String {
        let wrapped = ((minute % 1_440) + 1_440) % 1_440
        return Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(wrapped * 60))
            .formatted(date: .omitted, time: .shortened)
    }
}

/// One glanceable number with its icon. A missing number shows a dash, never zero.
struct Tile: View {
    let icon: String
    let value: String?
    let label: String
    var dot: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon).font(.body.weight(.medium)).foregroundStyle(TetherBrand.sub)
                Spacer()
                if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(value ?? "–").font(.headline).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(label).font(.caption).foregroundStyle(TetherBrand.sub)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glass(cornerRadius: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value ?? "not yet")")
    }
}

/// The latest scored hour's stress band (Calm, Usual or High), and the hour its run began.
enum StressNow {
    static func current(_ today: TodaySnapshot) -> (band: StressBand, since: Int)? {
        let scored = today.stressHours.filter { !$0.wasActive && $0.level != nil }
        guard let last = scored.last, let value = last.level else { return nil }
        let band = StressBand(level: value)
        var since = last.hour
        for hour in scored.dropLast().reversed() {
            guard let level = hour.level, StressBand(level: level) == band, hour.hour == since - 1 else { break }
            since = hour.hour
        }
        return (band, since)
    }
}

/// Header button for Ask, beside the strap chip.
struct AskButton: View {
    var body: some View {
        NavigationLink(value: TodayDetail.coach) {
            Image(systemName: "sparkles")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(TetherBrand.cardFill, in: .circle)
                .overlay(Circle().strokeBorder(TetherBrand.cardStroke))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask about your numbers")
    }
}

/// Energy on its own screen, now that Today shows only its best window.
struct EnergyView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabScreen {
            ScreenHeader(eyebrow: "Estimate from your sleep", title: "Energy")
            if let forecast = model.energyForecast {
                EnergyCard(forecast: forecast, now: Int(Date.now.timeIntervalSince1970))
            } else {
                NotYet(title: "After tonight", detail: "The forecast starts from a night that ended today.").card()
            }
        }
    }
}
