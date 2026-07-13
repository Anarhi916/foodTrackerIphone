import Foundation
import UIKit

/// Centralized helpers for internationalization.
///
/// Key principle: values that are STORED (in the DB) or SENT to the AI must be
/// language-neutral canonical tokens, while what the user SEES is localized.
/// Gender and stat-period were previously Russian display strings used as both —
/// this splits them.
enum Gender: String, CaseIterable {
    case male
    case female

    /// Localized label shown in the UI.
    var displayName: String {
        switch self {
        case .male: return String(localized: "Мужской")
        case .female: return String(localized: "Женский")
        }
    }

    /// English word passed to the AI norms prompt (language-neutral).
    var promptValue: String {
        switch self {
        case .male: return "male"
        case .female: return "female"
        }
    }

    /// Parse a stored profile gender value. Accepts the new canonical tokens
    /// ("male"/"female") and legacy Russian values ("Мужской"/"Женский") so
    /// existing profiles keep working after the update.
    static func from(stored value: String) -> Gender {
        switch value.lowercased() {
        case "male", "мужской", "м", "m": return .male
        case "female", "женский", "ж", "f": return .female
        default: return .male
        }
    }
}

/// The UI language code (ISO 639-1) currently in effect, e.g. "en", "ru", "de".
/// Passed to AI prompts so food names come back in the user's language.
enum AppLocale {
    /// Raw device language (ignores the in-app override). Used as the fallback
    /// when the user hasn't explicitly selected a language.
    static var deviceLanguageCode: String {
        if let code = Locale.preferredLanguages.first,
           let lang = Locale(identifier: code).language.languageCode?.identifier {
            return lang
        }
        return "en"
    }

    /// Two-letter language code currently in effect — respects the in-app
    /// language override (set via the picker) and falls back to the device.
    static var languageCode: String {
        let tag = selectedLanguageTag
        if !tag.isEmpty { return String(tag.prefix(2)) }
        return deviceLanguageCode
    }

    /// Human-readable English name of the current language, for embedding in
    /// AI prompts (e.g. "Russian", "German"). Falls back to the code.
    static var languageEnglishName: String {
        let code = languageCode
        let names: [String: String] = [
            "ru": "Russian", "uk": "Ukrainian", "en": "English",
            "de": "German", "es": "Spanish", "fr": "French",
            "it": "Italian", "pt": "Portuguese"
        ]
        return names[code] ?? "English"
    }

    /// Native name (endonym) of the current language, for display in the UI.
    static var languageEndonym: String {
        endonym(for: languageCode)
    }

    /// Supported languages as (BCP-47 code, native endonym). Empty code = follow
    /// the device language.
    static let supported: [(code: String, endonym: String)] = [
        ("", ""), // system default — label resolved in the UI
        ("ru", "Русский"),
        ("uk", "Українська"),
        ("en", "English"),
        ("de", "Deutsch"),
        ("es", "Español"),
        ("fr", "Français"),
        ("it", "Italiano"),
        ("pt", "Português")
    ]

    static func endonym(for code: String) -> String {
        let endonyms: [String: String] = [
            "ru": "Русский", "uk": "Українська", "en": "English",
            "de": "Deutsch", "es": "Español", "fr": "Français",
            "it": "Italiano", "pt": "Português"
        ]
        return endonyms[code] ?? code.uppercased()
    }

    /// The language the user explicitly selected via the in-app picker, or "" if
    /// they never chose one (→ follow the device language). Backed by the
    /// standard `AppleLanguages` UserDefaults key that iOS reads at launch.
    static var selectedLanguageTag: String {
        get { (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.first ?? "" }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
            }
            UserDefaults.standard.synchronize()
        }
    }

    /// Opens the system Settings screen for this app (fallback path).
    @MainActor
    static func openLanguageSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Units

/// User-selectable measurement system. Weight is always STORED in grams;
/// this only affects display and input parsing.
enum UnitSystem: String {
    case metric
    case imperial

    /// Current setting, persisted in UserDefaults. Defaults to imperial for
    /// US/Liberia/Myanmar locales, metric everywhere else.
    static var current: UnitSystem {
        get {
            if let raw = UserDefaults.standard.string(forKey: "unit_system"),
               let sys = UnitSystem(rawValue: raw) {
                return sys
            }
            let region = Locale.current.region?.identifier ?? ""
            return ["US", "LR", "MM"].contains(region) ? .imperial : .metric
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "unit_system") }
    }
}

/// Conversion helpers for BODY weight (kg) and height (cm), which the profile
/// stores in metric. Imperial UI collects pounds and feet+inches instead.
enum BodyUnits {
    static let kgPerPound = 0.45359237
    static let cmPerInch = 2.54
    static let cmPerFoot = 30.48

    // Weight: kg <-> lb
    static func kgToPounds(_ kg: Double) -> Double { kg / kgPerPound }
    static func poundsToKg(_ lb: Double) -> Double { lb * kgPerPound }

    // Height: cm <-> (feet, inches)
    static func cmToFeetInches(_ cm: Double) -> (feet: Int, inches: Int) {
        let totalInches = cm / cmPerInch
        var feet = Int(totalInches / 12.0)
        var inches = Int((totalInches - Double(feet) * 12.0).rounded())
        if inches == 12 { feet += 1; inches = 0 }
        return (feet, inches)
    }
    static func feetInchesToCm(feet: Double, inches: Double) -> Double {
        feet * cmPerFoot + inches * cmPerInch
    }
}

/// Formats and parses food weights honoring the user's `UnitSystem`.
/// Grams are canonical everywhere in storage and nutrient math.
enum WeightFormat {
    static let gramsPerOunce = 28.3495
    static let gramsPerPound = 453.592

    /// Localized short unit label for grams ("г"/"g"), from the string catalog.
    static var gramUnit: String { String(localized: "г") }
    /// Localized short unit label for ounces.
    static var ounceUnit: String { String(localized: "oz") }

    /// Compact weight for tables/rows, e.g. "150 г" or "5.3 oz".
    static func short(grams: Double) -> String {
        switch UnitSystem.current {
        case .metric:
            return "\(Int(grams.rounded()))\(gramUnit)"
        case .imperial:
            let oz = grams / gramsPerOunce
            let nf = NumberFormatter()
            nf.locale = .current
            nf.maximumFractionDigits = 1
            let num = nf.string(from: NSNumber(value: oz)) ?? String(format: "%.1f", oz)
            return "\(num) \(ounceUnit)"
        }
    }

    /// Convert a user-entered weight value (in the current display unit) to grams.
    static func toGrams(displayValue: Double) -> Double {
        switch UnitSystem.current {
        case .metric: return displayValue
        case .imperial: return displayValue * gramsPerOunce
        }
    }

    /// Convert grams to the current display unit's numeric value (for editing fields).
    static func fromGrams(_ grams: Double) -> Double {
        switch UnitSystem.current {
        case .metric: return grams
        case .imperial: return grams / gramsPerOunce
        }
    }
}

/// Centralized parsing of weights out of free-text food input, across all
/// supported languages and unit systems. Replaces three duplicated regexes.
enum WeightParser {
    /// Regex capturing (number)(unit). Units cover metric (multi-language) and
    /// imperial. Group 1 = number, group 2 = unit.
    static let pattern = #"(\d+(?:[.,]\d+)?)\s*(килограмм|kilograms?|kilogramm|kilogramos|грамм|gramm|gramos|grammi|gramas?|унци[яйи]|ounces?|фунт[аовы]*|pounds?|кг|kg|гр|г|g|ml|мл|oz|lb)\b"#

    /// Convert a matched (value, unit) to grams.
    static func toGrams(value: Double, unit: String) -> Double {
        switch unit.lowercased() {
        case "кг", "kg", "килограмм", "kilogram", "kilograms", "kilogramm", "kilogramos":
            return value * 1000
        case "oz", "унция", "унции", "унцій", "ounce", "ounces":
            return value * WeightFormat.gramsPerOunce
        case "lb", "фунт", "фунта", "фунтов", "фунты", "pound", "pounds":
            return value * WeightFormat.gramsPerPound
        default: // grams / ml (treated 1:1) in any language spelling
            return value
        }
    }

    /// Compiled regex (case-insensitive). Nil only if the pattern is malformed.
    static let regex: NSRegularExpression? = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)

    /// Extract (nameWithoutWeight, grams) from a single food item string.
    static func parse(_ item: String) -> (name: String, grams: Double) {
        let range = NSRange(item.startIndex..., in: item)
        guard let match = regex?.firstMatch(in: item, range: range),
              let wRange = Range(match.range(at: 1), in: item),
              let uRange = Range(match.range(at: 2), in: item) else {
            return (item, 0)
        }
        let wStr = String(item[wRange]).replacingOccurrences(of: ",", with: ".")
        let value = Double(wStr) ?? 0
        let grams = toGrams(value: value, unit: String(item[uRange]))
        var name = item
        if let fullRange = Range(match.range, in: item) {
            name = item.replacingCharacters(in: fullRange, with: "").trimmingCharacters(in: .whitespaces)
        }
        return (name, grams)
    }
}

