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

            // Step 2: USDA lookup — AI picks the best candidate (with adversarial verification + alt queries)
            for i in aiPending.indices {
                let item = aiPending[i]
                // For dairy with explicit % fat (e.g. "творог 5%"), strip the percent
                // from the English query — USDA doesn't index RU/UA fat grades, so we
                // search for the base product and later correct macros via AI.
                let isDairyWithPercent = isDairyWithFatPercent(item.foodNameRu)
                let foodNameEnForSearch: String = {
                    var name = isDairyWithPercent ? stripFatPercent(from: item.foodNameEn) : item.foodNameEn
                    // Normalise British English → American English so USDA finds the right entry
                    let britishToAmerican: [(String, String)] = [
                        ("beetroot", "beet"), ("aubergine", "eggplant"), ("courgette", "zucchini"),
                        ("coriander leaf", "cilantro"), ("capsicum", "bell pepper"),
                        ("rocket", "arugula"), ("mangetout", "snow peas"), ("swede", "rutabaga"),
                        ("broad bean", "fava bean"), ("chickpea", "garbanzo bean"),
                        ("maize", "corn"), ("prawn", "shrimp"),
                    ]
                    for (british, american) in britishToAmerican {
                        name = name.replacingOccurrences(of: british, with: american, options: .caseInsensitive)
                    }
                    return name
                }()

                let negationCleaned = foodNameEnForSearch
                    .replacingOccurrences(of: "\\b(without|no|not|minus|free\\s+from)\\s+\\w+", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)

                // Skip USDA for multi-ingredient composite dishes (AI handles them better).
                let significantWords = negationCleaned.lowercased().components(separatedBy: .whitespaces)
                    .filter { $0.count >= 3 && !["with", "and", "the", "from", "for"].contains($0) }
                if significantWords.count > 5 {
                    logger.debug("Skipping USDA for composite dish (\(significantWords.count) words): '\(negationCleaned)'")
                    continue
                }

                // The query shown to the AI must match what USDA was actually searched for —
                // otherwise for dairy-with-% ("творог 5%" → foodNameEnForSearch="curd") the AI
                // sees "curd 5%" and rejects the base-product hits as fat-mismatched.
                let queryRuForAi = isDairyWithPercent ? stripFatPercent(from: item.foodNameRu) : item.foodNameRu
                let queryEnForAi = isDairyWithPercent ? stripFatPercent(from: item.foodNameEn) : item.foodNameEn

                // Generate USDA-optimized search queries upfront.
                // Core fix: instead of using food_name_en directly (which can be a natural-language
                // dish name like "beef stew"), we ask a specialised function to produce USDA-style
                // ingredient+preparation queries ("beef braised").
                // For dairy-with-%, skip generation and use the stripped base name directly.
                let searchQueries: [String]
                if isDairyWithPercent {
                    searchQueries = [negationCleaned.isEmpty ? foodNameEnForSearch : negationCleaned]
                } else {
                    let generated = await generateUsdaSearchQueries(queryRu: queryRuForAi, queryEn: queryEnForAi)
                    searchQueries = generated.isEmpty ? [negationCleaned.isEmpty ? foodNameEnForSearch : negationCleaned] : generated
                }
                logger.debug("USDA search queries for '\(item.foodNameEn)': \(searchQueries)")

                var allCandidates: [Int: UsdaFood] = [:]

                // Runs one USDA search round: fetches, dedups, then asks AI to pick from the FULL
                // cumulative candidate set (not just this round's delta) — so a later query
                // doesn't hide a good earlier hit from the AI. After the pick, a second AI call
                // adversarially verifies the pick is the same biological product.
                func runOneRound(_ query: String) async -> UsdaFood? {
                    do {
                        let res = try await network.searchUSDA(query: query)
                        let fresh: [UsdaFood] = (res.foods ?? []).compactMap { f in
                            guard let id = f.fdcId else { return nil }
                            if allCandidates[id] != nil { return nil }
                            return f
                        }
                        for f in fresh { if let id = f.fdcId { allCandidates[id] = f } }
                        let briefsById: [Int: UsdaCandidateBrief] = Dictionary(uniqueKeysWithValues:
                            allCandidates.values.compactMap { food -> (Int, UsdaCandidateBrief)? in
                                guard let brief = usdaCandidateBrief(food) else { return nil }
                                return (brief.fdcId, brief)
                            })
                        if briefsById.isEmpty {
                            logger.debug("USDA query='\(query)' — no candidates with calories in cumulative set")
                            return nil
                        }
                        logger.debug("USDA query='\(query)': +\(fresh.count) new, \(briefsById.count) total fed to AI")

                        var excluded = Set<Int>()
                        for _ in 0..<2 {
                            let remaining = briefsById.values.filter { !excluded.contains($0.fdcId) }
                            if remaining.isEmpty { break }
                            guard let pickedId = await askAiToPickUsdaCandidate(queryRu: queryRuForAi, queryEn: queryEnForAi, candidates: Array(remaining)) else { break }
                            guard let pickedBrief = briefsById[pickedId] else { break }
                            if await verifyUsdaPick(queryRu: queryRuForAi, queryEn: queryEnForAi, pick: pickedBrief) {
                                return allCandidates[pickedId]
                            }
                            logger.debug("verifyUsdaPick REJECTED '\(pickedBrief.description)' for '\(queryEnForAi)' — retrying selection")
                            excluded.insert(pickedId)
                        }
                        return nil
                    } catch {
                        logger.warning("USDA search failed for '\(query)': \(error.localizedDescription)")
                        return nil
                    }
                }

                // Try each generated query in order until AI selects and verifies a candidate.
                var selectedFood: UsdaFood? = nil
                for query in searchQueries {
                    selectedFood = await runOneRound(query)
                    if selectedFood != nil { break }
                }

                if selectedFood == nil {
                    logger.debug("AI rejected all USDA candidates for '\(item.foodNameEn)' — falling through to Step 3")
                }

                if let food = selectedFood,
                   let nutrients = buildNutrientsFromUsda(food, query: foodNameEnForSearch, negationCleaned: negationCleaned) {
                    aiPending[i].nutrientsPer100g = nutrients
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
        let zeroMacroOk = ["вода", "water", "чай", "tea", "кофе", "coffee", "herb", "spice", "vinegar", "gelatin"]
        let results: [FoodAnalysisResult] = allItems.compactMap { item in
            guard let per100g = item.nutrientsPer100g else { return nil }
            let hasNutrients = per100g.calories > 0 || per100g.protein > 0 || per100g.fat > 0 || per100g.carbs > 0
            let isKnownZero = zeroMacroOk.contains(where: { item.foodNameRu.lowercased().contains($0) || item.foodNameEn.lowercased().contains($0) })
            guard hasNutrients || isKnownZero else { return nil }
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
        let name = [product.productNameRu, product.productNameUk, product.productNameEn, product.productName, product.brands]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? "Неизвестный продукт"
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

        // Enrich missing micros via AI (OFF API rarely provides vitamins/minerals)
        per100g = await enrichMicrosWithAIPublic(per100g, foodNameEn: name)

        // Enrich fat details
        per100g = try await enrichFatDetailsIfNeeded(per100g, foodNameEn: name, cacheEntry: nil)

        // Cache
        db.saveToCache(keyOriginal: name, keyEn: name, nutrientsPer100g: per100g)
        db.saveToCache(keyOriginal: "barcode:\(barcode)", keyEn: name, nutrientsPer100g: per100g)

        return (name, per100g, false)
    }

    func enrichMicrosWithAIPublic(_ nutrients: NutrientData, foodNameEn: String) async -> NutrientData {
        var missing: [String] = []
        if nutrients.vitaminA == 0 { missing.append("vitamin_a (mcg RAE)") }
        if nutrients.vitaminB1 == 0 { missing.append("vitamin_b1 (mg)") }
        if nutrients.vitaminB2 == 0 { missing.append("vitamin_b2 (mg)") }
        if nutrients.vitaminB3 == 0 { missing.append("vitamin_b3 (mg)") }
        if nutrients.vitaminB5 == 0 { missing.append("vitamin_b5 (mg)") }
        if nutrients.vitaminB6 == 0 { missing.append("vitamin_b6 (mg)") }
        if nutrients.vitaminB7 == 0 { missing.append("vitamin_b7 (mcg)") }
        if nutrients.vitaminB9 == 0 { missing.append("vitamin_b9 (mcg)") }
        if nutrients.vitaminB12 == 0 { missing.append("vitamin_b12 (mcg)") }
        if nutrients.vitaminC == 0 { missing.append("vitamin_c (mg)") }
        if nutrients.vitaminD == 0 { missing.append("vitamin_d (mcg)") }
        if nutrients.vitaminE == 0 { missing.append("vitamin_e (mg)") }
        if nutrients.vitaminK == 0 { missing.append("vitamin_k (mcg)") }
        if nutrients.calcium == 0 { missing.append("calcium (mg)") }
        if nutrients.iron == 0 { missing.append("iron (mg)") }
        if nutrients.magnesium == 0 { missing.append("magnesium (mg)") }
        if nutrients.phosphorus == 0 { missing.append("phosphorus (mg)") }
        if nutrients.potassium == 0 { missing.append("potassium (mg)") }
        if nutrients.sodium == 0 { missing.append("sodium (mg)") }
        if nutrients.zinc == 0 { missing.append("zinc (mg)") }
        if nutrients.copper == 0 { missing.append("copper (mg)") }
        if nutrients.manganese == 0 { missing.append("manganese (mg)") }
        if nutrients.selenium == 0 { missing.append("selenium (mcg)") }
        if nutrients.iodine < 0.01 { missing.append("iodine (mcg)") }
        guard !missing.isEmpty else { return nutrients }

        let prompt = """
For "\(foodNameEn)" per 100g, provide ONLY these nutrients using USDA reference values.
\(missing.joined(separator: ", "))
Return ONLY JSON, e.g.: {"vitamin_a": 45, "calcium": 11}
"""
        do {
            let messages = [OpenRouterMessage(role: "user", content: .text(prompt))]
            let text = try await network.callOpenRouterWithRetry(messages: messages, models: APIConfig.textModels)
            let map = try parseJSONMap(extractJSON(from: text))
            return fillMissingMicros(nutrients, from: map)
        } catch {
            logger.warning("AI micro enrichment failed for '\(foodNameEn)': \(error.localizedDescription)")
            return nutrients
        }
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
        let name = [product.productNameRu, product.productNameUk, product.productNameEn, product.productName, product.brands]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? "Dietary supplement"
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

    // MARK: - AI-driven USDA candidate selection
    // Instead of a hand-tuned scoreFood() heuristic, we ask the AI to pick the
    // best USDA hit for the query. The AI sees only a compact candidate list
    // (fdcId + description + dataType + macros) and returns a single fdcId —
    // nutrient values are still taken from the USDA JSON, so the model cannot
    // "invent" data from its own sources.

    /// Compact form of a USDA hit used to build the AI selection prompt.
    struct UsdaCandidateBrief {
        let fdcId: Int
        let description: String
        let dataType: String
        let calories: Double
        let protein: Double
        let fat: Double
        let carbs: Double
    }

    private func usdaCandidateBrief(_ f: UsdaFood) -> UsdaCandidateBrief? {
        guard let id = f.fdcId else { return nil }
        var nMap: [Int: Double] = [:]
        for fn in f.foodNutrients ?? [] {
            if let nid = fn.nutrientId, let v = fn.value { nMap[nid] = v }
        }
        let cal = nMap[UsdaFoodNutrient.ENERGY] ?? 0
        // Callers that expect zero-calorie foods (water, plain tea) filter differently;
        // this brief is only used for AI ranking where calories > 0 is the norm.
        guard cal > 0 else { return nil }
        return UsdaCandidateBrief(
            fdcId: id,
            description: f.description ?? "",
            dataType: f.dataType ?? "",
            calories: cal,
            protein: nMap[UsdaFoodNutrient.PROTEIN] ?? 0,
            fat: nMap[UsdaFoodNutrient.FAT] ?? 0,
            carbs: nMap[UsdaFoodNutrient.CARBS] ?? 0
        )
    }

    /// Ask the AI to pick the best USDA candidate for a query.
    /// Returns the chosen fdcId, or nil if no candidate is a good match.
    /// The returned id is verified against the candidate list to guard against hallucinated IDs.
    private func askAiToPickUsdaCandidate(
        queryRu: String,
        queryEn: String,
        candidates: [UsdaCandidateBrief]
    ) async -> Int? {
        if candidates.isEmpty { return nil }
        let list = candidates.enumerated().map { (i, c) in
            "\(i + 1). [fdcId=\(c.fdcId)] [\(c.dataType)] \"\(c.description)\" — " +
                "cal=\(String(format: "%.0f", c.calories)), " +
                "P=\(String(format: "%.1f", c.protein)), " +
                "F=\(String(format: "%.1f", c.fat)), " +
                "C=\(String(format: "%.1f", c.carbs))"
        }.joined(separator: "\n")

        let prompt = """
You are a nutrition expert selecting the single best USDA Food Data Central entry that matches a user's food query.

User query (original language): "\(queryRu)"
User query (English): "\(queryEn)"

USDA candidates (values are per 100g):
\(list)

Selection rules — in order of importance:

1. **BIOLOGICAL IDENTITY is non-negotiable.** The candidate MUST be the SAME species / product as the query — not a lexically similar but biologically different food. If none of the candidates is the same product, return fdc_id = null.
   Common traps to REJECT:
   - "черемша" / "wild garlic" / "ramps" / "wild leek" (Allium ursinum / Allium tricoccum) is NOT the same as "garlic" (Allium sativum) — garlic bulbs have ~33g carbs, wild garlic leaves have ~3-6g. Never accept "Garlic, raw" for a "wild garlic" / "ramps" / "черемша" query.
   - "cashew" is NOT "chestnut"; "chestnut" is NOT "water chestnut".
   - "cilantro" / "coriander leaf" is NOT "coriander seed"; "parsley" is NOT "cilantro".
   - "sweet potato" / "yam" is NOT "potato".
   - "sour cherry" / "вишня" is NOT "sweet cherry" / "черешня".
   - "buckwheat" is NOT "wheat"; "millet" is NOT "corn".
   - "quinoa" is NOT "couscous"; "spelt" is NOT "wheat".
   - "kohlrabi" is NOT "cabbage"; "bok choy" is NOT "cabbage".
   - "veal" is NOT "beef"; "mutton" is NOT "lamb".
   - "salmon" is NOT "trout"; "cod" is NOT "haddock" (different species — check the description carefully).
   - Frozen / canned / dried / juice / pie / jam / chips / cereal / candy / powder / ice cream forms are NOT the raw whole product.

2. **Macronutrient sanity check.** For the query's food family (leafy green, root vegetable, fruit, meat, grain, dairy...), the candidate's macros must be plausible. A "leafy green vegetable" query with >20g carbs per 100g is almost certainly the wrong product (leaves rarely exceed 5-8g carbs). A "raw fruit" query with 0g fiber and >30g carbs is likely juice or dried fruit.

3. **Preparation state must match:**
   - For raw fruits / vegetables / berries with no cooking method mentioned — pick "raw" / whole product.
   - For cooked / boiled / porridge — pick an entry with matching preparation state ("cooked", NOT "from raw" which means dry-weight equivalent).
   - Frozen / canned / dried / juice / pie / jam / chips / cereal / candy / powder / ice cream are different products — do NOT accept unless the query explicitly asked for that form.

4. **Data-type preference:** Prefer "Survey (FNDDS)", "SR Legacy", "Foundation" over "Branded" for generic ingredients.

5. **Implausible Branded macros filter:** Reject Branded entries where protein > 40g (unless protein powder / whey / jerky / parmesan), carbs > 75g (unless sugar / jam / flour / cereal / dried), fat > 70g (unless oil / butter / ghee / lard / mayonnaise).

6. **Atwater check:** Reject entries where 4·protein + 9·fat + 4·carbs > 1.3 × calories.

7. **Poultry:** For chicken / turkey breast or thigh, prefer "skinless" / "meat only" unless the query mentions skin or coating.

8. **Generic over variety:** Prefer generic entries over variety-specific ones when the query has no variety qualifier ("tomatoes, raw" over "tomatoes, green, raw").

9. **No hallucination:** Only return an fdcId from the numbered list above. If nothing is a good match, return null — DO NOT force a pick.

Return ONLY a JSON object:
{"fdc_id": <chosen id, or null if none of the candidates match well>, "reason": "<one short sentence explaining the pick or why nothing fit>"}
"""
        do {
            let messages = [OpenRouterMessage(role: "user", content: .text(prompt))]
            let text = try await network.callOpenRouterWithRetry(messages: messages, models: APIConfig.textModels)
            let json = extractJSON(from: text)
            let map = try parseJSONMap(json)
            let raw = map["fdc_id"]
            let id: Int? = {
                if let n = raw as? NSNumber { return n.intValue }
                if let s = raw as? String { return Int(s) }
                return nil
            }()
            logger.debug("AI USDA pick for '\(queryEn)': fdcId=\(id.map(String.init) ?? "nil"), reason=\((map["reason"] as? String) ?? "")")
            // Guard against hallucination: the id must exist in the candidate list.
            guard let picked = id, candidates.contains(where: { $0.fdcId == picked }) else { return nil }
            return picked
        } catch {
            logger.warning("AI USDA pick failed for '\(queryEn)': \(error.localizedDescription)")
            return nil
        }
    }

    /// Adversarial post-verification: after askAiToPickUsdaCandidate picks a candidate,
    /// ask the AI a fresh, sharply-focused question — "is this REALLY the same biological
    /// product as the query?" — with an instruction to default to REJECT on any doubt.
    /// Catches lexical-similarity traps that a permissive selection prompt might slip
    /// through (e.g. AI picks "Garlic, raw" for a "черемша"/"wild garlic" query).
    private func verifyUsdaPick(
        queryRu: String,
        queryEn: String,
        pick: UsdaCandidateBrief
    ) async -> Bool {
        let prompt = """
You are a nutrition-safety reviewer. Someone selected a USDA entry as the match for a user's food query. Your job is to REJECT it if the entry is NOT the same biological product / species / dish, even if the names are lexically similar.

User query (original language): "\(queryRu)"
User query (English): "\(queryEn)"

Selected USDA entry:
  description: "\(pick.description)"
  dataType:    "\(pick.dataType)"
  per 100g:    cal=\(String(format: "%.0f", pick.calories)), P=\(String(format: "%.1f", pick.protein)), F=\(String(format: "%.1f", pick.fat)), C=\(String(format: "%.1f", pick.carbs))

Answer TWO questions:
1. is_same_product: is this USDA entry the SAME biological product / species / dish as the user asked for? Different species (garlic vs wild garlic, cashew vs chestnut, cilantro vs parsley, sour vs sweet cherry, sweet potato vs potato, veal vs beef, salmon vs trout, buckwheat vs wheat, etc.) → false. Different form (juice / jam / pie / chips / dried / candied / powder / ice cream when the user asked for the whole raw product) → false.
2. macros_plausible: are the per-100g macros plausible for the QUERIED product's food family? A leafy green with >15g carbs is suspicious. A raw fruit with 0g fiber and >30g carbs is likely juice or dried. Meat with 0g protein is wrong.

Default to false if unsure. It's better to reject a correct pick than accept a wrong one — the caller will fall back to a different data source.

Return ONLY a JSON object:
{"is_same_product": <true|false>, "macros_plausible": <true|false>, "reason": "<one short sentence>"}
"""
        do {
            let messages = [OpenRouterMessage(role: "user", content: .text(prompt))]
            let text = try await network.callOpenRouterWithRetry(messages: messages, models: APIConfig.textModels)
            let json = extractJSON(from: text)
            let map = try parseJSONMap(json)
            func bool(_ key: String) -> Bool {
                if let b = map[key] as? Bool { return b }
                if let n = map[key] as? NSNumber { return n.boolValue }
                if let s = map[key] as? String { return s.caseInsensitiveCompare("true") == .orderedSame }
                return false
            }
            let ok = bool("is_same_product") && bool("macros_plausible")
            logger.debug("verifyUsdaPick '\(pick.description)' for '\(queryEn)': ok=\(ok) reason=\((map["reason"] as? String) ?? "")")
            return ok
        } catch {
            logger.warning("verifyUsdaPick failed for '\(queryEn)': \(error.localizedDescription) — treating as REJECT")
            return false
        }
    }

    /// Generate 2-3 USDA FDC-optimized search queries for a food item.
    /// Called BEFORE the USDA search — replaces the naive "use food_name_en directly" approach.
    ///
    /// USDA indexes food as INGREDIENT + PREPARATION STATE, not as dish names.
    /// "beef braised" ≠ "beef stew" — stew is a composite dish in USDA.
    private func generateUsdaSearchQueries(queryRu: String, queryEn: String) async -> [String] {
        let prompt = """
You are a USDA Food Data Central (FDC) database search expert. Generate 2-3 English search queries that will find the correct USDA FDC entry for the given food.

User query (original language): "\(queryRu)"
User query (English): "\(queryEn)"

USDA FDC names food as INGREDIENT + PREPARATION STATE — NOT as dish names. This is critical:

RULE 1 — MEAT / POULTRY with a cooking method → use the method as an adjective, NEVER a dish name:
  Correct: "beef braised", "pork roasted", "chicken fried", "lamb braised", "turkey baked"
  WRONG: "beef stew", "pork ragout", "chicken casserole", "lamb curry", "beef stroganoff"
  → "beef stew" is a composite DISH (with vegetables and sauce). "beef braised" is the INGREDIENT.
  → Any word like stew / ragout / casserole / curry / stroganoff / goulash = composite dish → DO NOT use.
  Examples:
  - "говядина тушёная" / "beef braised" → ["beef braised", "beef chuck braised"]
  - "свинина тушёная" / "pork braised" → ["pork braised", "pork shoulder braised"]
  - "курица тушёная" / "chicken braised" → ["chicken braised", "chicken thigh braised"]
  - "говядина жареная" / "beef fried" → ["beef pan-fried", "beef fried"]
  - "свинина запечённая" / "pork roasted" → ["pork roasted", "pork loin roasted"]
  - "баранина тушёная" / "lamb braised" → ["lamb braised", "lamb shoulder braised"]

RULE 2 — FISH / SEAFOOD with a cooking method → same rule, never dish names:
  - "судак тушёный" / "pike-perch braised" → ["pike-perch braised", "walleye braised", "walleye cooked"]
  - "треска запечённая" / "cod baked" → ["cod baked", "cod roasted"]

RULE 3 — GRAINS / PORRIDGE → use "cooked" or the grain name:
  - "гречка варёная" / "buckwheat cooked" → ["buckwheat groats cooked", "buckwheat cooked"]
  - "пшённая каша" / "millet porridge" → ["millet cooked", "millet porridge"]

RULE 4 — REGIONAL / LOCALISED foods → use the closest USDA synonym:
  - "черемша" / "wild garlic" → ["ramps raw", "wild leek raw"] (USDA uses "ramps", NOT "wild garlic")
  - "творог" / "cottage cheese" → ["cottage cheese", "cottage cheese lowfat"]
  - "ряженка" / "cultured milk" → ["kefir", "cultured milk fermented"]

RULE 5 — RAW produce → add "raw":
  - "помидор" / "tomato" → ["tomato raw"]
  - "яблоко" / "apple" → ["apple raw"]

RULE 6 — Use American English: beet (not beetroot), eggplant (not aubergine), zucchini (not courgette), cilantro (not coriander leaf).

RULE 7 — Return 2-3 queries, most specific first. If the English query already looks like a correct USDA query (e.g. "salmon salted", "oatmeal cooked"), include it as-is and add one variation.

Return ONLY a JSON array of English strings:
["query1", "query2"]
"""
        do {
            let messages = [OpenRouterMessage(role: "user", content: .text(prompt))]
            let text = try await network.callOpenRouterWithRetry(messages: messages, models: APIConfig.textModels)
            let json = extractJSON(from: text)
            guard let data = json.data(using: .utf8) else { return [queryEn] }
            if let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
                let result = Array(array.filter { !$0.isEmpty }.reduce(into: [String]()) { acc, s in
                    if !acc.contains(where: { $0.caseInsensitiveCompare(s) == .orderedSame }) { acc.append(s) }
                }.prefix(3))
                return result.isEmpty ? [queryEn] : result
            }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let firstArr = obj.values.compactMap { $0 as? [Any] }.first
                let strings = firstArr?.compactMap { $0 as? String } ?? []
                let result = Array(strings.filter { !$0.isEmpty }.reduce(into: [String]()) { acc, s in
                    if !acc.contains(where: { $0.caseInsensitiveCompare(s) == .orderedSame }) { acc.append(s) }
                }.prefix(3))
                return result.isEmpty ? [queryEn] : result
            }
            return [queryEn]
        } catch {
            logger.warning("generateUsdaSearchQueries failed for '\(queryEn)': \(error.localizedDescription)")
            return [queryEn]
        }
    }

    // MARK: - USDA nutrients extraction (post-filter)

    /// Extracts NutrientData from an AI-selected USDA food and applies the same
    /// post-filters the previous heuristic pipeline had: Branded implausibility guard
    /// (skips to null so the caller falls through), US enrichment correction for
    /// flour-based foods, Atwater sanity check.
    private func buildNutrientsFromUsda(_ food: UsdaFood, query: String, negationCleaned: String) -> NutrientData? {
        guard let foodNutrients = food.foodNutrients else { return nil }

        var nMap: [Int: Double] = [:]
        for fn in foodNutrients {
            if let id = fn.nutrientId, let v = fn.value { nMap[id] = v }
        }

        // Branded implausibility guard — if AI still picked a Branded outlier, reject
        // and let the caller fall through to Step 3 (batch AI nutrients).
        if food.dataType == "Branded" {
            let prot = nMap[UsdaFoodNutrient.PROTEIN] ?? 0
            let fat = nMap[UsdaFoodNutrient.FAT] ?? 0
            let carbs = nMap[UsdaFoodNutrient.CARBS] ?? 0
            let queryLower = query.lowercased()
            let highProtOk = ["protein", "powder", "whey", "casein", "isolate", "jerky", "parmesan"].contains(where: { queryLower.contains($0) })
            let highCarbOk = ["sugar", "honey", "syrup", "candy", "jam", "dried", "flour", "cereal", "granola"].contains(where: { queryLower.contains($0) })
            let highFatOk = ["oil", "butter", "lard", "ghee", "mayo", "mayonnaise"].contains(where: { queryLower.contains($0) })
            if (prot > 40 && !highProtOk) || (carbs > 75 && !highCarbOk) || (fat > 70 && !highFatOk) {
                logger.warning("Branded pick '\(food.description ?? "")' rejected (implausible macros p=\(prot) f=\(fat) c=\(carbs) for '\(queryLower)')")
                return nil
            }
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

        // US flour-fortification correction: in the US, flour is fortified with B1/B2/B3/B9/iron —
        // not typical for Eastern Europe. Scale down for flour-based foods.
        let flourKeywords = [
            "pierogi", "dumpling", "pelmeni", "ravioli", "wonton",
            "bread", "roll", "bun", "bagel", "tortilla", "pita", "naan", "flatbread",
            "pasta", "noodle", "spaghetti", "macaroni", "lasagna",
            "pancake", "crepe", "waffle", "blini", "blintz",
            "cake", "cookie", "biscuit", "muffin", "pie", "pastry", "croissant", "doughnut",
            "flour", "cereal", "cornmeal", "porridge"
        ]
        let foodDesc = ((food.description ?? "") + " " + query).lowercased()
        if flourKeywords.contains(where: { foodDesc.contains($0) }) {
            per100g.vitaminB1 *= 0.17
            per100g.vitaminB2 *= 0.10
            per100g.vitaminB3 *= 0.22
            per100g.vitaminB9 *= 0.17
            per100g.iron *= 0.26
        }

        // Atwater sanity check + implausible-macro guard (0 protein + 0 carbs + fat > 0 only OK for pure fats/oils).
        let macroCalories = per100g.protein * 4 + per100g.fat * 9 + per100g.carbs * 4
        let isPureFat = ["oil", "butter", "lard", "ghee", "shortening", "fat", "grease"].contains(where: { negationCleaned.lowercased().contains($0) })
        let macroPlausible = isPureFat || !(per100g.protein == 0 && per100g.carbs == 0 && per100g.fat > 0)
        let zeroCalorieFoods = ["water", "tea", "coffee", "herb", "spice", "vinegar", "gelatin"]
        let queryIsZeroCalorie = zeroCalorieFoods.contains(where: { negationCleaned.lowercased().contains($0) })
        let sane = (per100g.calories == 0 && per100g.protein == 0 && per100g.fat == 0 && per100g.carbs == 0 && queryIsZeroCalorie)
            || (per100g.calories > 0 && macroCalories <= per100g.calories * 1.3 && macroPlausible)
        if !sane {
            logger.warning("USDA sanity check REJECTED '\(food.description ?? "")' for '\(query)': cal=\(per100g.calories) p=\(per100g.protein) f=\(per100g.fat) c=\(per100g.carbs)")
            return nil
        }
        return per100g
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

КРИТИЧЕСКИ ВАЖНО для мяса/птицы с указанием способа приготовления:
"тушеная/тушена" для МЯСА = "braised" (НЕ "stew" — stew это блюдо с овощами и подливкой!)
"жареная/смажена" для МЯСА = "fried" или "pan-fried"
"запечённая/запечена" для МЯСА = "baked" или "roasted"
"варёная/варена/отварная" для МЯСА = "cooked" или "boiled"

Примеры:
- "говядина тушеная" / "яловичина тушкована" → "beef braised" (НЕ "beef stew"!)
- "свинина тушеная" / "свинина тушкована" → "pork braised"
- "курица тушеная" / "курка тушкована" → "chicken braised"
- "говядина жареная" / "яловичина смажена" → "beef pan-fried"
- "свинина запечённая" / "свинина запечена" → "pork roasted"
- "говядина варёная" / "яловичина варена" → "beef cooked"
- "телятина тушеная" → "veal braised"
- "баранина тушеная" / "баранина тушкована" → "lamb braised"
- "кролик тушеный" / "кролик тушкований" → "rabbit braised"

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
- "свекла" / "буряк" / "свёкла" → "beet raw"
- "репа" / "ріпа" → "turnip raw"
- "редька" / "редька чёрная" → "radish raw"
- "тыква" / "гарбуз" → "pumpkin raw"
- "кабачок" / "цукіні" → "zucchini raw"
- "баклажан" → "eggplant raw"
- "сельдерей" / "селера" → "celery raw"
- "петрушка" / "петрушка свіжа" → "parsley raw"
- "укроп" / "кріп" → "dill raw"
- "виноград" / "виноград" → "grapes raw"
- "черешня" / "черешні" → "sweet cherry raw"
- "вишня" / "вишні" → "sour cherry raw"
- "черника" / "чорниця" → "blueberry raw"
- "голубика" / "лохина" → "blueberry raw"
- "смородина чёрная" / "чорна смородина" → "blackcurrant raw"
- "смородина красная" / "червона смородина" → "redcurrant raw"
- "кукуруза" / "кукурудза" → "corn raw"
- "горох свежий" / "горох" → "peas raw"
- "фасоль стручковая" / "зелена квасоля" → "green beans raw"
- "цветная капуста" / "цвітна капуста" → "cauliflower raw"
- "авокадо" → "avocado raw"
- "ананас" → "pineapple raw"
- "манго" → "mango raw"
- "киви" → "kiwi raw"

ВАЖНО для USDA — используй АМЕРИКАНСКИЙ английский, не британский:
- "beet", НЕ "beetroot" (beetroot = только чипсы в USDA)
- "eggplant", НЕ "aubergine"
- "zucchini", НЕ "courgette"
- "cilantro", НЕ "coriander" (для зелени)
- "bell pepper", НЕ "capsicum"

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
