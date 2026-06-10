import Foundation

struct APIConfig {
    // MARK: - API Keys
    // API key loaded from Config.plist (not committed to git)
    static var openRouterApiKey: String {
        // 1. Try Config.plist
        if let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path),
           let key = dict["OPENROUTER_API_KEY"] as? String, !key.isEmpty {
            return key
        }
        // 2. Try Info.plist
        if let key = Bundle.main.infoDictionary?["OPENROUTER_API_KEY"] as? String, !key.isEmpty {
            return key
        }
        // 3. Try UserDefaults (set via Settings bundle or manual entry)
        if let key = UserDefaults.standard.string(forKey: "openrouter_api_key"), !key.isEmpty {
            return key
        }
        return ""
    }

    static let usdaApiKey = "FrYuRxWfygwuQbOzohHhbbI981ahQCGnPTJiDb35"

    // MARK: - Models
    static let textModels = ["google/gemini-2.5-flash-lite"]
    static let visionModels = ["google/gemini-2.5-flash-lite"]
    static let photoModels = ["google/gemini-2.5-flash"]
    static let normsModels = ["google/gemini-2.5-pro-preview"]

    // MARK: - Base URLs
    static let openRouterBaseURL = "https://openrouter.ai/api/v1/chat/completions"
    static let usdaBaseURL = "https://api.nal.usda.gov/fdc/v1/foods/search"
    static let openFoodFactsBaseURL = "https://world.openfoodfacts.org"
}
