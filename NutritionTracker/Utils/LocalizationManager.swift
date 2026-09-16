import Foundation
import SwiftUI

/// Runtime language switching without an app relaunch.
///
/// iOS normally reads the app language only at launch. To switch instantly we
/// swap the localization table that `Bundle.main` uses: a `Bundle` subclass
/// intercepts `localizedString(forKey:…)` and delegates to the selected
/// language's `.lproj` bundle. `Text("literal")` and `NSLocalizedString` route
/// through `Bundle.main.localizedString`, so they switch live. `String(localized:)`
/// (Foundation `LocalizedStringResource`) does NOT — it resolves against the
/// launch-time preferred localization and stays frozen — so for `String` values
/// (nutrient names, unit labels) use the `L(_:)` helper below, which reads the
/// selected bundle at call time. The view tree is rebuilt via `.id(language)`.
private var localizedBundleKey: UInt8 = 0

/// Localized lookup for `String` values that must honor the in-app language
/// override at call time. This is the `String(localized:)` replacement: the
/// latter freezes to the launch-time language, whereas this reads the currently
/// selected `.lproj` bundle (the same one the `Bundle.main` swizzle points at).
/// Falls back to the key itself (the Russian source string) when a translation
/// is missing, matching the string-catalog development-language fallback.
/// `nonisolated`, so it is safe to call off the main actor.
func L(_ key: String) -> String {
    LocalizationManager.currentBundle.localizedString(forKey: key, value: key, table: nil)
}

final class LocalizedMainBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = objc_getAssociatedObject(self, &localizedBundleKey) as? Bundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    /// Currently selected language tag; "" means follow the device language.
    @Published private(set) var language: String

    /// Bundle for the language currently in effect. Updated by `applyBundle` and
    /// read by the `L(_:)` helper. `nonisolated(unsafe)` because it is written
    /// only on the main actor (init / setLanguage) but read from `L(_:)` on any
    /// thread; a reference read/write is atomic on our platforms.
    nonisolated(unsafe) static var currentBundle: Bundle = .main

    private init() {
        language = AppLocale.selectedLanguageTag
        Self.applyBundle(for: language)
    }

    /// Effective two-letter code actually in use (resolves "" to the device language).
    var effectiveCode: String {
        if language.isEmpty {
            return AppLocale.deviceLanguageCode
        }
        return String(language.prefix(2))
    }

    /// Locale to inject into the SwiftUI environment for number/date formatting.
    var locale: Locale { Locale(identifier: effectiveCode) }

    func setLanguage(_ tag: String) {
        AppLocale.selectedLanguageTag = tag   // persist (also honored on cold start)
        language = tag
        Self.applyBundle(for: tag)
    }

    /// Point Bundle.main at the chosen language's string table.
    static func applyBundle(for tag: String) {
        // Upgrade Bundle.main to our intercepting subclass once.
        if !(Bundle.main is LocalizedMainBundle) {
            object_setClass(Bundle.main, LocalizedMainBundle.self)
        }
        let code = tag.isEmpty ? AppLocale.deviceLanguageCode : String(tag.prefix(2))
        let path = Bundle.main.path(forResource: code, ofType: "lproj")
        let bundle = path.flatMap { Bundle(path: $0) }
        objc_setAssociatedObject(Bundle.main, &localizedBundleKey, bundle, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        currentBundle = bundle ?? .main
    }
}
