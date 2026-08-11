import Foundation

// The client talks ONLY to its own backend proxy. The AI/USDA keys moved to the server
// (see backend/ARCHITECTURE.md). The OFF barcode lookup stays on the client
// (its own IP -> the rate limit doesn't collapse; there's no key — nothing to hide).
struct APIConfig {
    // MARK: - Backend
    // Production URL. On the iOS Simulator in a DEBUG build we instead hit an SSH tunnel to
    // the server's plain-HTTP port 3000 (Node listens there directly; Caddy only fronts TLS).
    // The corporate network on the dev machine blocks the production domain at the TLS/SNI
    // layer, so the simulator — routing through that machine — can't reach it otherwise.
    // On real devices and in release this always resolves to the production URL.
    //   Start the tunnel on the host:  ssh -N -L 3000:127.0.0.1:3000 root@169.58.153.252
    static let backendBaseURL: String = {
        #if targetEnvironment(simulator) && DEBUG
        return "http://localhost:3000"
        #else
        return "https://api.nutritiontracker.uk"
        #endif
    }()

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
