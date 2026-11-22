import Charts
import SwiftUI
import TetherCore

/// Today's energy forecast: how alert you're likely to feel through the day, your sharpest two hours,
/// the afternoon dip, the coffee cut-off, and a nap window when you're owed sleep.
struct EnergyCard: View {
    let forecast: EnergyForecast
    let now: Int

    private var dayStart: Date { Calendar.current.startOfDay(for: .now) }
    private func date(_ minute: Int) -> Date { dayStart.addingTimeInterval(TimeInterval(minute * 60)) }
    private func clock(_ minute: Int) -> String { date(minute).formatted(date: .omitted, time: .shortened) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Energy today").font(.headline)
                Spacer()
                Text("estimate from your sleep").font(.caption).foregroundStyle(TetherBrand.sub)
            }
            chart.frame(height: 96)
            VStack(alignment: .leading, spacing: 4) {
                line("bolt.fill", "Sharpest \(clock(forecast.bestWindow.lowerBound))–\(clock(forecast.bestWindow.upperBound))",
                     TetherBrand.good)
                line("arrow.down.right", "Dip around \(clock(forecast.dipMinute))", TetherBrand.sub)
                line("cup.and.saucer.fill", "Last coffee by \(clock(forecast.coffeeCutoffMinute))", TetherBrand.sub)
                if let nap = forecast.napWindow {
                    line("powersleep", "Room for a 20-minute nap \(clock(nap.lowerBound))–\(clock(nap.upperBound))",
                         TetherBrand.ember)
                }
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private var chart: some View {
        Chart {
            RectangleMark(xStart: .value("Sharpest from", date(forecast.bestWindow.lowerBound)),
                          xEnd: .value("Sharpest to", date(forecast.bestWindow.upperBound)))
                .foregroundStyle(TetherBrand.good.opacity(0.12))
            if let nap = forecast.napWindow {
                RectangleMark(xStart: .value("Nap from", date(nap.lowerBound)), xEnd: .value("Nap to", date(nap.upperBound)))
                    .foregroundStyle(TetherBrand.ember.opacity(0.14))
            }
            ForEach(forecast.points) { point in
                LineMark(x: .value("Time", date(point.minute)), y: .value("Energy", point.level))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(TetherBrand.text)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            RuleMark(x: .value("Coffee cut-off", date(forecast.coffeeCutoffMinute)))
                .foregroundStyle(TetherBrand.sub.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            let nowMinute = (now - Int(dayStart.timeIntervalSince1970)) / 60
            if let current = forecast.points.min(by: { abs($0.minute - nowMinute) < abs($1.minute - nowMinute) }),
               abs(current.minute - nowMinute) <= 15 {
                PointMark(x: .value("Now", date(current.minute)), y: .value("Energy now", current.level))
                    .foregroundStyle(TetherBrand.ember).symbolSize(40)
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis(.hidden)
        .chartXScale(domain: date(6 * 60)...date(24 * 60))
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisValueLabel(format: .dateTime.hour())
            }
        }
    }

    private func line(_ icon: String, _ text: String, _ tint: Color) -> some View {
        Label { Text(text).font(.subheadline) } icon: { Image(systemName: icon).foregroundStyle(tint) }
    }
}
