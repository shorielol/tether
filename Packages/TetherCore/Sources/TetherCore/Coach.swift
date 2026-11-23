import Foundation

/// The coach's side that doesn't need a model: a short brief of your own numbers for the on-device model to
/// answer from, and written answers from the same numbers for phones without Apple Intelligence.
public enum Coach {
    public struct Input: Sendable {
        public let lastNight: NightSummary?
        /// Earlier nights, oldest first; the last 7 are used.
        public let week: [NightSummary]
        public let effortToday: Double?
        public let sleepNeedMin: Double?
        public let bedtimeMinute: Int?
        public let warning: HealthMonitor.Warning?
        /// Journal findings already worded as sentences.
        public let journal: [String]

        public init(lastNight: NightSummary?, week: [NightSummary], effortToday: Double?, sleepNeedMin: Double?,
                    bedtimeMinute: Int?, warning: HealthMonitor.Warning?, journal: [String]) {
            self.lastNight = lastNight
            self.week = week
            self.effortToday = effortToday
            self.sleepNeedMin = sleepNeedMin
            self.bedtimeMinute = bedtimeMinute
            self.warning = warning
            self.journal = journal
        }
    }

    public enum Topic: Sendable, Equatable { case charge, sleep, effort, health, overview }

    public static let suggestions = [
        "Why is my Charge where it is?",
        "How did I sleep this week?",
        "How hard should I push today?",
        "Is anything off with my health?",
    ]

    /// What the model is told before every question.
    public static let instructions = """
        You are the coach inside Tether, a personal app for a WHOOP strap. Answer only from the numbers in the \
        brief. Only when the brief can't answer the question, say so in one sentence. Use plain words and the \
        person's own numbers, in at most four short sentences. Don't diagnose illness or give medical advice. \
        Mention a doctor only when the brief's health check says signals are off normal.
        """

    public static func hasData(_ input: Input) -> Bool { input.lastNight != nil || !input.week.isEmpty }

    // MARK: Brief

    public static func brief(_ input: Input) -> String {
        var lines: [String] = []
        if let night = input.lastNight {
            var parts: [String] = []
            if let sleep = night.totalSleepMin { parts.append("slept \(DayLine.duration(sleep))") }
            if let charge = night.charge { parts.append("Charge \(Int(charge.rounded()))%") }
            if let hrv = night.hrv { parts.append("HRV \(Int(hrv.rounded())) ms") }
            if let rhr = night.restingHR { parts.append("resting heart rate \(rhr) bpm") }
            if let resp = night.respRate { parts.append(String(format: "breathing %.1f a minute", resp)) }
            if let deep = night.deepMin, let rem = night.remMin {
                parts.append("deep \(DayLine.duration(deep)), REM \(DayLine.duration(rem))")
            }
            lines.append("Last night: " + parts.joined(separator: ", ") + ".")
            if let skin = night.skinTempDevC { lines.append("Skin temperature \(signed(skin, "°C")) against normal.") }
            let drivers = topDrivers(night)
            if !drivers.isEmpty {
                lines.append("What moved Charge most: " + drivers.map { driver in
                    let effect = driver.deltaPoints > 0 ? "added \(driver.deltaPoints) points to Charge"
                                                        : "took \(abs(driver.deltaPoints)) points off Charge"
                    return "\(driver.label) (\(driver.valueText)) \(effect)"
                }.joined(separator: "; ") + ".")
            }
        }
        let week = Array(input.week.suffix(7))
        let sleeps = week.compactMap(\.totalSleepMin)
        if !sleeps.isEmpty {
            lines.append("Average sleep over the last \(sleeps.count) nights: \(DayLine.duration(mean(sleeps))).")
        }
        let charges = week.compactMap(\.charge)
        if !charges.isEmpty { lines.append("Average Charge over those nights: \(Int(mean(charges).rounded()))%.") }
        if let effort = input.effortToday { lines.append(String(format: "Effort so far today: %.1f of 100.", effort)) }
        if let zone = zone(input) {
            let band = EffortTarget.band(for: zone)
            lines.append("Today's Effort target from Charge: \(Int(band.low))–\(Int(band.high)).")
        }
        if let need = input.sleepNeedMin {
            var line = "Sleep need tonight: \(DayLine.duration(need))"
            if let bed = input.bedtimeMinute { line += ", bed by \(clock(bed))" }
            lines.append(line + ".")
        }
        if let warning = input.warning { lines.append("Health check: \(describe(warning)).") }
        lines.append(contentsOf: input.journal.prefix(3).map { "Journal: \($0)" })
        return lines.joined(separator: "\n")
    }

    // MARK: Written answers

    public static func topic(for question: String) -> Topic {
        let q = question.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { q.contains($0) } }
        if has(["charge", "recover", "recovery", "ready", "readiness"]) { return .charge }
        if has(["sleep", "slept", "bed", "night", "tired", "nap"]) { return .sleep }
        if has(["effort", "train", "workout", "push", "exercise", "gym", "run"]) { return .effort }
        if has(["health", "sick", "illness", "temperature", "temp", "unwell", "fever", "vitals"]) { return .health }
        return .overview
    }

    public static func writtenAnswer(to question: String, _ input: Input) -> String {
        guard hasData(input) else {
            return "There are no nights scored yet, so there's nothing to go on. Wear the strap to bed and ask again in the morning."
        }
        switch topic(for: question) {
        case .charge: return chargeAnswer(input)
        case .sleep: return sleepAnswer(input)
        case .effort: return effortAnswer(input)
        case .health: return input.warning.map { "Health check: \(describe($0))." } ?? "Your health check needs last night's vitals first."
        case .overview: return [chargeAnswer(input), effortAnswer(input)].joined(separator: " ")
        }
    }

    private static func chargeAnswer(_ input: Input) -> String {
        guard let night = input.lastNight, let charge = night.charge else {
            return "Charge needs a few nights to learn your normal before it scores."
        }
        var text = "Charge is \(Int(charge.rounded()))% this morning."
        let drivers = topDrivers(night)
        if let first = drivers.first {
            text += " The biggest mover was \(first.label) (\(first.valueText)), \(points(first.deltaPoints))"
            if drivers.count > 1 { text += ", then \(drivers[1].label), \(points(drivers[1].deltaPoints))" }
            text += "."
        }
        return text
    }

    private static func sleepAnswer(_ input: Input) -> String {
        let sleeps = input.week.suffix(7).compactMap(\.totalSleepMin)
        var parts: [String] = []
        if let last = input.lastNight?.totalSleepMin { parts.append("Last night you slept \(DayLine.duration(last)).") }
        if !sleeps.isEmpty { parts.append("Over the last \(sleeps.count) nights you averaged \(DayLine.duration(mean(sleeps))).") }
        if let need = input.sleepNeedMin {
            parts.append("Tonight you need about \(DayLine.duration(need))" + (input.bedtimeMinute.map { ", so bed by \(clock($0))." } ?? "."))
        }
        return parts.isEmpty ? "There's no sleep scored yet." : parts.joined(separator: " ")
    }

    private static func effortAnswer(_ input: Input) -> String {
        guard let zone = zone(input) else { return "Once Charge is scoring, Tether sets an Effort target for the day." }
        let band = EffortTarget.band(for: zone)
        var text = "With today's Charge, aim for an Effort of \(Int(band.low))–\(Int(band.high))."
        if let effort = input.effortToday { text += String(format: " You're at %.1f so far.", effort) }
        return text
    }

    // MARK: Helpers

    private static func zone(_ input: Input) -> ChargeZone? { input.lastNight?.charge.map(ChargeZone.init(charge:)) }

    private static func topDrivers(_ night: NightSummary) -> [NightSummary.Driver] {
        Array(night.drivers.filter { $0.deltaPoints != 0 }.sorted { abs($0.deltaPoints) > abs($1.deltaPoints) }.prefix(2))
    }

    private static func describe(_ warning: HealthMonitor.Warning) -> String {
        switch warning {
        case .learning(let nights): "still learning your normal, \(nights) nights to go"
        case .clear: "nothing unusual"
        case .mild(let signals): "a little off normal (\(signals.joined(separator: ", ")))"
        case .raised(let signals): "several signals off normal together (\(signals.joined(separator: ", ")))"
        case .explained(let signals): "off normal with a likely reason (\(signals.joined(separator: ", ")))"
        }
    }

    private static func points(_ delta: Int) -> String { delta > 0 ? "+\(delta) points" : "−\(abs(delta)) points" }

    private static func signed(_ value: Double, _ unit: String) -> String {
        String(format: "%@%.1f %@", value >= 0 ? "+" : "−", abs(value), unit)
    }

    private static func clock(_ minute: Int) -> String {
        let wrapped = ((minute % 1_440) + 1_440) % 1_440
        let date = Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(wrapped * 60))
        return date.formatted(date: .omitted, time: .shortened)
    }

    private static func mean(_ values: [Double]) -> Double { values.reduce(0, +) / Double(values.count) }
}
