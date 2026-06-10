import Foundation

actor NetworkService {
    static let shared = NetworkService()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 180
        session = URLSession(configuration: config)
    }

    // MARK: - OpenRouter

    func callOpenRouter(messages: [OpenRouterMessage], models: [String]) async throws -> String {
        let model = models.first ?? "google/gemini-2.5-flash-lite"
        let request = OpenRouterRequest(
            model: model,
            messages: messages,
            temperature: 0.0,
            maxTokens: 4096
        )

        var urlRequest = URLRequest(url: URL(string: APIConfig.openRouterBaseURL)!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(APIConfig.openRouterApiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        let orResponse = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
        if let error = orResponse.error {
            throw APIError.apiError(message: error.message ?? "Unknown error")
        }

        guard let content = orResponse.choices?.first?.message?.content else {
            throw APIError.noContent
        }

        return content
    }

    func callOpenRouterWithRetry(messages: [OpenRouterMessage], models: [String], maxRetries: Int = 2) async throws -> String {
        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                let modelIdx = min(attempt, models.count - 1)
                let model = [models[modelIdx]]
                return try await callOpenRouter(messages: messages, models: model)
            } catch {
                lastError = error
                if attempt < maxRetries - 1 {
                    try await Task.sleep(nanoseconds: UInt64(1_000_000_000 * (attempt + 1)))
                }
            }
        }
        throw lastError ?? APIError.noContent
    }

    // MARK: - USDA

    func searchUSDA(query: String, pageSize: Int = 25) async throws -> UsdaSearchResponse {
        var components = URLComponents(string: APIConfig.usdaBaseURL)!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: APIConfig.usdaApiKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "pageSize", value: String(pageSize))
        ]

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.timeoutInterval = 15

        let (data, _) = try await session.data(for: urlRequest)
        return try JSONDecoder().decode(UsdaSearchResponse.self, from: data)
    }

    // MARK: - OpenFoodFacts

    func lookupBarcode(_ barcode: String) async throws -> OpenFoodFactsResponse {
        let url = URL(string: "\(APIConfig.openFoodFactsBaseURL)/api/v2/product/\(barcode).json")!
        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("NutritionTracker/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        urlRequest.timeoutInterval = 15

        let (data, _) = try await session.data(for: urlRequest)
        return try JSONDecoder().decode(OpenFoodFactsResponse.self, from: data)
    }

    func searchOFF(terms: String) async throws -> OFFSearchResponse {
        var components = URLComponents(string: "\(APIConfig.openFoodFactsBaseURL)/cgi/search.pl")!
        components.queryItems = [
            URLQueryItem(name: "search_terms", value: terms),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "5"),
            URLQueryItem(name: "fields", value: "product_name,product_name_en,nutriments")
        ]

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.setValue("NutritionTracker/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        urlRequest.timeoutInterval = 15

        let (data, _) = try await session.data(for: urlRequest)
        return try JSONDecoder().decode(OFFSearchResponse.self, from: data)
    }
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
