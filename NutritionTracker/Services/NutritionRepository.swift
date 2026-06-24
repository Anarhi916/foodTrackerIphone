import Foundation
import os.log

private let logger = Logger(subsystem: "com.nutrition.tracker", category: "Repository")

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

    func calculateAndSaveNorms(gender: String, age: Int, weight: Double, height: Double, goals: String) async throws -> NutrientData {
        let prompt = """
You are a professional nutrition expert. Based on the following user data, calculate the recommended DAILY nutritional intake to achieve their goals.

User data:
- Gender: \(gender)
- Age: \(age) years
- Weight: \(weight) kg
- Height: \(height) cm
- Goals and activity level: \(goals)

IMPORTANT: All values MUST be in the units specified. Pay special attention:
- copper is in MG (milligrams), NOT mcg. Typical adult RDA is 0.9 mg.
- manganese is in MG. Typical adult AI is 2.3 mg.
- selenium, iodine are in MCG (micrograms).

Calculate daily norms and return ONLY a JSON object with this EXACT structure (all numbers, no text):
{"calories": <number>, "protein": <grams>, "fat": <grams>, "saturated_fat": <grams>, "monounsaturated_fat": <grams>, "polyunsaturated_fat": <grams>, "cholesterol": <mg>, "carbs": <grams>, "fiber": <grams>, "vitamin_a": <mcg>, "vitamin_b1": <mg>, "vitamin_b2": <mg>, "vitamin_b3": <mg>, "vitamin_b5": <mg>, "vitamin_b6": <mg>, "vitamin_b7": <mcg>, "vitamin_b9": <mcg>, "vitamin_b12": <mcg>, "vitamin_c": <mg>, "vitamin_d": <mcg>, "vitamin_e": <mg>, "vitamin_k": <mcg>, "calcium": <mg>, "iron": <mg>, "magnesium": <mg>, "phosphorus": <mg>, "potassium": <mg>, "sodium": <mg>, "zinc": <mg>, "copper": <mg, e.g. 0.9>, "manganese": <mg, e.g. 2.3>, "selenium": <mcg>, "iodine": <mcg>}
"""
        let messages = [OpenRouterMessage(role: "user", content: .text(prompt))]
        let text = try await network.callOpenRouterWithRetry(messages: messages, models: APIConfig.normsModels)
        var nutrients = try parseNutrientDataFromJSON(extractJSON(from: text))
        nutrients = sanitizeNormUnits(nutrients)
        saveDailyNorms(nutrients)
        return nutrients
    }

    private func sanitizeNormUnits(_ n: NutrientData) -> NutrientData {
        var result = n
        if result.copper > 10 { result.copper /= 1000.0 }
        if result.manganese > 50 { result.manganese /= 1000.0 }
        if result.selenium > 0 && result.selenium < 1 { result.selenium *= 1000.0 }
        return result
    }

    // MARK: - Food Entries

    func getTodayEntries() -> [FoodEntry] { db.getEntriesForDate(todayDate()) }

    func getEntriesForDate(_ date: String) -> [FoodEntry] { db.getEntriesForDate(date) }

    func getEntriesForDateRange(start: String, end: String) -> [FoodEntry] { db.getEntriesForDateRange(start: start, end: end) }

    func getRecentDates() -> [String] { db.getRecentDates() }
    func getAllDates() -> [String] { db.getAllDates() }

    func addFoodEntry(foodName: String, weightGrams: Double, nutrients: NutrientData, source: String = "manual", fromCache: Bool = false) {
        db.addFoodEntry(date: todayDate(), foodName: foodName, weightGrams: weightGrams, nutrients: nutrients, source: source, fromCache: fromCache)
    }

    func updateFoodEntryWeight(_ entry: FoodEntry, newWeight: Double) {
        db.updateFoodEntryWeight(entry: entry, newWeight: newWeight)
    }

    func deleteFoodEntry(_ entry: FoodEntry) { db.deleteFoodEntry(entry) }

    // MARK: - Food Cache

    func getAllCachedFoods() -> [FoodCache] { db.getAllCachedFoods() }

    func deleteCachedFood(_ entry: FoodCache) { db.deleteCachedFood(entry) }

    func deleteAllCachedFoods() { db.deleteAllCachedFoods() }

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

    // MARK: - Main Food Analysis Pipeline

    func analyzeFoodText(_ foodDescription: String, useCache: Bool = true) async throws -> [FoodAnalysisResult] {
        // Step 0: Local parse + cache lookup
        let localParsed = parseLocalFoodInput(foodDescription)
        logger.debug("Local parse: \(localParsed.count) items")

        struct PendingFood {
            var foodNameRu: String
            var foodNameEn: String
            var weight: Double
            var nutrientsPer100g: NutrientData?
            var fromCache: Bool = false
            var cacheEntityId: FoodCache?
        }

        var cachedResults: [PendingFood] = []
        var uncachedItems: [(String, Double)] = []

        for (name, weight) in localParsed {
            if useCache, let cached = db.findInCache(key: name) {
                let nutrients = db.parseNutrients(cached.nutrientsPer100gJson) ?? NutrientData()
                // Reject implausible cached data
                let isFatOnly = ["масло", "олія", "oil", "butter", "lard", "ghee", "жир", "сало"]
                    .contains(where: { name.lowercased().contains($0) })
                let implausible = !isFatOnly && nutrients.protein == 0 && nutrients.carbs == 0 && nutrients.fat > 0
                if implausible {
                    db.deleteCachedFood(cached)
                    uncachedItems.append((name, weight))
                } else {
                    cachedResults.append(PendingFood(
                        foodNameRu: name,
                        foodNameEn: cached.keyEn,
                        weight: weight > 0 ? weight : 100.0,
                        nutrientsPer100g: nutrients,
                        fromCache: true,
                        cacheEntityId: cached
                    ))
                }
            } else {
                uncachedItems.append((name, weight))
            }
        }

        // Enrich fat details for cached items
        for i in cachedResults.indices {
            if var n = cachedResults[i].nutrientsPer100g {
                n = try await enrichFatDetailsIfNeeded(n, foodNameEn: cachedResults[i].foodNameEn, cacheEntry: cachedResults[i].cacheEntityId)
                cachedResults[i].nutrientsPer100g = n
            }
        }

        // All cached
        if uncachedItems.isEmpty && !cachedResults.isEmpty {
            return cachedResults.map { item in
                let factor = item.weight / 100.0
                return FoodAnalysisResult(
                    foodName: item.foodNameRu,
                    foodNameEn: item.foodNameEn,
                    weightGrams: item.weight,
                    nutrients: (item.nutrientsPer100g ?? NutrientData()) * factor,
                    fromCache: true
                )
            }
        }

        // Step 1: AI identification
        var aiPending: [PendingFood] = []

        if !uncachedItems.isEmpty {
            let descriptionForAi = uncachedItems.map { (name, w) in
                w > 0 ? "\(name) \(Int(w))г" : name
            }.joined(separator: ", ")

            let identifyPrompt = buildIdentifyPrompt(description: descriptionForAi)
            let messages = [OpenRouterMessage(role: "user", content: .text(identifyPrompt))]
            let identifyText = try await network.callOpenRouterWithRetry(messages: messages, models: APIConfig.textModels)
            let identities = parseIdentityList(identifyText)

            if identities.isEmpty && cachedResults.isEmpty {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Не удалось распознать продукты из описания"])
            }

            for id in identities {
                let rawName = id.foodName.isEmpty ? descriptionForAi : id.foodName
                let nameRu = rawName.replacingOccurrences(of: "\\s*\\d+(?:[.,]\\d+)?\\s*(г|гр|грамм|g|ml|мл|кг|kg)\\b", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                let nameEn = id.foodNameEn.isEmpty ? id.foodName : id.foodNameEn
                let weight = id.weightGrams > 0 ? id.weightGrams : 100.0

                // Try cache by English key
                if useCache, let cachedByEn = db.findInCache(key: nameEn) {
                    var enriched = db.parseNutrients(cachedByEn.nutrientsPer100gJson) ?? NutrientData()
                    enriched = try await enrichFatDetailsIfNeeded(enriched, foodNameEn: nameEn, cacheEntry: cachedByEn)
                    db.saveToCache(keyOriginal: nameRu, keyEn: nameEn, nutrientsPer100g: enriched)
                    cachedResults.append(PendingFood(
                        foodNameRu: nameRu, foodNameEn: nameEn,
                        weight: weight, nutrientsPer100g: enriched, fromCache: true
                    ))
                } else {
                    aiPending.append(PendingFood(foodNameRu: nameRu, foodNameEn: nameEn, weight: weight))
                }
            }

            // Step 2: USDA lookup
            for i in aiPending.indices {
                let item = aiPending[i]
                // For dairy with explicit % fat (e.g. "творог 5%"), strip the percent
                // from the English query — USDA doesn't index RU/UA fat grades, so we
                // search for the base product and later correct macros via AI.
                let isDairyWithPercent = isDairyWithFatPercent(item.foodNameRu)
                let foodNameEnForSearch = isDairyWithPercent ? stripFatPercent(from: item.foodNameEn) : item.foodNameEn
                do {
                    let negationCleaned = foodNameEnForSearch
                        .replacingOccurrences(of: "\\b(without|no|not|minus|free\\s+from)\\s+\\w+", with: "", options: .regularExpression)
                        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                        .trimmingCharacters(in: .whitespaces)

                    let significantWords = negationCleaned.lowercased().components(separatedBy: .whitespaces)
                        .filter { $0.count >= 3 && !["with", "and", "the", "from", "for"].contains($0) }
                    if significantWords.count > 5 { continue }

                    let usdaResult = try await network.searchUSDA(query: negationCleaned.isEmpty ? foodNameEnForSearch : negationCleaned)
                    if let nutrients = selectBestUSDAResult(usdaResult, query: foodNameEnForSearch, negationCleaned: negationCleaned) {
                        aiPending[i].nutrientsPer100g = nutrients
                    }
                } catch {
                    logger.warning("USDA search failed for '\(item.foodNameEn)': \(error.localizedDescription)")
                }
            }

            // Step 3: Batch AI for items without USDA data
            let needAi = aiPending.enumerated().filter { $0.element.nutrientsPer100g == nil }
            if !needAi.isEmpty {
                do {
                    let foodsList = needAi.enumerated().map { (i, pair) in
                        "\(i + 1). \(pair.element.foodNameEn) (per 100g)"
                    }.joined(separator: "\n")
                    let batchPrompt = buildBatchNutrientPrompt(foodsList: foodsList, count: needAi.count)
                    let messages = [OpenRouterMessage(role: "user", content: .text(batchPrompt))]
                    let text = try await network.callOpenRouterWithRetry(messages: messages, models: APIConfig.textModels)
                    let parsed = parseBatchNutrientArray(extractJSON(from: text))
                    for (listIdx, pair) in needAi.enumerated() {
                        if listIdx < parsed.count {
                            aiPending[pair.offset].nutrientsPer100g = nutrientDataFromMap(parsed[listIdx])
                        }
                    }
                } catch {
                    logger.warning("Batch AI failed: \(error.localizedDescription)")
                }
            }

            // Step 4: Batch micro fill for USDA items
            let usdaItemsNeedMicros = aiPending.enumerated().filter { pair in
                guard let n = pair.element.nutrientsPer100g else { return false }
                return n.iodine < 0.01
            }
            if !usdaItemsNeedMicros.isEmpty {
                do {
                    let foodsList = usdaItemsNeedMicros.enumerated().map { (i, pair) in
                        "\(i + 1). \(pair.element.foodNameEn)"
                    }.joined(separator: "\n")
                    let microPrompt = buildMicroFillPrompt(foodsList: foodsList, count: usdaItemsNeedMicros.count)
                    let messages = [OpenRouterMessage(role: "user", content: .text(microPrompt))]
                    let text = try await network.callOpenRouterWithRetry(messages: messages, models: APIConfig.textModels)
                    let parsed = parseBatchNutrientArray(extractJSON(from: text))
                    for (listIdx, pair) in usdaItemsNeedMicros.enumerated() {
                        if listIdx < parsed.count, var n = aiPending[pair.offset].nutrientsPer100g {
                            let m = parsed[listIdx]
                            n = fillMissingMicros(n, from: m)
                            aiPending[pair.offset].nutrientsPer100g = n
                        }
                    }
                } catch {
                    logger.warning("Batch micro fill failed: \(error.localizedDescription)")
                }
            }

            // Step 5: Last resort for remaining items
            for i in aiPending.indices {
                if aiPending[i].nutrientsPer100g == nil {
                    do {
                        let result = try await analyzeSingleDish(aiPending[i].foodNameRu, weightGrams: 100.0, useCache: false)
                        aiPending[i].nutrientsPer100g = result.nutrients
                    } catch {
                        logger.warning("Last resort failed for '\(aiPending[i].foodNameRu)'")
                    }
                }
                // For dairy with explicit %, override macros via AI using GOST reference data
                // (USDA gave us micronutrients for the base product, but macros for the wrong fat grade).
                if let per100g = aiPending[i].nutrientsPer100g,
                   isDairyWithFatPercent(aiPending[i].foodNameRu) {
                    aiPending[i].nutrientsPer100g = await correctDairyMacrosWithAI(per100g, foodNameRu: aiPending[i].foodNameRu)
                }
                // Cache
                if let per100g = aiPending[i].nutrientsPer100g {
                    db.saveToCache(keyOriginal: aiPending[i].foodNameRu, keyEn: aiPending[i].foodNameEn, nutrientsPer100g: per100g)
                }
            }
        }

        // Build results
        let allItems = cachedResults + aiPending
        let results: [FoodAnalysisResult] = allItems.compactMap { item in
            guard let per100g = item.nutrientsPer100g,
                  per100g.calories > 0 || per100g.protein > 0 || per100g.fat > 0 || per100g.carbs > 0 else {
                return nil
            }
            let factor = item.weight / 100.0
            return FoodAnalysisResult(
                foodName: item.foodNameRu,
                foodNameEn: item.foodNameEn,
                weightGrams: item.weight,
                nutrients: per100g * factor,
                fromCache: item.fromCache
            )
        }

        if results.isEmpty {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Не удалось получить данные о нутриентах для введённых продуктов"])
        }
        return results
    }

    // MARK: - Single Dish Analysis

    func analyzeSingleDish(_ dishName: String, weightGrams: Double, useCache: Bool = true) async throws -> FoodAnalysisResult {
        if useCache, let cached = db.findInCache(key: dishName) {
            var nutrients = db.parseNutrients(cached.nutrientsPer100gJson) ?? NutrientData()
            nutrients = try await enrichFatDetailsIfNeeded(nutrients, foodNameEn: cached.keyEn, cacheEntry: cached)
            let factor = weightGrams / 100.0
            return FoodAnalysisResult(foodName: dishName, foodNameEn: cached.keyEn, weightGrams: weightGrams, nutrients: nutrients * factor, fromCache: true)
        }

        let prompt = """
You are a professional nutritionist. Provide nutritional values PER 100 GRAMS for this COMPLETE DISH (do NOT split into ingredients):
"\(dishName)"

Return ONLY a JSON object with these fields:
{"food_name_en": "<English translation>", "calories": <kcal>, "protein": <g>, "fat": <g>, "saturated_fat": <g>, "monounsaturated_fat": <g>, "polyunsaturated_fat": <g>, "cholesterol": <mg>, "carbs": <g>, "fiber": <g>, "vitamin_a": <mcg>, "vitamin_b1": <mg>, "vitamin_b2": <mg>, "vitamin_b3": <mg>, "vitamin_b5": <mg>, "vitamin_b6": <mg>, "vitamin_b7": <mcg>, "vitamin_b9": <mcg>, "vitamin_b12": <mcg>, "vitamin_c": <mg>, "vitamin_d": <mcg>, "vitamin_e": <mg>, "vitamin_k": <mcg>, "calcium": <mg>, "iron": <mg>, "magnesium": <mg>, "phosphorus": <mg>, "potassium": <mg>, "sodium": <mg>, "zinc": <mg>, "copper": <mg>, "manganese": <mg>, "selenium": <mcg>, "iodine": <mcg>}
"""
        let messages = [OpenRouterMessage(role: "user", content: .text(prompt))]
        let text = try await network.callOpenRouterWithRetry(messages: messages, models: APIConfig.textModels)
        let json = extractJSON(from: text)
        let map = try parseJSONMap(json)
        let nameEn = (map["food_name_en"] as? String) ?? dishName
        var per100g = nutrientDataFromMap(map)
        if isDairyWithFatPercent(dishName) {
            per100g = await correctDairyMacrosWithAI(per100g, foodNameRu: dishName)
        }

        db.saveToCache(keyOriginal: dishName, keyEn: nameEn, nutrientsPer100g: per100g)

        let factor = weightGrams / 100.0
        return FoodAnalysisResult(foodName: dishName, foodNameEn: nameEn, weightGrams: weightGrams, nutrients: per100g * factor, fromCache: false)
    }

    // MARK: - Photo Analysis

    func identifyAndAnalyzeFoodFromPhoto(_ imageData: Data) async throws -> FoodAnalysisResult {
        let base64 = imageData.base64EncodedString()
        let prompt = """
You are a professional nutritionist. Look at this food photo and:
1. Identify the dish/food name IN RUSSIAN (detailed, including ingredients)
2. Estimate total portion weight in grams
3. Provide nutritional values PER 100 GRAMS for this complete dish

Return ONLY a JSON object:
{"food_name": "<название на русском>", "food_name_en": "<English translation>", "weight_grams": <number>, "calories": <kcal>, "protein": <g>, "fat": <g>, "saturated_fat": <g>, "monounsaturated_fat": <g>, "polyunsaturated_fat": <g>, "cholesterol": <mg>, "carbs": <g>, "fiber": <g>, "vitamin_a": <mcg>, "vitamin_b1": <mg>, "vitamin_b2": <mg>, "vitamin_b3": <mg>, "vitamin_b5": <mg>, "vitamin_b6": <mg>, "vitamin_b7": <mcg>, "vitamin_b9": <mcg>, "vitamin_b12": <mcg>, "vitamin_c": <mg>, "vitamin_d": <mcg>, "vitamin_e": <mg>, "vitamin_k": <mcg>, "calcium": <mg>, "iron": <mg>, "magnesium": <mg>, "phosphorus": <mg>, "potassium": <mg>, "sodium": <mg>, "zinc": <mg>, "copper": <mg>, "manganese": <mg>, "selenium": <mcg>, "iodine": <mcg>}
"""
        let contentParts: [OpenRouterContentPart] = [
            OpenRouterContentPart(type: "text", text: prompt, imageUrl: nil),
            OpenRouterContentPart(type: "image_url", text: nil, imageUrl: OpenRouterImageUrl(url: "data:image/jpeg;base64,\(base64)"))
        ]
        let messages = [OpenRouterMessage(role: "user", content: .parts(contentParts))]
        let text = try await network.callOpenRouterWithRetry(messages: messages, models: APIConfig.photoModels)
        let json = extractJSON(from: text)
        let map = try parseJSONMap(json)

        let foodName = (map["food_name"] as? String) ?? "Блюдо"
        let nameEn = (map["food_name_en"] as? String) ?? foodName
        let weightGrams = (map["weight_grams"] as? NSNumber)?.doubleValue ?? 200.0
        let per100g = nutrientDataFromMap(map)

        db.saveToCache(keyOriginal: foodName, keyEn: nameEn, nutrientsPer100g: per100g)

        return FoodAnalysisResult(foodName: foodName, foodNameEn: nameEn, weightGrams: weightGrams, nutrients: per100g, fromCache: false)
    }

    // MARK: - Barcode

    func lookupBarcodeWithCache(_ barcode: String) async throws -> (name: String, nutrients: NutrientData, fromCache: Bool)? {
        // Check cache
        if let cached = db.findInCache(key: "barcode:\(barcode)") {
            let nutrients = db.parseNutrients(cached.nutrientsPer100gJson) ?? NutrientData()
            let enriched = try await enrichFatDetailsIfNeeded(nutrients, foodNameEn: cached.keyEn, cacheEntry: cached)
            return (cached.keyEn, enriched, true)
        }

        // OFF API
        let response = try await network.lookupBarcode(barcode)
        guard let product = response.product else { return nil }
        let name = product.productName ?? product.productNameEn ?? product.brands ?? "Неизвестный продукт"
        let n = product.nutriments

        var per100g = NutrientData(
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

        // If zero macros, fall back to AI
        if per100g.calories == 0 && per100g.protein == 0 && per100g.fat == 0 && per100g.carbs == 0 {
            let aiResult = try await analyzeSingleDish(name, weightGrams: 100.0, useCache: false)
            per100g = aiResult.nutrients
        }

        // Enrich fat details
        per100g = try await enrichFatDetailsIfNeeded(per100g, foodNameEn: name, cacheEntry: nil)

        // Cache
        db.saveToCache(keyOriginal: name, keyEn: name, nutrientsPer100g: per100g)
        db.saveToCache(keyOriginal: "barcode:\(barcode)", keyEn: name, nutrientsPer100g: per100g)

        return (name, per100g, false)
    }

    // MARK: - Supplement

    func lookupSupplementBarcode(_ barcode: String) async throws -> SupplementResult? {
        let cacheKey = "supplement:\(barcode)"
        if let cached = db.findInCache(key: cacheKey) {
            let nutrients = db.parseNutrients(cached.nutrientsPer100gJson) ?? NutrientData()
            let servingSize = cached.keyOriginal
                .replacingOccurrences(of: "supplement:\(barcode):", with: "")
            return SupplementResult(name: cached.keyEn, nutrientsPerServing: nutrients, servingSize: servingSize.isEmpty ? "1 порция" : servingSize, fromCache: true)
        }

        let response = try await network.lookupBarcode(barcode)
        guard let product = response.product else { return nil }
        let name = product.productName ?? product.productNameEn ?? product.brands ?? "Dietary supplement"
        let servingSize = product.servingSize ?? "1 порция"

        let perServing = try await getSupplementNutrientsFromAI(name: name, servingSize: servingSize, barcode: barcode)

        db.saveToCache(keyOriginal: "supplement:\(barcode):\(servingSize)", keyEn: name, nutrientsPer100g: perServing)

        return SupplementResult(name: name, nutrientsPerServing: perServing, servingSize: servingSize, fromCache: false)
    }

    private func getSupplementNutrientsFromAI(name: String, servingSize: String, barcode: String) async throws -> NutrientData {
        let prompt = """
You are a nutrition database expert. For the dietary supplement described below, provide the nutrients PER ONE SERVING.
Product: \(name)
Serving size: \(servingSize)
Barcode: \(barcode)

IMPORTANT: Use correct units. Vitamins in mcg or mg as appropriate. Most supplements have 0 calories/protein/fat/carbs unless it's a protein supplement.

Return ONLY a JSON object:
{"calories": <kcal>, "protein": <g>, "fat": <g>, "carbs": <g>, "fiber": <g>, "saturated_fat": <g>, "monounsaturated_fat": <g>, "polyunsaturated_fat": <g>, "cholesterol": <mg>, "vitamin_a": <mcg>, "vitamin_b1": <mg>, "vitamin_b2": <mg>, "vitamin_b3": <mg>, "vitamin_b5": <mg>, "vitamin_b6": <mg>, "vitamin_b7": <mcg>, "vitamin_b9": <mcg>, "vitamin_b12": <mcg>, "vitamin_c": <mg>, "vitamin_d": <mcg>, "vitamin_e": <mg>, "vitamin_k": <mcg>, "calcium": <mg>, "iron": <mg>, "magnesium": <mg>, "phosphorus": <mg>, "potassium": <mg>, "sodium": <mg>, "zinc": <mg>, "copper": <mg>, "manganese": <mg>, "selenium": <mcg>, "iodine": <mcg>}
"""
        let messages = [OpenRouterMessage(role: "user", content: .text(prompt))]
        let text = try await network.callOpenRouterWithRetry(messages: messages, models: APIConfig.textModels)
        return try parseNutrientDataFromJSON(extractJSON(from: text))
    }

    // MARK: - Fat Enrichment

    private func enrichFatDetailsIfNeeded(_ nutrients: NutrientData, foodNameEn: String, cacheEntry: FoodCache?) async throws -> NutrientData {
        guard nutrients.fat > 0 else { return nutrients }
        guard nutrients.monounsaturatedFat == 0 && nutrients.polyunsaturatedFat == 0 else { return nutrients }

        var current = nutrients

        // Step 1: USDA
        do {
            let usdaResult = try await network.searchUSDA(query: foodNameEn)
            if let food = usdaResult.foods?.first(where: { f in
                f.foodNutrients?.contains(where: { $0.nutrientId == UsdaFoodNutrient.ENERGY && ($0.value ?? 0) > 0 }) == true
            }) {
                var nMap: [Int: Double] = [:]
                for fn in food.foodNutrients ?? [] {
                    if let id = fn.nutrientId, let v = fn.value { nMap[id] = v }
                }
                if current.saturatedFat == 0 { current.saturatedFat = nMap[UsdaFoodNutrient.SATURATED_FAT] ?? 0 }
                if current.monounsaturatedFat == 0 { current.monounsaturatedFat = nMap[UsdaFoodNutrient.MONOUNSATURATED_FAT] ?? 0 }
                if current.polyunsaturatedFat == 0 { current.polyunsaturatedFat = nMap[UsdaFoodNutrient.POLYUNSATURATED_FAT] ?? 0 }
                if current.cholesterol == 0 { current.cholesterol = nMap[UsdaFoodNutrient.CHOLESTEROL] ?? 0 }
            }
        } catch {}

        // Step 2: AI if still missing
        if current.monounsaturatedFat == 0 || current.polyunsaturatedFat == 0 {
            let aiPrompt = """
For the food product "\(foodNameEn)" with total fat \(nutrients.fat)g per 100g, estimate the fat breakdown.
Return ONLY a JSON object:
{"saturated_fat": <grams>, "monounsaturated_fat": <grams>, "polyunsaturated_fat": <grams>, "cholesterol": <mg>}
Rules:
- CRITICAL: saturated_fat + monounsaturated_fat + polyunsaturated_fat MUST be <= \(nutrients.fat)g (total fat)
- Each value must be >= 0 and individually less than total fat (\(nutrients.fat)g)
- cholesterol is in mg (milligrams), typical range 0-300mg per 100g
- Use established nutritional data for this food
"""
            do {
                let messages = [OpenRouterMessage(role: "user", content: .text(aiPrompt))]
                let text = try await network.callOpenRouterWithRetry(messages: messages, models: APIConfig.textModels)
                let map = try parseJSONMap(extractJSON(from: text))
                if current.saturatedFat == 0 { current.saturatedFat = (map["saturated_fat"] as? NSNumber)?.doubleValue ?? 0 }
                if current.monounsaturatedFat == 0 { current.monounsaturatedFat = (map["monounsaturated_fat"] as? NSNumber)?.doubleValue ?? 0 }
                if current.polyunsaturatedFat == 0 { current.polyunsaturatedFat = (map["polyunsaturated_fat"] as? NSNumber)?.doubleValue ?? 0 }
                if current.cholesterol == 0 { current.cholesterol = (map["cholesterol"] as? NSNumber)?.doubleValue ?? 0 }
            } catch {}
        }

        // Validate: fat breakdown must not exceed total fat
        let totalFat = current.fat
        let fatSum = current.saturatedFat + current.monounsaturatedFat + current.polyunsaturatedFat
        if fatSum > totalFat && totalFat > 0 {
            let scale = totalFat / fatSum
            current.saturatedFat *= scale
            current.monounsaturatedFat *= scale
            current.polyunsaturatedFat *= scale
        }
        // Each component individually must not exceed total fat
        current.saturatedFat = min(current.saturatedFat, totalFat)
        current.monounsaturatedFat = min(current.monounsaturatedFat, totalFat)
        current.polyunsaturatedFat = min(current.polyunsaturatedFat, totalFat)

        // Sentinel
        if current.monounsaturatedFat == 0 && current.polyunsaturatedFat == 0 {
            current.monounsaturatedFat = 0.0001
            current.polyunsaturatedFat = 0.0001
        }

        // Update cache
        if current != nutrients, let entry = cacheEntry {
            db.updateCachedFoodNutrients(entry, nutrients: current)
        }

        return current
    }

    // MARK: - USDA Selection

    private func selectBestUSDAResult(_ response: UsdaSearchResponse, query: String, negationCleaned: String) -> NutrientData? {
        let queryWords = negationCleaned.lowercased().components(separatedBy: .whitespaces).filter { $0.count >= 3 }
        let cookingTerms: Set<String> = ["porridge", "cooked", "boiled", "fried", "baked", "grilled", "steamed", "roasted", "stewed", "casserole", "braised", "raw", "fresh", "dried", "frozen", "canned", "smoked", "pickled", "mashed", "sliced", "chopped", "minced", "ground", "whole", "hot", "cold", "warm", "thick", "thin", "light", "heavy", "homemade", "instant", "regular", "plain", "with", "without"]
        let mainWord = queryWords.filter { !cookingTerms.contains($0) }.max(by: { $0.count < $1.count }) ?? queryWords.max(by: { $0.count < $1.count })

        guard let mainWord else { return nil }

        func wordForms(_ word: String) -> [String] {
            var forms = [word, word + "s", word + "es"]
            if word.hasSuffix("y") && word.count > 2 { forms.append(String(word.dropLast()) + "ies") }
            if word.hasSuffix("ies") && word.count > 4 { forms.append(String(word.dropLast(3)) + "y") }
            if word.hasSuffix("es") && word.count > 3 { forms.append(String(word.dropLast(2))) }
            if word.hasSuffix("s") && !word.hasSuffix("ss") && word.count > 2 { forms.append(String(word.dropLast())) }
            return forms
        }

        func descContains(_ desc: String, _ word: String) -> Bool {
            wordForms(word).contains(where: { desc.contains($0) })
        }

        func isRelevant(_ description: String?) -> Bool {
            guard let desc = description?.lowercased() else { return false }
            guard descContains(desc, mainWord) else { return false }
            let secondaryWords = queryWords.filter { $0 != mainWord }
            if queryWords.count >= 3 && !secondaryWords.isEmpty {
                return secondaryWords.contains(where: { descContains(desc, $0) })
            }
            return true
        }

        let foodsWithCalories = response.foods?.filter { f in
            f.foodNutrients?.contains(where: { $0.nutrientId == UsdaFoodNutrient.ENERGY && ($0.value ?? 0) > 0 }) == true && isRelevant(f.description)
        } ?? []

        func scoreFood(_ f: UsdaFood) -> Int {
            let desc = (f.description ?? "").lowercased()
            let typePriority: Int = {
                switch f.dataType {
                case "Survey (FNDDS)": return 200
                case "SR Legacy": return 150
                case "Branded": return 50
                default: return 100
                }
            }()
            let wordMatchBonus = queryWords.filter { descContains(desc, $0) }.count * 30
            let queryImpliesCooked = queryWords.contains(where: { ["porridge", "cooked", "boiled", "steamed", "stewed", "braised", "baked", "fried", "grilled", "roasted"].contains($0) })
            let isActuallyRaw = desc.contains("raw") && !desc.contains("from raw")
            let plainBonus: Int = {
                if desc.contains(", nfs") { return 25 }
                if queryImpliesCooked && desc.contains("cooked") { return 30 }
                if queryImpliesCooked && isActuallyRaw { return -20 }
                if !queryImpliesCooked && isActuallyRaw { return 20 }
                return 0
            }()

            let queryLower = query.lowercased()
            let dishTypeWords: Set<String> = ["pie", "cake", "cobbler", "turnover", "crisp", "crumble", "tart", "strudel", "juice", "jam", "jelly", "preserve", "sauce", "syrup", "compote", "filling", "ice cream", "yogurt", "smoothie", "shake", "milkshake", "muffin", "scone", "bread", "cookie", "brownie", "pudding", "parfait", "dried", "candied", "glazed", "chocolate"]
            let derivativePenalty = dishTypeWords.contains(where: { desc.contains($0) && !queryLower.contains($0) }) ? -80 : 0

            let skinBonus: Int = {
                let querySkin = queryLower.contains("skin")
                if !querySkin && (queryLower.contains("chicken") || queryLower.contains("breast") || queryLower.contains("thigh")) {
                    if desc.contains("skinless") || desc.contains("meat only") { return 60 }
                    if desc.contains("skin eaten") || desc.contains("with skin") { return -40 }
                }
                return 0
            }()

            return typePriority + wordMatchBonus + plainBonus + derivativePenalty + skinBonus
        }

        guard let best = foodsWithCalories.sorted(by: { scoreFood($0) > scoreFood($1) }).first,
              let foodNutrients = best.foodNutrients else { return nil }

        var nMap: [Int: Double] = [:]
        for fn in foodNutrients {
            if let id = fn.nutrientId, let v = fn.value { nMap[id] = v }
        }

        let N = UsdaFoodNutrient.self
        var per100g = NutrientData(
            calories: nMap[N.ENERGY] ?? 0, protein: nMap[N.PROTEIN] ?? 0, fat: nMap[N.FAT] ?? 0,
            saturatedFat: nMap[N.SATURATED_FAT] ?? 0, monounsaturatedFat: nMap[N.MONOUNSATURATED_FAT] ?? 0,
            polyunsaturatedFat: nMap[N.POLYUNSATURATED_FAT] ?? 0, cholesterol: nMap[N.CHOLESTEROL] ?? 0,
            carbs: nMap[N.CARBS] ?? 0, fiber: nMap[N.FIBER] ?? 0,
            vitaminA: nMap[N.VITAMIN_A] ?? 0, vitaminB1: nMap[N.VITAMIN_B1] ?? 0,
            vitaminB2: nMap[N.VITAMIN_B2] ?? 0, vitaminB3: nMap[N.VITAMIN_B3] ?? 0,
            vitaminB5: nMap[N.VITAMIN_B5] ?? 0, vitaminB6: nMap[N.VITAMIN_B6] ?? 0,
            vitaminB7: nMap[N.VITAMIN_B7] ?? 0, vitaminB9: nMap[N.VITAMIN_B9] ?? 0,
            vitaminB12: nMap[N.VITAMIN_B12] ?? 0, vitaminC: nMap[N.VITAMIN_C] ?? 0,
            vitaminD: nMap[N.VITAMIN_D] ?? 0, vitaminE: nMap[N.VITAMIN_E] ?? 0,
            vitaminK: nMap[N.VITAMIN_K] ?? 0, calcium: nMap[N.CALCIUM] ?? 0,
            iron: nMap[N.IRON] ?? 0, magnesium: nMap[N.MAGNESIUM] ?? 0,
            phosphorus: nMap[N.PHOSPHORUS] ?? 0, potassium: nMap[N.POTASSIUM] ?? 0,
            sodium: nMap[N.SODIUM] ?? 0, zinc: nMap[N.ZINC] ?? 0,
            copper: nMap[N.COPPER] ?? 0, manganese: nMap[N.MANGANESE] ?? 0,
            selenium: nMap[N.SELENIUM] ?? 0, iodine: nMap[N.IODINE] ?? 0
        )

        // Flour enrichment correction
        let flourKeywords = ["pierogi", "dumpling", "pelmeni", "ravioli", "bread", "roll", "bun", "tortilla", "pasta", "noodle", "spaghetti", "pancake", "crepe", "waffle", "cake", "cookie", "muffin", "pie", "pastry", "croissant", "flour", "cereal", "cornmeal", "porridge"]
        let foodDesc = ((best.description ?? "") + " " + query).lowercased()
        if flourKeywords.contains(where: { foodDesc.contains($0) }) {
            per100g.vitaminB1 *= 0.17
            per100g.vitaminB2 *= 0.10
            per100g.vitaminB3 *= 0.22
            per100g.vitaminB9 *= 0.17
            per100g.iron *= 0.26
        }

        // Sanity check
        let macroCalories = per100g.protein * 4 + per100g.fat * 9 + per100g.carbs * 4
        let isPureFat = ["oil", "butter", "lard", "ghee", "shortening"].contains(where: { negationCleaned.lowercased().contains($0) })
        let macroPlausible = isPureFat || !(per100g.protein == 0 && per100g.carbs == 0 && per100g.fat > 0)
        let sane = per100g.calories > 0 && macroCalories <= per100g.calories * 1.3 && macroPlausible

        return sane ? per100g : nil
    }

    // MARK: - Helpers

    /// Список ключевых слов для молочных продуктов с гост-стандартом жирности
    /// (где X% в названии = X граммов жира на 100г продукта).
    /// Твёрдые сыры исключены — там % это жирность в сухом веществе.
    private let dairyWithFatPercentKeywords: [String] = [
        "творог", "творожн", "сирок", "сырок", "сир знежирен", "сир нежирн", "сир кисломолочн",
        "молоко", "сметана", "кефир", "ряженка", "ряжанка", "йогурт", "сливки", "вершки",
        "простокваша", "ацидофилин", "айран", "тан", "мацони", "снежок", "бифидок"
    ]

    /// true если в названии явно указан % жирности dairy-продукта по ГОСТ.
    /// Твёрдые сыры исключаются.
    private func isDairyWithFatPercent(_ foodName: String) -> Bool {
        let lower = foodName.lowercased()
        let isHardCheese = (lower.contains("сыр") || lower.contains("сир") ||
                            (lower.contains("cheese") && !lower.contains("cottage")))
                           && !dairyWithFatPercentKeywords.contains(where: { lower.contains($0) })
        if isHardCheese { return false }
        guard dairyWithFatPercentKeywords.contains(where: { lower.contains($0) }) else { return false }
        return extractFatPercent(from: foodName) != nil
    }

    /// Извлекает указанный % жирности из названия продукта (0..100).
    private func extractFatPercent(from foodName: String) -> Double? {
        let pattern = #"(\d+(?:[.,]\d+)?)\s*%"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: foodName, range: NSRange(foodName.startIndex..., in: foodName)),
              let range = Range(match.range(at: 1), in: foodName) else { return nil }
        let raw = String(foodName[range]).replacingOccurrences(of: ",", with: ".")
        guard let percent = Double(raw), percent >= 0, percent <= 100 else { return nil }
        return percent
    }

    /// Убирает указание % жирности из названия — чтобы искать в USDA по общему имени продукта.
    /// "cottage cheese 5%" → "cottage cheese", "молоко 2.5%" → "молоко".
    private func stripFatPercent(from foodName: String) -> String {
        let pattern = #"\s*\d+(?:[.,]\d+)?\s*%\s*"#
        let stripped = foodName.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        return stripped.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Корректирует БЕЛОК/ЖИР/УГЛЕВОДЫ для dairy-продукта с указанным % жирности
    /// через AI-запрос. USDA возвращает данные для другой разновидности
    /// (например, для творога — cottage cheese 2%, у которого белок ~12г вместо ~17г),
    /// поэтому макронутриенты переопределяем по ГОСТ через AI.
    /// Микронутриенты (витамины, минералы) сохраняем из USDA.
    private func correctDairyMacrosWithAI(_ nutrients: NutrientData, foodNameRu: String) async -> NutrientData {
        guard let percent = extractFatPercent(from: foodNameRu) else { return nutrients }

        let prompt = """
You are a professional nutritionist. The user entered a dairy product following the Russian/Ukrainian GOST standard, where the percentage in the name is grams of fat per 100g of the final product (NOT % of milkfat in the source milk, NOT USDA cottage cheese variants).

Product: "\(foodNameRu)"
Fat percentage from name: \(percent)% (= \(percent) g of fat per 100g)

Return ONLY a JSON object with macronutrients PER 100 GRAMS of this product, according to GOST/DSTU reference data:
{"protein": <g>, "fat": <g>, "carbs": <g>, "calories": <kcal>}

Examples for calibration (per 100g):
- "творог 0%": {"protein": 18.0, "fat": 0.0, "carbs": 1.8, "calories": 71}
- "творог 5%": {"protein": 17.2, "fat": 5.0, "carbs": 1.8, "calories": 121}
- "творог 9%": {"protein": 16.7, "fat": 9.0, "carbs": 2.0, "calories": 156}
- "молоко 2.5%": {"protein": 2.9, "fat": 2.5, "carbs": 4.7, "calories": 52}
- "сметана 20%": {"protein": 2.5, "fat": 20.0, "carbs": 3.2, "calories": 206}
- "кефир 1%": {"protein": 2.8, "fat": 1.0, "carbs": 4.0, "calories": 37}
- "йогурт 3.2%": {"protein": 5.0, "fat": 3.2, "carbs": 8.5, "calories": 82}

The fat value MUST equal \(percent). Calories MUST satisfy: protein*4 + fat*9 + carbs*4 ≈ calories.
"""
        do {
            let messages = [OpenRouterMessage(role: "user", content: .text(prompt))]
            let text = try await network.callOpenRouterWithRetry(messages: messages, models: APIConfig.textModels)
            let json = extractJSON(from: text)
            let map = try parseJSONMap(json)

            guard let protein = (map["protein"] as? NSNumber)?.doubleValue,
                  let fat = (map["fat"] as? NSNumber)?.doubleValue,
                  let carbs = (map["carbs"] as? NSNumber)?.doubleValue,
                  protein > 0 else {
                logger.warning("AI macro correction returned invalid data for '\(foodNameRu)'")
                return nutrients
            }
            let calories = (map["calories"] as? NSNumber)?.doubleValue ?? (protein * 4 + fat * 9 + carbs * 4)

            // Safety net: fat MUST match the percent from the name (AI sometimes drifts).
            let finalFat = abs(fat - percent) / max(percent, 0.5) > 0.15 ? percent : fat
            let finalCalories = abs(finalFat - fat) > 0.01
                ? (protein * 4 + finalFat * 9 + carbs * 4)
                : calories

            var corrected = nutrients
            let oldFat = nutrients.fat
            corrected.protein = protein
            corrected.fat = finalFat
            corrected.carbs = carbs
            corrected.calories = finalCalories

            // Масштабируем фракции жира пропорционально новому total fat.
            if oldFat > 0 {
                let scale = finalFat / oldFat
                corrected.saturatedFat = nutrients.saturatedFat * scale
                corrected.monounsaturatedFat = nutrients.monounsaturatedFat * scale
                corrected.polyunsaturatedFat = nutrients.polyunsaturatedFat * scale
                corrected.cholesterol = nutrients.cholesterol * scale
            }

            logger.debug("AI macro correction for '\(foodNameRu)': protein \(nutrients.protein)→\(protein)g, fat \(oldFat)→\(finalFat)g, carbs \(nutrients.carbs)→\(carbs)g")
            return corrected
        } catch {
            logger.warning("AI macro correction failed for '\(foodNameRu)': \(error.localizedDescription)")
            return nutrients
        }
    }

    private func parseLocalFoodInput(_ input: String) -> [(String, Double)] {
        let items = input.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return items.map { item in
            let pattern = #"(\d+(?:[.,]\d+)?)\s*(г|гр|грамм|g|ml|мл|кг|kg)\b"#
            let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let range = NSRange(item.startIndex..., in: item)
            var weight = 0.0
            var name = item
            if let match = regex?.firstMatch(in: item, range: range) {
                if let wRange = Range(match.range(at: 1), in: item),
                   let uRange = Range(match.range(at: 2), in: item) {
                    let wStr = String(item[wRange]).replacingOccurrences(of: ",", with: ".")
                    weight = Double(wStr) ?? 0
                    let unit = String(item[uRange]).lowercased()
                    if unit == "кг" || unit == "kg" { weight *= 1000 }
                    if let fullRange = Range(match.range, in: item) {
                        name = item.replacingCharacters(in: fullRange, with: "").trimmingCharacters(in: .whitespaces)
                    }
                }
            }
            return (name, weight)
        }.filter { !$0.0.isEmpty }
    }

    private func parseIdentityList(_ text: String) -> [FoodIdentity] {
        let json = extractJSON(from: text)
        guard let data = json.data(using: .utf8) else { return [] }
        // Try array
        if let array = try? JSONDecoder().decode([FoodIdentity].self, from: data) { return array }
        // Try single
        if let single = try? JSONDecoder().decode(FoodIdentity.self, from: data) { return [single] }
        return []
    }

    func extractJSON(from text: String) -> String {
        var cleaned = text.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Find first { or [
        if let bracketIdx = cleaned.firstIndex(where: { $0 == "{" || $0 == "[" }) {
            cleaned = String(cleaned[bracketIdx...])
        }
        // Find matching close
        if cleaned.first == "[" {
            if let lastBracket = cleaned.lastIndex(of: "]") {
                cleaned = String(cleaned[...lastBracket])
            }
        } else if cleaned.first == "{" {
            if let lastBrace = cleaned.lastIndex(of: "}") {
                cleaned = String(cleaned[...lastBrace])
            }
        }
        return cleaned
    }

    private func parseJSONMap(_ json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.parseError("Cannot parse JSON map")
        }
        return obj
    }

    private func parseBatchNutrientArray(_ json: String) -> [[String: Any]] {
        guard let data = json.data(using: .utf8) else { return [] }
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] { return array }
        // Extract individual objects
        var objects: [[String: Any]] = []
        var searchFrom = json.startIndex
        while searchFrom < json.endIndex {
            guard let start = json[searchFrom...].firstIndex(of: "{") else { break }
            if let end = findMatchingBrace(json, from: start) {
                let substr = String(json[start...end])
                if let d = substr.data(using: .utf8), let map = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                    if map.keys.contains("calories") || map.keys.contains("protein") { objects.append(map) }
                }
                searchFrom = json.index(after: end)
            } else { break }
        }
        return objects
    }

    private func findMatchingBrace(_ text: String, from openPos: String.Index) -> String.Index? {
        var depth = 0
        var inString = false
        var escape = false
        var i = openPos
        while i < text.endIndex {
            let c = text[i]
            if escape { escape = false; i = text.index(after: i); continue }
            if c == "\\" && inString { escape = true; i = text.index(after: i); continue }
            if c == "\"" { inString = !inString; i = text.index(after: i); continue }
            if inString { i = text.index(after: i); continue }
            if c == "{" { depth += 1 }
            if c == "}" { depth -= 1; if depth == 0 { return i } }
            i = text.index(after: i)
        }
        return nil
    }

    func nutrientDataFromMap(_ map: [String: Any]) -> NutrientData {
        func v(_ key: String) -> Double {
            if let n = map[key] as? NSNumber { return n.doubleValue }
            if let s = map[key] as? String { return Double(s) ?? 0 }
            return 0
        }
        return NutrientData(
            calories: v("calories"), protein: v("protein"), fat: v("fat"),
            saturatedFat: v("saturated_fat"), monounsaturatedFat: v("monounsaturated_fat"),
            polyunsaturatedFat: v("polyunsaturated_fat"), cholesterol: v("cholesterol"),
            carbs: v("carbs"), fiber: v("fiber"),
            vitaminA: v("vitamin_a"), vitaminB1: v("vitamin_b1"), vitaminB2: v("vitamin_b2"),
            vitaminB3: v("vitamin_b3"), vitaminB5: v("vitamin_b5"), vitaminB6: v("vitamin_b6"),
            vitaminB7: v("vitamin_b7"), vitaminB9: v("vitamin_b9"), vitaminB12: v("vitamin_b12"),
            vitaminC: v("vitamin_c"), vitaminD: v("vitamin_d"), vitaminE: v("vitamin_e"),
            vitaminK: v("vitamin_k"), calcium: v("calcium"), iron: v("iron"),
            magnesium: v("magnesium"), phosphorus: v("phosphorus"), potassium: v("potassium"),
            sodium: v("sodium"), zinc: v("zinc"), copper: v("copper"),
            manganese: v("manganese"), selenium: v("selenium"), iodine: v("iodine")
        )
    }

    private func parseNutrientDataFromJSON(_ json: String) throws -> NutrientData {
        let map = try parseJSONMap(json)
        return nutrientDataFromMap(map)
    }

    private func fillMissingMicros(_ nutrients: NutrientData, from map: [String: Any]) -> NutrientData {
        func v(_ key: String) -> Double {
            (map[key] as? NSNumber)?.doubleValue ?? 0
        }
        var n = nutrients
        if n.vitaminA == 0 { n.vitaminA = v("vitamin_a") }
        if n.vitaminB1 == 0 { n.vitaminB1 = v("vitamin_b1") }
        if n.vitaminB2 == 0 { n.vitaminB2 = v("vitamin_b2") }
        if n.vitaminB3 == 0 { n.vitaminB3 = v("vitamin_b3") }
        if n.vitaminB5 == 0 { n.vitaminB5 = v("vitamin_b5") }
        if n.vitaminB6 == 0 { n.vitaminB6 = v("vitamin_b6") }
        if n.vitaminB7 == 0 { n.vitaminB7 = v("vitamin_b7") }
        if n.vitaminB9 == 0 { n.vitaminB9 = v("vitamin_b9") }
        if n.vitaminB12 == 0 { n.vitaminB12 = v("vitamin_b12") }
        if n.vitaminC == 0 { n.vitaminC = v("vitamin_c") }
        if n.vitaminD == 0 { n.vitaminD = v("vitamin_d") }
        if n.vitaminE == 0 { n.vitaminE = v("vitamin_e") }
        if n.vitaminK == 0 { n.vitaminK = v("vitamin_k") }
        if n.calcium == 0 { n.calcium = v("calcium") }
        if n.iron == 0 { n.iron = v("iron") }
        if n.magnesium == 0 { n.magnesium = v("magnesium") }
        if n.phosphorus == 0 { n.phosphorus = v("phosphorus") }
        if n.potassium == 0 { n.potassium = v("potassium") }
        if n.sodium == 0 { n.sodium = v("sodium") }
        if n.zinc == 0 { n.zinc = v("zinc") }
        if n.copper == 0 { n.copper = v("copper") }
        if n.manganese == 0 { n.manganese = v("manganese") }
        if n.selenium == 0 { n.selenium = v("selenium") }
        if n.iodine < 0.01 { n.iodine = v("iodine") }
        return n
    }

    // MARK: - Prompt Builders

    private func buildIdentifyPrompt(description: String) -> String {
        """
Определи ВСЕ продукты и их вес из описания. Описание может быть на русском, украинском или другом языке.
Если указано количество штук — рассчитай общий вес. Если вес не указан — оцени типичную порцию.

ВАЖНО:
- food_name — сохрани название НА ЯЗЫКЕ ВВОДА (не переводи на другой язык)
- food_name_en — ТОЧНЫЙ перевод на английский для поиска в USDA базе данных

Примеры правильного перевода:
- "куриная отбивная" / "куряча відбивна" → "chicken breast cutlet"
- "гречневая каша" / "гречана каша" → "buckwheat porridge"
- "ячневая каша вареная" → "barley porridge cooked"
- "овсяная каша" / "вівсяна каша" → "oatmeal cooked"
- "творог нежирный" → "low-fat cottage cheese"
- "борщ" → "borscht"
- "вареники с картошкой" → "potato pierogi"
- "пельмени" → "pelmeni meat dumplings"
- "сырники" / "сирники" → "cottage cheese pancakes"
- "голубці" / "голубцы" → "stuffed cabbage rolls"
- "деруни" / "драники" → "potato pancakes"
- "лосось слабосоленный" → "salmon salted"
- "кава" / "кофе" → "coffee brewed"
- "капучіно" / "капучино" → "coffee cappuccino"

ВАЖНО: слова "вареная"/"варена"/"варенная"/"варёная"/"отварная" ВСЕ означают "cooked" — всегда добавляй "cooked" в перевод!

ВАЖНО для свежих овощей/фруктов/ягод/зелени:
Если продукт — свежий овощ, фрукт, ягода, зелень или листовой салат,
и в названии НЕ указан способ приготовления (вареный/жареный/тушёный/печёный/квашеный/маринованный/сушёный и т.п.),
обязательно добавь "raw" в food_name_en. USDA по умолчанию выдаёт салаты и обработанные варианты вместо свежего продукта.

Примеры:
- "капуста" → "cabbage raw"
- "морковь" / "морква" → "carrot raw"
- "яблоко" / "яблуко" → "apple raw"
- "помидор" / "помідор" → "tomato raw"
- "огурец" / "огірок" → "cucumber raw"
- "лук" / "цибуля" → "onion raw"
- "шпинат" → "spinach raw"
- "клубника" / "полуниця" → "strawberry raw"
- "банан" → "banana raw"
- "брокколи" → "broccoli raw"
- "перец болгарский" / "перець солодкий" → "bell pepper raw"

НЕ добавляй "raw" для:
- мяса/рыбы/птицы/яиц (без указания способа — подразумевается приготовленное)
- круп, макарон, бобовых, хлеба
- молочных продуктов, сыров, орехов, семян, масел
- готовых блюд, консервов, продуктов прошедших обработку
- если в названии уже есть способ приготовления или "сырой"/"свіжий"/"raw"/"fresh"

ВАЖНО для составных блюд (салаты, супы):
- НЕ перечисляй все ингредиенты в food_name_en — используй КОРОТКОЕ узнаваемое название
- Если блюдо "без заправки" / "без майонеза" — НЕ включай "without dressing" в food_name_en

Описание: \(description)

Верни ТОЛЬКО JSON массив (даже если продукт один):
[{"food_name": "<название НА ЯЗЫКЕ ВВОДА>", "food_name_en": "<EXACT English translation for USDA search>", "weight_grams": <число>}]
"""
    }

    private func buildBatchNutrientPrompt(foodsList: String, count: Int) -> String {
        """
You are a professional nutritionist. Provide nutritional values PER 100 GRAMS for EACH food below.
Return ONLY a JSON array with one object per food, in the SAME ORDER.

Foods:
\(foodsList)

Return format (array of \(count) objects):
[{"calories": <kcal>, "protein": <g>, "fat": <g>, "saturated_fat": <g>, "monounsaturated_fat": <g>, "polyunsaturated_fat": <g>, "cholesterol": <mg>, "carbs": <g>, "fiber": <g>, "vitamin_a": <mcg>, "vitamin_b1": <mg>, "vitamin_b2": <mg>, "vitamin_b3": <mg>, "vitamin_b5": <mg>, "vitamin_b6": <mg>, "vitamin_b7": <mcg>, "vitamin_b9": <mcg>, "vitamin_b12": <mcg>, "vitamin_c": <mg>, "vitamin_d": <mcg>, "vitamin_e": <mg>, "vitamin_k": <mcg>, "calcium": <mg>, "iron": <mg>, "magnesium": <mg>, "phosphorus": <mg>, "potassium": <mg>, "sodium": <mg>, "zinc": <mg>, "copper": <mg>, "manganese": <mg>, "selenium": <mcg>, "iodine": <mcg>}]
"""
    }

    private func buildMicroFillPrompt(foodsList: String, count: Int) -> String {
        """
For each food below, provide ALL micronutrients PER 100 GRAMS using USDA reference values.
Return ONLY a JSON array with one object per food, in the SAME ORDER.

IMPORTANT: iodine is REQUIRED. Typical: seafood 30-160 mcg, dairy 20-50 mcg, egg 24 mcg, buckwheat 3.3 mcg.

Foods:
\(foodsList)

Return format (array of \(count) objects):
[{"vitamin_a": <mcg>, "vitamin_b1": <mg>, "vitamin_b2": <mg>, "vitamin_b3": <mg>, "vitamin_b5": <mg>, "vitamin_b6": <mg>, "vitamin_b7": <mcg>, "vitamin_b9": <mcg>, "vitamin_b12": <mcg>, "vitamin_c": <mg>, "vitamin_d": <mcg>, "vitamin_e": <mg>, "vitamin_k": <mcg>, "calcium": <mg>, "iron": <mg>, "magnesium": <mg>, "phosphorus": <mg>, "potassium": <mg>, "sodium": <mg>, "zinc": <mg>, "copper": <mg>, "manganese": <mg>, "selenium": <mcg>, "iodine": <mcg>}]
"""
    }
}
