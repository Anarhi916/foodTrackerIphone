import Foundation

// Клиент backend-прокси. Все AI/USDA-вызовы идут на наш сервер (/v1/*).
// Нутриенты приходят на 100г; клиент масштабирует сам.
// См. backend/ARCHITECTURE.md. NutrientData декодируется напрямую (snake_case совпадает).
actor NetworkService {
    static let shared = NetworkService()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 180
        session = URLSession(configuration: config)
    }

    // MARK: - Общий POST на backend

    private func post<Req: Encodable, Res: Decodable>(
        _ path: String, body: Req, timeout: TimeInterval = 120
    ) async throws -> Res {
        let url = URL(string: "\(APIConfig.backendBaseURL)\(path)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Dev-авторизация. В prod заменяется на App Attest (X-Attest-*).
        req.setValue(APIConfig.devAuthSecret, forHTTPHeaderField: "X-Dev-Auth")
        req.setValue("ios", forHTTPHeaderField: "X-Platform")
        // Пользовательская сессия (Bearer). auth-эндпоинты (/v1/auth/*) сами не требуют — там nil.
        if let access = await AuthManager.shared.accessToken {
            req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONEncoder().encode(body)

        var (data, response) = try await session.data(for: req)
        guard var http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        // 401 → пробуем обновить сессию refresh-токеном и повторить один раз.
        if http.statusCode == 401 {
            // Аккаунт удалён с другого устройства → стираем локальные данные, на логин.
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
            // Пытаемся достать message из {error, message}
            if let errObj = try? JSONDecoder().decode(BackendError.self, from: data),
               let msg = errObj.message {
                throw APIError.apiError(message: msg)
            }
            throw APIError.httpError(statusCode: http.statusCode, body: bodyStr)
        }
        return try JSONDecoder().decode(Res.self, from: data)
    }

    // MARK: - /v1/food/analyze (текст)

    func analyzeFood(items: [AnalyzeItem], uiLang: String, useCache: Bool = true) async throws -> [BackendFoodResult] {
        let body = AnalyzeRequest(items: items, uiLang: uiLang, useCache: useCache)
        let res: AnalyzeResponse = try await post("/v1/food/analyze", body: body)
        return res.results
    }

    // MARK: - /v1/food/dish (целое блюдо — фото со сменой имени)

    func analyzeDish(dishName: String) async throws -> DishResponse {
        try await post("/v1/food/dish", body: DishRequest(dishName: dishName))
    }

    // MARK: - /v1/food/photo

    func analyzePhoto(imageBase64: String, uiLang: String) async throws -> PhotoResponse {
        try await post("/v1/food/photo", body: PhotoRequest(imageBase64: imageBase64, uiLang: uiLang))
    }

    // MARK: - /v1/food/enrich (штрихкод — OFF-данные от клиента)

    func enrichBarcode(name: String, nutrientsPer100g: NutrientData) async throws -> EnrichResponse {
        try await post("/v1/food/enrich", body: EnrichRequest(name: name, nutrientsPer100g: nutrientsPer100g))
    }

    // MARK: - /v1/norms

    func calculateNorms(gender: String, age: Int, weight: Double, height: Double, goals: String) async throws -> NutrientData {
        let body = NormsRequest(gender: gender, age: age, weight: weight, height: height, goals: goals)
        let res: NormsResponse = try await post("/v1/norms", body: body)
        return res.norms
    }

    // MARK: - Auth (/v1/auth/*) — вход/обновление/выход/удаление.
    // Отдельный helper: НЕ делает refresh-петлю (иначе рекурсия при логине).

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

    // MARK: - OpenFoodFacts (штрихкод — остаётся на клиенте, свой IP)

    func lookupBarcode(_ barcode: String) async throws -> OpenFoodFactsResponse {
        let url = URL(string: "\(APIConfig.openFoodFactsBaseURL)/api/v2/product/\(barcode).json")!
        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("NutritionTracker/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        urlRequest.timeoutInterval = 15
        let (data, _) = try await session.data(for: urlRequest)
        return try JSONDecoder().decode(OpenFoodFactsResponse.self, from: data)
    }
}

// MARK: - Backend request/response модели

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

// MARK: - Auth модели

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
