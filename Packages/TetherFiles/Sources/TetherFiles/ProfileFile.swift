import Foundation
import TetherCore

/// `profile.md`: the wearer's profile and when their history starts. Written by the phone only.
public enum ProfileFile {
    public static let relativePath = "profile.md"

    public enum ReadError: Error, Equatable { case missingHeader, badProfile }

    public static func write(profile: UserProfile, pairedAt: Int?, strapName: String? = nil) -> String {
        var lines = ["---", "tether: 1", "age: \(profile.age)", "height_cm: \(profile.heightCm)",
                     "weight_kg: \(profile.weightKg)", "sex: \(profile.sex.rawValue)"]
        if let resting = profile.restingHR { lines.append("resting_hr: \(resting)") }
        if let pairedAt { lines.append("history_starts: \(pairedAt)") }
        if let strapName, !strapName.isEmpty { lines.append("strap_name: \(strapName)") }
        lines.append("---")
        lines.append("")
        lines.append("# Profile")
        lines.append("")
        lines.append("Used for max heart rate, zones and calories. Nothing recorded before `history_starts` is kept. Tether for Mac looks for the strap named in `strap_name`.")
        return lines.joined(separator: "\n") + "\n"
    }

    public static func read(_ text: String) throws -> (profile: UserProfile, pairedAt: Int?, strapName: String?) {
        let lines = text.components(separatedBy: "\n")
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { throw ReadError.missingHeader }
        var values: [String: String] = [:]
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            values[String(line[..<colon])] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard let age = values["age"].flatMap(Int.init), let height = values["height_cm"].flatMap(Int.init),
              let weight = values["weight_kg"].flatMap(Double.init),
              let sex = values["sex"].flatMap(Sex.init(rawValue:)) else { throw ReadError.badProfile }
        let profile = UserProfile(age: age, heightCm: height, weightKg: weight,
                                  restingHR: values["resting_hr"].flatMap(Int.init), sex: sex)
        let strapName = values["strap_name"].flatMap { $0.isEmpty ? nil : $0 }
        return (profile, values["history_starts"].flatMap(Int.init), strapName)
    }
}
