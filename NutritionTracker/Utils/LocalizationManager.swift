import Foundation
import SwiftUI

/// Runtime language switching without an app relaunch.
///
/// iOS normally reads the app language only at launch. To switch instantly we
/// swap the localization table that `Bundle.main` uses: a `Bundle` subclass
/// intercepts `localizedString(forKey:…)` and delegates to the selected
/// language's `.lproj` bundle. Because `Text("literal")`, `String(localized:)`
/// and `NSLocalizedString` all funnel through `Bundle.main.localizedString`,
/// this covers the entire UI. The view tree is then rebuilt via `.id(language)`.
private var localizedBundleKey: UInt8 = 0

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
    }
}
