import Foundation
import StrandAnalytics

/// Phase 3: last night's vitals each checked against your range, and a gentle early warning when
/// several move the illness-ward way together. Uses NOOP's `VitalBands` and `IllnessSignalEngine`.
/// Not a diagnosis, and silent until your own normal has `trustedNights` behind it.
public struct HealthMonitor: Sendable, Equatable {
    public struct Flag: Sendable, Equatable, Identifiable {
        public let name: String
        public let outOfRange: Bool
        /// True when judged against your own normal; false while a typical adult range stands in.
        public let personal: Bool
        public var id: String { name }
    }

    public enum Warning: Sendable, Equatable {
        /// Your normal isn't settled yet, so nothing is judged.
        case learning(nightsToGo: Int)
        case clear
        /// A little off; worth a look, not a notification.
        case mild([String])
        /// Several signals off together: the one case that notifies.
        case raised([String])
        /// Off, but something else (a hard late workout, say) explains it.
        case explained([String])
    }

    public struct Notice: Sendable, Equatable {
        public let title: String
        public let body: String
    }

    public let flags: [Flag]
    public let warning: Warning

    /// Nights before your own normal is trusted, as NOOP's baselines count it.
    public static let trustedNights = 14

    private struct Vital: Sendable {
        let name: String
        let key: String
        let population: ClosedRange<Double>
        /// Which way is illness-ward: +1 when a rise is, −1 when a drop is.
        let illnessward: Double
        let read: @Sendable (NightSummary) -> Double?
        let phrase: @Sendable (Deviation) -> String
    }

    private static let vitals: [Vital] = [
        Vital(name: "HRV", key: "hrv", population: 20...120, illnessward: -1, read: { $0.hrv },
              phrase: { "HRV \(percent($0))" }),
        Vital(name: "Resting HR", key: "resting_hr", population: 40...80, illnessward: 1,
              read: { $0.restingHR.map(Double.init) }, phrase: { "resting HR \(signed($0.delta, 0)) bpm" }),
        Vital(name: "Breathing", key: "resp", population: 12...20, illnessward: 1, read: { $0.respRate },
              phrase: { "breathing \(signed($0.delta, 1)) /min" }),
        Vital(name: "Skin temp", key: "skin_temp", population: 30...36, illnessward: 1, read: { $0.skinTempC },
              phrase: { "skin temp \(signed($0.delta, 1)) °C" }),
    ]

    public static func check(latest: NightSummary?, history: [NightSummary]) -> HealthMonitor? {
        guard let latest else { return nil }
        let earlier = history.filter { $0.day < latest.day }.sorted { $0.day < $1.day }
        var flags: [Flag] = []
        var inputs = IllnessSignalEngine.Inputs()
        var labels: [String: String] = [:]
        var hrvNights = 0
        var trusted = false
        for vital in vitals {
            guard let cfg = Baselines.metricCfg[vital.key] else { continue }
            let series = VitalBands.calendarSeries(earlier.map { (day: $0.day, value: vital.read($0)) })
            let state = Baselines.foldHistory(series, cfg: cfg)
            if vital.key == "hrv" {
                hrvNights = state.nValid
                trusted = state.trusted
            }
            guard let value = vital.read(latest) else { continue }
            let band = VitalBands.band(value: value, history: series, populationRange: vital.population, cfg: cfg)
            flags.append(Flag(name: vital.name, outOfRange: band.band == .outOfRange, personal: band.basis == .personal))
            guard state.usable else { continue }
            let deviation = Baselines.deviation(value, state: state)
            let reading = IllnessSignalEngine.SignalReading(zIllnessward: deviation.z * vital.illnessward)
            switch vital.key {
            case "hrv": inputs.hrv = reading
            case "resting_hr": inputs.restingHR = reading
            case "resp": inputs.respiration = reading
            default: inputs.skinTemp = reading
            }
            labels[engineKey(vital.key)] = vital.phrase(deviation)
        }
        guard trusted else {
            return HealthMonitor(flags: flags, warning: .learning(nightsToGo: max(1, trustedNights - hrvNights)))
        }
        let result = IllnessSignalEngine.evaluate(inputs, context: .init(baselineTrusted: true), firedLabels: labels)
        let warning: Warning = switch result.level {
        case .quiet, .alreadyUnwell: .clear
        case .mild: .mild(result.firedSignals)
        case .raised: .raised(result.firedSignals)
        case .suppressed: .explained(result.firedSignals)
        }
        return HealthMonitor(flags: flags, warning: warning)
    }

    /// The morning notification: only for a raised warning, and at most once a day.
    public static func notification(for warning: Warning, day: String, lastNotifiedDay: String?) -> Notice? {
        guard case .raised(let signals) = warning, day != lastNotifiedDay else { return nil }
        return Notice(title: "A few of your signals are off your normal",
                      body: "Last night: \(signals.joined(separator: ", ")). Worth taking it easy and seeing how you feel. \(IllnessSignalEngine.disclaimerTail)")
    }

    private static func engineKey(_ key: String) -> String {
        switch key {
        case "resting_hr": "restingHR"
        case "resp": "respiration"
        case "skin_temp": "skinTemp"
        default: key
        }
    }

    private static func signed(_ value: Double, _ decimals: Int) -> String {
        let text = String(format: "%.\(decimals)f", abs(value))
        return value >= 0 ? "+\(text)" : "−\(text)"
    }

    private static func percent(_ deviation: Deviation) -> String {
        signed(deviation.ratio * 100, 0) + "%"
    }
}
