import Foundation

// Backend proxy client. All AI/USDA calls go to our server (/v1/*).
// Nutrients arrive per 100g; the client scales them itself.
// See backend/ARCHITECTURE.md. NutrientData decodes directly (snake_case matches).
actor NetworkService {
    static let shared = NetworkService()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 180
        session = URLSession(configuration: config)
    }

    // MARK: - Shared POST to backend

    private func post<Req: Encodable, Res: Decodable>(
        _ path: String, body: Req, timeout: TimeInterval = 120
    ) async throws -> Res {
        let url = URL(string: "\(APIConfig.backendBaseURL)\(path)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Dev auth. In prod it's replaced by App Attest (X-Attest-*).
        req.setValue(APIConfig.devAuthSecret, forHTTPHeaderField: "X-Dev-Auth")
        req.setValue("ios", forHTTPHeaderField: "X-Platform")
        // User session (Bearer). Auth endpoints (/v1/auth/*) don't require it — nil there.
        if let access = await AuthManager.shared.accessToken {
            req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONEncoder().encode(body)

        var (data, response) = try await session.data(for: req)
        guard var http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        // 401 -> try to refresh the session with the refresh token and retry once.
        if http.statusCode == 401 {
            // Account deleted on another device -> wipe local data, go to login.
            if let errObj = try? JSONDecoder().decode(BackendError.self, from: data),
               errObj.error == "account_deleted" {
                await AuthManager.shared.handleAccountDeleted()
                throw APIError.httpError(statusCode: 401, body: "account_deleted")
            }
            if await AuthManager.shared.tryRefresh() {
                if let access = await AuthManager.shared.accessToken {
                    req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
                }
                (data, response) = try await session.data(for: req)
                guard let http2 = response as? HTTPURLResponse else { throw APIError.invalidResponse }
                http = http2
            }
        }
        guard http.statusCode == 200 else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            // Try to extract message from {error, message}
            if let errObj = try? JSONDecoder().decode(BackendError.self, from: data),
               let msg = errObj.message {
                throw APIError.apiError(message: msg)
            }
            throw APIError.httpError(statusCode: http.statusCode, body: bodyStr)
        }
        return try JSONDecoder().decode(Res.self, from: data)
    }

    // MARK: - /v1/food/analyze (text)

    func analyzeFood(items: [AnalyzeItem], uiLang: String, useCache: Bool = true) async throws -> [BackendFoodResult] {
        let body = AnalyzeRequest(items: items, uiLang: uiLang, useCache: useCache)
        let res: AnalyzeResponse = try await post("/v1/food/analyze", body: body)
        return res.results
    }

    // MARK: - /v1/food/dish (whole dish — photo with a name change)

    func analyzeDish(dishName: String) async throws -> DishResponse {
        try await post("/v1/food/dish", body: DishRequest(dishName: dishName))
    }

    // MARK: - /v1/food/photo

    func analyzePhoto(imageBase64: String, uiLang: String) async throws -> PhotoResponse {
        try await post("/v1/food/photo", body: PhotoRequest(imageBase64: imageBase64, uiLang: uiLang))
    }

    // MARK: - /v1/food/enrich (barcode — OFF data from the client)

    func enrichBarcode(name: String, nutrientsPer100g: NutrientData) async throws -> EnrichResponse {
        try await post("/v1/food/enrich", body: EnrichRequest(name: name, nutrientsPer100g: nutrientsPer100g))
    }

    // MARK: - /v1/norms

    func calculateNorms(gender: String, age: Int, weight: Double, height: Double, goals: String) async throws -> NutrientData {
        let body = NormsRequest(gender: gender, age: age, weight: weight, height: height, goals: goals)
        let res: NormsResponse = try await post("/v1/norms", body: body)
        return res.norms
    }

    // MARK: - Auth (/v1/auth/*) — sign-in/refresh/logout/delete.
    // Separate helper: does NOT do the refresh loop (otherwise recursion at login).

    private func authPost<Req: Encodable, Res: Decodable>(_ path: String, body: Req) async throws -> Res {
        let url = URL(string: "\(APIConfig.backendBaseURL)\(path)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(APIConfig.devAuthSecret, forHTTPHeaderField: "X-Dev-Auth")
        req.setValue("ios", forHTTPHeaderField: "X-Platform")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.invalidResponse
        }
        return try JSONDecoder().decode(Res.self, from: data)
    }

    func authApple(identityToken: String, nonce: String) async throws -> TokenResponse {
        try await authPost("/v1/auth/apple", body: AppleAuthRequest(identityToken: identityToken, nonce: nonce))
    }

    func authGoogle(idToken: String, nonce: String) async throws -> TokenResponse {
        try await authPost("/v1/auth/google", body: GoogleAuthRequest(idToken: idToken, nonce: nonce))
    }

    func authGoogleCode(code: String, codeVerifier: String, redirectUri: String, clientId: String) async throws -> TokenResponse {
        try await authPost("/v1/auth/google", body: GoogleCodeRequest(
            code: code, codeVerifier: codeVerifier, redirectUri: redirectUri, clientId: clientId
        ))
    }

    func refreshSession(refreshToken: String) async throws -> TokenResponse {
        try await authPost("/v1/auth/refresh", body: RefreshRequest(refreshToken: refreshToken))
    }

    func logout(refreshToken: String) async {
        _ = try? await authPost("/v1/auth/logout", body: RefreshRequest(refreshToken: refreshToken)) as OkResponse
    }

    func deleteAccount(accessToken: String) async throws {
        let url = URL(string: "\(APIConfig.backendBaseURL)/v1/auth/account")!
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue(APIConfig.devAuthSecret, forHTTPHeaderField: "X-Dev-Auth")
        req.setValue("ios", forHTTPHeaderField: "X-Platform")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.invalidResponse
        }
    }

    // MARK: - Sync (/v1/sync/*)

    func syncPush(_ payload: SyncPushRequest) async throws -> SyncPushResponse {
        try await post("/v1/sync/push", body: payload)
    }

    func syncPull(since: Int64?) async throws -> SyncPullResponse {
        var urlStr = "\(APIConfig.backendBaseURL)/v1/sync/pull"
        if let since { urlStr += "?since=\(since)" }
        let url = URL(string: urlStr)!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 60
        req.setValue(APIConfig.devAuthSecret, forHTTPHeaderField: "X-Dev-Auth")
        req.setValue("ios", forHTTPHeaderField: "X-Platform")
        if let access = await AuthManager.shared.accessToken {
            req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        }
        var (data, response) = try await session.data(for: req)
        guard var http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 {
            if let errObj = try? JSONDecoder().decode(BackendError.self, from: data),
               errObj.error == "account_deleted" {
                await AuthManager.shared.handleAccountDeleted()
                throw APIError.httpError(statusCode: 401, body: "account_deleted")
            }
            if await AuthManager.shared.tryRefresh() {
                if let access = await AuthManager.shared.accessToken {
                    req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
                }
                (data, response) = try await session.data(for: req)
                guard let http2 = response as? HTTPURLResponse else { throw APIError.invalidResponse }
                http = http2
            }
        }
        guard http.statusCode == 200 else { throw APIError.invalidResponse }
        return try JSONDecoder().decode(SyncPullResponse.self, from: data)
    }

    // MARK: - OpenFoodFacts (barcode — stays on the client, its own IP)

    func lookupBarcode(_ barcode: String) async throws -> OpenFoodFactsResponse {
        let url = URL(string: "\(APIConfig.openFoodFactsBaseURL)/api/v2/product/\(barcode).json")!
        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("NutritionTracker/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        urlRequest.timeoutInterval = 15
        let (data, _) = try await session.data(for: urlRequest)
        return try JSONDecoder().decode(OpenFoodFactsResponse.self, from: data)
    }
}

// MARK: - Backend request/response models

struct AnalyzeItem: Encodable {
    let name: String
    let grams: Double
}

struct AnalyzeRequest: Encodable {
    let items: [AnalyzeItem]
    let uiLang: String
    let useCache: Bool
}

struct BackendFoodResult: Decodable {
    let foodName: String
    let foodNameEn: String
    let weightGrams: Double
    let nutrientsPer100g: NutrientData
    let fromCache: Bool
}

struct AnalyzeResponse: Decodable {
    let results: [BackendFoodResult]
}

struct DishRequest: Encodable {
    let dishName: String
}

struct DishResponse: Decodable {
    let foodNameEn: String
    let nutrientsPer100g: NutrientData
}

struct PhotoRequest: Encodable {
    let imageBase64: String
    let uiLang: String
}

struct PhotoResponse: Decodable {
    let foodName: String
    let foodNameEn: String
    let weightGrams: Double
    let nutrientsPer100g: NutrientData
}

struct EnrichRequest: Encodable {
    let name: String
    let nutrientsPer100g: NutrientData
}

struct EnrichResponse: Decodable {
    let name: String
    let nutrientsPer100g: NutrientData
}

struct NormsRequest: Encodable {
    let gender: String
    let age: Int
    let weight: Double
    let height: Double
    let goals: String
}

struct NormsResponse: Decodable {
    let norms: NutrientData
}

struct BackendError: Decodable {
    let error: String?
    let message: String?
}

// MARK: - Auth models

struct AppleAuthRequest: Encodable {
    let identityToken: String
    let nonce: String
}

struct GoogleAuthRequest: Encodable {
    let idToken: String
    let nonce: String
}

struct GoogleCodeRequest: Encodable {
    let code: String
    let codeVerifier: String
    let redirectUri: String
    let clientId: String
}

struct RefreshRequest: Encodable {
    let refreshToken: String
}

struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
}

struct OkResponse: Decodable {
    let ok: Bool
}

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case apiError(message: String)
    case noContent
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response"
        case .httpError(let code, let body): return "HTTP \(code): \(body.prefix(200))"
        case .apiError(let msg): return msg
        case .noContent: return "No content in response"
        case .parseError(let msg): return "Parse error: \(msg)"
        }
    }
}
