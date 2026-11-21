import Foundation
import TetherCore

/// One markdown file per day. A flat `key: value` header anyone can read, a short summary, and
/// labelled CSV blocks for the series. The phone is the only writer.
public enum DayFile {
    public static let version = 1

    public enum ReadError: Error, Equatable {
        case missingHeader
        case unsupportedVersion(Int)
        case badValue(String)
    }

    public static func relativePath(day: String) -> String {
        let parts = day.split(separator: "-")
        guard parts.count == 3 else { return "days/\(day).md" }
        return "days/\(parts[0])/\(parts[1])/\(day).md"
    }

    // MARK: - Write

    public static func write(_ record: DayRecord) -> String {
        var header = Header()
        header["tether"] = String(version)
        header["day"] = record.day
        header["saved_at"] = String(record.savedAt)
        header.set("strap_battery_pct", record.strapBatteryPct)
        if let today = record.today { writeToday(today, into: &header) }
        if let night = record.night { writeNight(night, into: &header) }

        var out = "---\n" + header.lines.joined(separator: "\n") + "\n---\n\n# \(record.day)\n\n"
        out += summary(record).map { "- \($0)" }.joined(separator: "\n") + "\n"
        if let today = record.today {
            out += block("minutes", "ts,bpm,segment", today.minuteSeries.map { "\($0.ts),\(fmt($0.bpm)),\($0.segment)" })
            out += block("stress", "hour,level,active", today.stressHours.map {
                "\($0.hour),\($0.level.map(fmt) ?? ""),\($0.wasActive ? 1 : 0)"
            })
        }
        if let night = record.night {
            out += block("stages", "start,end,stage", night.stages.map { "\($0.start),\($0.end),\($0.kind.rawValue)" })
            out += block("drivers", "delta,label,value_text", night.drivers.map {
                "\($0.deltaPoints),\($0.label),\($0.valueText)"
            })
        }
        return out
    }

    private static func writeToday(_ today: TodaySnapshot, into header: inout Header) {
        header.set("window_start", today.window.lowerBound)
        header.set("window_end", today.window.upperBound)
        header.set("max_hr", today.maxHR)
        header.set("min_bpm", today.minBPM)
        header.set("avg_bpm", today.avgBPM)
        header.set("max_bpm", today.maxBPM)
        header["zone_minutes"] = today.zoneMinutes.map(String.init).joined(separator: ",")
        header.set("resting_hr", today.restingHR)
        header["resting_source"] = today.restingSource.rawValue
        header.set("effort", today.effort)
        header.set("calories_total", today.caloriesTotal)
        header.set("calories_active", today.caloriesActive)
        header.set("hrv_now_ms", today.hrvNow)
        if let coverage = today.coverage {
            header.set("coverage_window_start", coverage.window.lowerBound)
            header.set("coverage_window_end", coverage.window.upperBound)
            header.set("coverage_captured_s", coverage.capturedSeconds)
            header["coverage_gaps"] = coverage.gaps.map { "\($0.lowerBound)-\($0.upperBound)" }.joined(separator: ";")
        }
    }

    private static func writeNight(_ night: NightSummary, into header: inout Header) {
        header["night_day"] = night.day
        header.set("sleep_start", night.sleepStart)
        header.set("sleep_end", night.sleepEnd)
        header.set("total_sleep_min", night.totalSleepMin)
        header.set("sleep_efficiency", night.efficiency)
        header.set("deep_min", night.deepMin)
        header.set("rem_min", night.remMin)
        header.set("light_min", night.lightMin)
        header.set("disturbances", night.disturbances)
        header.set("night_resting_hr", night.restingHR)
        header.set("night_hrv_ms", night.hrv)
        header.set("resp_rate", night.respRate)
        header.set("charge", night.charge)
        header.set("rest", night.rest)
    }

    private static func summary(_ record: DayRecord) -> [String] {
        var lines: [String] = []
        if let night = record.night, let minutes = night.totalSleepMin {
            lines.append("Slept \(Int(minutes) / 60) h \(Int(minutes) % 60) m (estimated from heart rate)")
        }
        if let charge = record.night?.charge { lines.append("Charge \(Int(charge.rounded()))") }
        if let today = record.today {
            if let effort = today.effort { lines.append("Effort \(String(format: "%.1f", effort))") }
            if let low = today.minBPM, let avg = today.avgBPM, let high = today.maxBPM {
                lines.append("Heart rate \(low)–\(high) bpm, average \(avg)")
            }
            if let coverage = today.coverage {
                lines.append("Captured \(Int((coverage.fraction * 100).rounded()))% of the day")
            }
        }
        return lines.isEmpty ? ["Nothing measured"] : lines
    }

    private static func block(_ name: String, _ columns: String, _ rows: [String]) -> String {
        "\n```csv \(name)\n\(columns)\n" + rows.map { $0 + "\n" }.joined() + "```\n"
    }

    static func fmt(_ value: Double) -> String { String(describing: value) }

    /// Every block has three columns; the last one may itself contain commas.
    private static let csvColumns = 3

    // MARK: - Read

    public static func read(_ text: String) throws -> DayRecord {
        let lines = text.components(separatedBy: "\n")
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { throw ReadError.missingHeader }
        var header = Header()
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            header[String(line[..<colon])] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        let version = try header.int("tether") ?? 0
        guard version == Self.version else { throw ReadError.unsupportedVersion(version) }
        guard let day = header["day"], let savedAt = try header.int("saved_at") else { throw ReadError.badValue("day") }
        let blocks = csvBlocks(Array(lines[(end + 1)...]))
        return DayRecord(day: day, savedAt: savedAt, strapBatteryPct: try header.int("strap_battery_pct"),
                         today: try readToday(header, blocks), night: try readNight(header, blocks))
    }

    private static func readToday(_ header: Header, _ blocks: [String: [[String]]]) throws -> TodaySnapshot? {
        guard let start = try header.int("window_start"), let end = try header.int("window_end") else { return nil }
        let minutes = try (blocks["minutes"] ?? []).map { row -> TodaySnapshot.MinutePoint in
            guard row.count == 3, let ts = Int(row[0]), let bpm = Double(row[1]), let seg = Int(row[2]) else {
                throw ReadError.badValue("minutes")
            }
            return .init(ts: ts, bpm: bpm, segment: seg)
        }
        let stress = try (blocks["stress"] ?? []).map { row -> TodaySnapshot.StressHour in
            guard row.count == 3, let hour = Int(row[0]) else { throw ReadError.badValue("stress") }
            return .init(hour: hour, level: row[1].isEmpty ? nil : Double(row[1]), wasActive: row[2] == "1")
        }
        var coverage: CoverageReport?
        if let cStart = try header.int("coverage_window_start"), let cEnd = try header.int("coverage_window_end"),
           let captured = try header.int("coverage_captured_s") {
            let gaps = try (header["coverage_gaps"] ?? "").split(separator: ";").map { pair -> ClosedRange<Int> in
                let ends = pair.split(separator: "-").compactMap { Int($0) }
                guard ends.count == 2, ends[0] <= ends[1] else { throw ReadError.badValue("coverage_gaps") }
                return ends[0]...ends[1]
            }
            coverage = CoverageReport(window: cStart...cEnd, capturedSeconds: captured, gaps: gaps)
        }
        let zones = (header["zone_minutes"] ?? "").split(separator: ",").compactMap { Int($0) }
        return TodaySnapshot(
            window: start...end, maxHR: try header.int("max_hr") ?? 0, minuteSeries: minutes,
            minBPM: try header.int("min_bpm"), avgBPM: try header.int("avg_bpm"), maxBPM: try header.int("max_bpm"),
            zoneMinutes: zones.count == 5 ? zones : Array(repeating: 0, count: 5),
            restingHR: try header.int("resting_hr") ?? TodayAnalytics.defaultRestingHR,
            restingSource: header["resting_source"].flatMap(TodaySnapshot.RestingSource.init(rawValue:)) ?? .defaultValue,
            effort: try header.double("effort"), caloriesTotal: try header.int("calories_total"),
            caloriesActive: try header.int("calories_active"), hrvNow: try header.double("hrv_now_ms"),
            stressHours: stress, coverage: coverage)
    }

    private static func readNight(_ header: Header, _ blocks: [String: [[String]]]) throws -> NightSummary? {
        guard let day = header["night_day"] else { return nil }
        let stages = try (blocks["stages"] ?? []).map { row -> NightSummary.Stage in
            guard row.count == 3, let start = Int(row[0]), let end = Int(row[1]),
                  let kind = NightSummary.Stage.Kind(rawValue: row[2]) else { throw ReadError.badValue("stages") }
            return .init(start: start, end: end, kind: kind)
        }
        let drivers = try (blocks["drivers"] ?? []).map { row -> NightSummary.Driver in
            guard row.count == 3, let delta = Int(row[0]) else { throw ReadError.badValue("drivers") }
            return .init(label: row[1], valueText: row[2], deltaPoints: delta)
        }
        return NightSummary(
            day: day, sleepStart: try header.int("sleep_start"), sleepEnd: try header.int("sleep_end"),
            totalSleepMin: try header.double("total_sleep_min"), efficiency: try header.double("sleep_efficiency"),
            deepMin: try header.double("deep_min"), remMin: try header.double("rem_min"),
            lightMin: try header.double("light_min"), disturbances: try header.int("disturbances"),
            restingHR: try header.int("night_resting_hr"), hrv: try header.double("night_hrv_ms"),
            respRate: try header.double("resp_rate"), charge: try header.double("charge"),
            rest: try header.double("rest"), drivers: drivers, stages: stages)
    }

    /// `csv <name>` fenced blocks, minus their column line. The last column keeps any commas.
    private static func csvBlocks(_ lines: [String]) -> [String: [[String]]] {
        var blocks: [String: [[String]]] = [:]
        var current: String?
        var sawColumns = false
        for line in lines {
            if current == nil, line.hasPrefix("```csv ") {
                current = String(line.dropFirst("```csv ".count))
                blocks[current!] = []
                sawColumns = false
            } else if let name = current {
                if line == "```" { current = nil; continue }
                if !sawColumns { sawColumns = true; continue }
                blocks[name]?.append(line.split(separator: ",", maxSplits: csvColumns - 1,
                                                omittingEmptySubsequences: false).map(String.init))
            }
        }
        return blocks
    }
}

/// Ordered `key: value` pairs; optional values are simply left out.
struct Header {
    private(set) var lines: [String] = []
    private var values: [String: String] = [:]

    subscript(key: String) -> String? {
        get { values[key] }
        set {
            guard let newValue else { return }
            if values[key] == nil { lines.append("\(key): \(newValue)") }
            else if let index = lines.firstIndex(where: { $0.hasPrefix("\(key):") }) { lines[index] = "\(key): \(newValue)" }
            values[key] = newValue
        }
    }

    mutating func set(_ key: String, _ value: Int?) { if let value { self[key] = String(value) } }
    mutating func set(_ key: String, _ value: Double?) { if let value { self[key] = DayFile.fmt(value) } }

    func int(_ key: String) throws -> Int? {
        guard let raw = values[key] else { return nil }
        guard let value = Int(raw) else { throw DayFile.ReadError.badValue(key) }
        return value
    }

    func double(_ key: String) throws -> Double? {
        guard let raw = values[key] else { return nil }
        guard let value = Double(raw) else { throw DayFile.ReadError.badValue(key) }
        return value
    }
}
