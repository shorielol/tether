import Foundation

public enum Sex: String, Codable, Sendable, CaseIterable {
    case male, female

    public var label: String { self == .male ? "Male" : "Female" }
}

/// What the scoring formulas need about the wearer. Stays on the phone and in the user's own folder.
public struct UserProfile: Codable, Equatable, Sendable {
    public enum FieldError: Error, Equatable, Sendable {
        case age, height, weight, restingHR

        public var message: String {
            switch self {
            case .age: "Enter an age between 13 and 100."
            case .height: "Enter a height between 120 and 230 cm."
            case .weight: "Enter a weight between 30 and 250 kg."
            case .restingHR: "Resting HR should be between 30 and 110, or left blank."
            }
        }
    }

    public static let ageRange = 13...100
    public static let heightRange = 120...230
    public static let weightRange = 30.0...250.0
    public static let restingHRRange = 30...110
    private static let defaultsKey = "tether.profile"

    public let age: Int
    public let heightCm: Int
    public let weightKg: Double
    public let restingHR: Int?
    public let sex: Sex

    public init(age: Int, heightCm: Int, weightKg: Double, restingHR: Int?, sex: Sex) {
        self.age = age
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.restingHR = restingHR
        self.sex = sex
    }

    /// Tanaka: 208 − 0.7 × age.
    public var maxHR: Int { Int((208 - 0.7 * Double(age)).rounded()) }

    /// Turns the form's text fields into a profile. A blank resting HR means "learn it".
    public static func parse(age: String, heightCm: String, weightKg: String, restingHR: String,
                             sex: Sex) -> Result<UserProfile, FieldError> {
        guard let ageValue = Int(trimmed(age)), ageRange.contains(ageValue) else { return .failure(.age) }
        guard let height = Int(trimmed(heightCm)), heightRange.contains(height) else { return .failure(.height) }
        let weightText = trimmed(weightKg).replacingOccurrences(of: ",", with: ".")
        guard let weight = Double(weightText), weightRange.contains(weight) else { return .failure(.weight) }
        let restingText = trimmed(restingHR)
        var resting: Int?
        if !restingText.isEmpty {
            guard let value = Int(restingText), restingHRRange.contains(value) else { return .failure(.restingHR) }
            resting = value
        }
        return .success(UserProfile(age: ageValue, heightCm: height, weightKg: weight, restingHR: resting, sex: sex))
    }

    public static func load(from defaults: UserDefaults = .standard) -> UserProfile? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(UserProfile.self, from: data)
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
