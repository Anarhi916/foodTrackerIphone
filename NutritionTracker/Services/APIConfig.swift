import Foundation

// The client talks ONLY to its own backend proxy. The AI/USDA keys moved to the server
// (see backend/ARCHITECTURE.md). The OFF barcode lookup stays on the client
// (its own IP -> the rate limit doesn't collapse; there's no key — nothing to hide).
struct APIConfig {
    // MARK: - Backend
    // Production URL used on real devices, simulator, and all builds.
    static let backendBaseURL = "https://api.nutritiontracker.uk"

    // Dev auth (X-Dev-Auth). In prod it's replaced by App Attest.
    // Must match DEV_AUTH_SECRET in backend/.env.
    static let devAuthSecret = "change-me-local-dev-secret"

    // MARK: - OpenFoodFacts (barcode — stays on the client)
    static let openFoodFactsBaseURL = "https://world.openfoodfacts.org"

    // MARK: - Google Sign-In (OAuth web flow via ASWebAuthenticationSession)
    // iOS OAuth client ID from the Google Cloud Console. The reversed client ID is the URL scheme.
    static let googleClientId = "634452098876-85n6iabtmhsjm12vqpkdmruk2g72qaq8.apps.googleusercontent.com"
    // reversed client id for redirect
    static let googleRedirectScheme = "com.googleusercontent.apps.634452098876-85n6iabtmhsjm12vqpkdmruk2g72qaq8"
}
