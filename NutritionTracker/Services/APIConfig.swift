import Foundation

// Клиент ходит ТОЛЬКО на свой backend-прокси. Ключи AI/USDA переехали на сервер
// (см. backend/ARCHITECTURE.md). OFF-запрос по штрихкоду остаётся на клиенте
// (свой IP → лимит не схлопывается; ключа нет — прятать нечего).
struct APIConfig {
    // MARK: - Backend
    // dev: локальный сервер (симулятор видит localhost мака). prod: заменить на боевой URL.
    static let backendBaseURL = "http://localhost:3000"

    // Dev-авторизация (X-Dev-Auth). В prod заменяется на App Attest.
    // Должен совпадать с DEV_AUTH_SECRET в backend/.env.
    static let devAuthSecret = "change-me-local-dev-secret"

    // MARK: - OpenFoodFacts (штрихкод — остаётся на клиенте)
    static let openFoodFactsBaseURL = "https://world.openfoodfacts.org"
}
