import Foundation
import os.log

private let logger = Logger(subsystem: "com.nutrition.tracker", category: "Repository")

// Thin-client repository: local DB/cache + one backend call per action.
// All the multi-step AI/USDA logic moved to the server (see backend/ARCHITECTURE.md).
// What stays local: SwiftData (profile, norms, entries, cache), WeightParser,
// recalculation by weight, saved products, UX dialogs (in MainViewModel).
// The backend returns nutrients per 100g; the client scales them.
@MainActor
class NutritionRepository {
    static let shared = NutritionRepository()

    private let db = DatabaseManager.shared
    private let network = NetworkService.shared

    // MARK: - Date

    func todayDate() -> String {
        DatabaseManager.todayDate()
    }

    // MARK: - User Profile

    func getProfile() -> UserProfile? { db.getProfile() }

    func saveProfile(gender: String, age: Int, weight: Double, height: Double, goals: String) {
        db.saveProfile(gender: gender, age: age, weight: weight, height: height, goals: goals)
    }

    // MARK: - Daily Norms

    func getDailyNorms() -> NutrientData? {
        guard let entity = db.getDailyNorms() else { return nil }
        return db.parseNutrients(entity.nutrientsJson)
    }

    func saveDailyNorms(_ nutrients: NutrientData) {
        db.saveDailyNorms(nutrientsJson: db.encodeNutrients(nutrients))
    }

    /// Calculate daily targets via the backend (/v1/norms). Save the result locally.
    func calculateAndSaveNorms(gender: String, age: Int, weight: Double, height: Double, goals: String) async throws -> NutrientData {
        let genderForPrompt = Gender.from(stored: gender).promptValue
        let nutrients = try await network.calculateNorms(
            gender: genderForPrompt, age: age, weight: weight, height: height, goals: goals
        )
        saveDailyNorms(nutrients)
        return nutrients
    }

    // MARK: - Food Entries

    func getTodayEntries() -> [FoodEntry] { db.getEntriesForDate(todayDate()) }

    func getEntriesForDate(_ date: String) -> [FoodEntry] { db.getEntriesForDate(date) }

    func getEntriesForDateRange(start: String, end: String) -> [FoodEntry] { db.getEntriesForDateRange(start: start, end: end) }

    func getRecentDates() -> [String] { db.getRecentDates() }
    func getAllDates() -> [String] { db.getAllDates() }

    func addFoodEntry(foodName: String, foodNameEn: String = "", weightGrams: Double, nutrients: NutrientData, source: String = "manual", fromCache: Bool = false) {
        db.addFoodEntry(date: todayDate(), foodName: foodName, foodNameEn: foodNameEn, weightGrams: weightGrams, nutrients: nutrients, source: source, fromCache: fromCache)
    }

    func updateFoodEntryWeight(_ entry: FoodEntry, newWeight: Double) {
        db.updateFoodEntryWeight(entry: entry, newWeight: newWeight)
    }

    func deleteFoodEntry(_ entry: FoodEntry) { db.deleteFoodEntry(entry) }

    // MARK: - Food Cache

    func getAllCachedFoods() -> [FoodCache] { db.getAllCachedFoods() }

    func deleteCachedFood(_ entry: FoodCache) { db.deleteCachedFood(entry) }

    func deleteAllCachedFoods() { db.deleteAllCachedFoods() }

    func deleteAllBarcodeEntries() { db.deleteAllBarcodeEntries() }

    func addManualCachedFood(nameRu: String, nameEn: String, nutrients: NutrientData) {
        db.saveToCache(keyOriginal: nameRu, keyEn: nameEn, nutrientsPer100g: nutrients)
    }

    func updateCachedFoodFull(_ entry: FoodCache, nameRu: String, nameEn: String, nutrients: NutrientData) {
        db.updateCachedFoodFull(entry, nameRu: nameRu, nameEn: nameEn, nutrients: nutrients)
    }

    // MARK: - Parse Nutrients

    func parseNutrients(_ json: String) -> NutrientData {
        db.parseNutrients(json) ?? NutrientData()
    }

    /// Quick add of a saved product. Fat details are now filled by the backend
    /// on the first analysis, so here we just read the cache (no network calls).
    func enrichFatDetailsForCachedEntry(_ entry: FoodCache) async throws -> NutrientData {
        parseNutrients(entry.nutrientsPer100gJson)
    }

    // MARK: - Main Food Analysis Pipeline (text)

    /// Text analysis: local parse + cache -> a single backend call /v1/food/analyze.
    /// The client parses the weight (WeightParser). The backend returns nutrients per 100g -> we scale.
    func analyzeFoodText(_ foodDescription: String, useCache: Bool = true) async throws -> [FoodAnalysisResult] {
        let localParsed = parseLocalFoodInput(foodDescription)

        var cachedResults: [FoodAnalysisResult] = []
        var uncachedItems: [(name: String, grams: Double)] = []

        // Local cache: a hit -> take it from the device (no network).
        for (name, weight) in localParsed {
            if useCache, let cached = db.findInCache(key: name) {
                let per100g = db.parseNutrients(cached.nutrientsPer100gJson) ?? NutrientData()
                let w = weight > 0 ? weight : 100.0
                let factor = w / 100.0
                cachedResults.append(FoodAnalysisResult(
                    foodName: name, foodNameEn: cached.keyEn, weightGrams: w,
                    nutrients: per100g * factor, fromCache: true
                ))
            } else {
                uncachedItems.append((name, weight))
            }
        }

        // Everything from the local cache — no network needed.
        if uncachedItems.isEmpty && !cachedResults.isEmpty {
            return cachedResults
        }

        // Miss — one backend call.
        var results = cachedResults
        if !uncachedItems.isEmpty {
            let items = uncachedItems.map { AnalyzeItem(name: $0.name, grams: $0.grams) }
            let backendResults = try await network.analyzeFood(
                items: items, uiLang: AppLocale.languageEnglishName, useCache: useCache
            )
            if backendResults.isEmpty && cachedResults.isEmpty {
                throw APIError.apiError(message: String(localized: "Не удалось распознать продукты из описания"))
            }
            for r in backendResults {
                // Local cache: save on the device by the entered name + English key.
                db.saveToCache(keyOriginal: r.foodName, keyEn: r.foodNameEn, nutrientsPer100g: r.nutrientsPer100g)
                let factor = r.weightGrams / 100.0
                results.append(FoodAnalysisResult(
                    foodName: r.foodName, foodNameEn: r.foodNameEn, weightGrams: r.weightGrams,
                    nutrients: r.nutrientsPer100g * factor, fromCache: r.fromCache
                ))
            }
        }

        if results.isEmpty {
            throw APIError.apiError(message: String(localized: "Не удалось получить данные о нутриентах для введённых продуктов"))
        }
        return results
    }

    /// Whole dish (photo with a name change) via the backend /v1/food/dish. No USDA.
    func analyzeSingleDish(_ dishName: String, weightGrams: Double, useCache: Bool = true) async throws -> FoodAnalysisResult {
        if useCache, let cached = db.findInCache(key: dishName) {
            let per100g = db.parseNutrients(cached.nutrientsPer100gJson) ?? NutrientData()
            let factor = weightGrams / 100.0
            return FoodAnalysisResult(foodName: dishName, foodNameEn: cached.keyEn, weightGrams: weightGrams, nutrients: per100g * factor, fromCache: true)
        }
        let res = try await network.analyzeDish(dishName: dishName)
        db.saveToCache(keyOriginal: dishName, keyEn: res.foodNameEn, nutrientsPer100g: res.nutrientsPer100g)
        let factor = weightGrams / 100.0
        return FoodAnalysisResult(foodName: dishName, foodNameEn: res.foodNameEn, weightGrams: weightGrams, nutrients: res.nutrientsPer100g * factor, fromCache: false)
    }

    // MARK: - Photo Analysis

    /// Photo -> backend /v1/food/photo. Nutrients per 100g (the client scales by weight).
    func identifyAndAnalyzeFoodFromPhoto(_ imageData: Data) async throws -> FoodAnalysisResult {
        let base64 = imageData.base64EncodedString()
        let res = try await network.analyzePhoto(imageBase64: base64, uiLang: AppLocale.languageEnglishName)
        db.saveToCache(keyOriginal: res.foodName, keyEn: res.foodNameEn, nutrientsPer100g: res.nutrientsPer100g)
        return FoodAnalysisResult(foodName: res.foodName, foodNameEn: res.foodNameEn, weightGrams: res.weightGrams, nutrients: res.nutrientsPer100g, fromCache: false)
    }

    // MARK: - Barcode (OFF on the client, enrichment on the backend)

    /// Barcode: local cache -> the client queries OFF itself -> backend enriches (/v1/food/enrich).
    /// Returns nutrients per 100g.
    func lookupBarcodeWithCache(_ barcode: String) async throws -> (name: String, nutrients: NutrientData, fromCache: Bool)? {
        if let cached = db.findInCache(key: "barcode:\(barcode)") {
            let nutrients = db.parseNutrients(cached.nutrientsPer100gJson) ?? NutrientData()
            return (cached.keyEn, nutrients, true)
        }

        // The client queries OFF itself (its own IP -> the rate limit doesn't collapse).
        let response = try await network.lookupBarcode(barcode)
        guard let product = response.product else { return nil }
        let name = [product.productNameRu, product.productNameUk, product.productNameEn, product.productName, product.brands]
            .compactMap { sanitizeOFFName($0) }
            .first
        guard let name else { return nil }

        let offPer100g = nutrientsFromOFF(product.nutriments)

        // The backend enriches missing micros/fats (data from the client -> does NOT write to the shared cache).
        let enriched = try await network.enrichBarcode(name: name, nutrientsPer100g: offPer100g)

        // Local cache (device only).
        db.saveToCache(keyOriginal: name, keyEn: name, nutrientsPer100g: enriched.nutrientsPer100g)
        db.saveToCache(keyOriginal: "barcode:\(barcode)", keyEn: name, nutrientsPer100g: enriched.nutrientsPer100g)

        return (name, enriched.nutrientsPer100g, false)
    }

    func lookupBarcodeForIngredient(_ barcode: String) async -> (name: String, cache: FoodCache?)? {
        guard let result = try? await lookupBarcodeWithCache(barcode) else { return nil }
        let cache = db.findInCache(key: result.name) ?? db.findInCache(key: "barcode:\(barcode)")
        return (result.name, cache)
    }

    /// Micronutrient enrichment via the backend /v1/food/enrich (used in the photo flow
    /// when the name is unchanged). The backend fills in missing micros + fats.
    func enrichMicrosWithAIPublic(_ nutrients: NutrientData, foodNameEn: String) async -> NutrientData {
        do {
            let res = try await network.enrichBarcode(name: foodNameEn, nutrientsPer100g: nutrients)
            return res.nutrientsPer100g
        } catch {
            logger.warning("enrichMicros failed for '\(foodNameEn)': \(error.localizedDescription)")
            return nutrients
        }
    }

    // MARK: - Local helpers (stay on the client)

    /// Parse the input: split by commas, extract weight locally (WeightParser).
    private func parseLocalFoodInput(_ input: String) -> [(String, Double)] {
        let items = input.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return items.map { item in
            let parsed = WeightParser.parse(item)
            return (parsed.name, parsed.grams)
        }.filter { !$0.0.isEmpty }
    }

    /// OFF nutriments -> NutrientData (per 100g). The client parses the OFF response itself.
    // Rejects vandalized/garbage OFF product names. Real food names are short and don't contain "!".
    private func sanitizeOFFName(_ raw: String?) -> String? {
        guard let t = raw?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        if t.count > 80 || t.contains("!") { return nil }
        return t
    }

    private func nutrientsFromOFF(_ n: OFFNutriments?) -> NutrientData {
        NutrientData(
            calories: n?.energyKcal100g ?? 0, protein: n?.proteins100g ?? 0,
            fat: n?.fat100g ?? 0, saturatedFat: n?.saturatedFat100g ?? 0,
            monounsaturatedFat: n?.monounsaturatedFat100g ?? 0,
            polyunsaturatedFat: n?.polyunsaturatedFat100g ?? 0,
            cholesterol: n?.cholesterol100g ?? 0, carbs: n?.carbohydrates100g ?? 0,
            fiber: n?.fiber100g ?? 0, vitaminA: n?.vitaminA100g ?? 0,
            vitaminB1: n?.vitaminB1100g ?? 0, vitaminB2: n?.vitaminB2100g ?? 0,
            vitaminB3: n?.vitaminB3100g ?? 0, vitaminB5: n?.vitaminB5100g ?? 0,
            vitaminB6: n?.vitaminB6100g ?? 0, vitaminB7: n?.vitaminB7100g ?? 0,
            vitaminB9: n?.vitaminB9100g ?? 0, vitaminB12: n?.vitaminB12100g ?? 0,
            vitaminC: n?.vitaminC100g ?? 0, vitaminD: n?.vitaminD100g ?? 0,
            vitaminE: n?.vitaminE100g ?? 0, vitaminK: n?.vitaminK100g ?? 0,
            calcium: n?.calcium100g ?? 0, iron: n?.iron100g ?? 0,
            magnesium: n?.magnesium100g ?? 0, phosphorus: n?.phosphorus100g ?? 0,
            potassium: n?.potassium100g ?? 0, sodium: n?.sodium100g ?? 0,
            zinc: n?.zinc100g ?? 0, copper: n?.copper100g ?? 0,
            manganese: n?.manganese100g ?? 0, selenium: n?.selenium100g ?? 0,
            iodine: n?.iodine100g ?? 0
        )
    }
}
