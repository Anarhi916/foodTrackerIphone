import Foundation
import SwiftUI
import Combine

@MainActor
class MainViewModel: ObservableObject {
    private let repo = NutritionRepository.shared

    // MARK: - Published State

    @Published var foodInput: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var todayEntries: [FoodEntry] = []
    @Published var dailyNorms: NutrientData?
    @Published var hasProfile: Bool = false
    @Published var userProfile: UserProfile?
    @Published var todayTotals: NutrientData = NutrientData()
    @Published var recentDates: [String] = []
    @Published var cachedFoods: [FoodCache] = []

    // Dialogs
    @Published var showConfirmDialog: Bool = false
    @Published var pendingFood: FoodAnalysisResult?
    @Published var pendingFoodOriginalInput: String = ""
    @Published var pendingFoodWeight: Double = 0
    @Published var pendingFoodSource: String = "manual"

    @Published var showEditDialog: Bool = false
    @Published var editingEntry: FoodEntry?
    @Published var editWeight: String = ""

    @Published var showBarcodeWeightDialog: Bool = false
    @Published var barcodeProductName: String?
    @Published var barcodeNutrientsPer100g: NutrientData?
    @Published var barcodeWeight: String = "100"

    // Set when a NutriTrack QR share is scanned (URL points at our web share page or custom scheme)
    @Published var importedSharedFood: SharedFood?

    @Published var showPhotoEditDialog: Bool = false
    @Published var photoFoodName: String = ""
    @Published var photoOriginalFoodName: String = ""
    @Published var photoWeight: String = "200"
    @Published var photoNutrientsPer100g: NutrientData?
    @Published var photoFoodNameEn: String = ""

    private var refreshTimer: Timer?

    init() {
        loadData()
        startAutoRefresh()
    }

    func loadData() {
        userProfile = repo.getProfile()
        hasProfile = userProfile != nil
        dailyNorms = repo.getDailyNorms()
        refreshTodayData()
        recentDates = repo.getRecentDates()
        cachedFoods = repo.getAllCachedFoods()
    }

    /// Full state reset when the account changes (sign-out/deletion/account_deleted).
    /// Clears both transient/dialog/pending fields and in-memory copies of DB data —
    /// so the previous user's data doesn't "leak" into the next session.
    func reset() {
        foodInput = ""
        isLoading = false
        errorMessage = nil
        todayEntries = []
        dailyNorms = nil
        hasProfile = false
        userProfile = nil
        todayTotals = NutrientData()
        recentDates = []
        cachedFoods = []
        showConfirmDialog = false
        pendingFood = nil
        pendingFoodOriginalInput = ""
        pendingFoodWeight = 0
        pendingFoodSource = "manual"
        showEditDialog = false
        editingEntry = nil
        editWeight = ""
        showBarcodeWeightDialog = false
        barcodeProductName = nil
        barcodeNutrientsPer100g = nil
        barcodeWeight = "100"
        importedSharedFood = nil
        showPhotoEditDialog = false
        photoFoodName = ""
        photoOriginalFoodName = ""
        photoWeight = "200"
        photoNutrientsPer100g = nil
        photoFoodNameEn = ""
    }

    func refreshTodayData() {
        todayEntries = repo.getTodayEntries()
        todayTotals = todayEntries.reduce(NutrientData()) { acc, entry in
            acc + repo.parseNutrients(entry.nutrientsJson)
        }
        cachedFoods = repo.getAllCachedFoods()
    }

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshTodayData()
            }
        }
    }

    // MARK: - Food Analysis

    func analyzeFood() {
        let input = foodInput.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let results = try await repo.analyzeFoodText(input)
                if results.count == 1 {
                    let result = results[0]
                    pendingFood = result
                    pendingFoodOriginalInput = input
                    pendingFoodWeight = result.weightGrams > 0 ? result.weightGrams : extractWeight(from: input)
                    pendingFoodSource = "manual"
                    cachedFoods = repo.getAllCachedFoods()
                    showConfirmDialog = true
                } else {
                    for result in results {
                        let weight = result.weightGrams > 0 ? result.weightGrams : 100.0
                        repo.addFoodEntry(foodName: result.foodName, foodNameEn: result.foodNameEn, weightGrams: weight, nutrients: result.nutrients, source: "manual", fromCache: result.fromCache)
                    }
                    foodInput = ""
                    refreshTodayData()
                }
                isLoading = false
            } catch {
                isLoading = false
                errorMessage = String(format: String(localized: "Ошибка анализа: %@"), error.localizedDescription)
            }
        }
    }

    func confirmAddFood() {
        guard let food = pendingFood else { return }
        let newWeight = pendingFoodWeight
        let nutrients: NutrientData
        if food.weightGrams > 0 && newWeight != food.weightGrams {
            nutrients = food.nutrients * (newWeight / food.weightGrams)
        } else {
            nutrients = food.nutrients
        }

        let foodName = pendingFoodOriginalInput.isEmpty ? food.foodName : pendingFoodOriginalInput
        repo.addFoodEntry(foodName: foodName, foodNameEn: food.foodNameEn, weightGrams: newWeight, nutrients: nutrients, source: pendingFoodSource, fromCache: food.fromCache)
        showConfirmDialog = false
        pendingFood = nil
        pendingFoodOriginalInput = ""
        foodInput = ""
        refreshTodayData()
    }

    func dismissConfirmDialog() {
        showConfirmDialog = false
        pendingFood = nil
        pendingFoodOriginalInput = ""
    }

    // MARK: - Entry Management

    func deleteEntry(_ entry: FoodEntry) {
        repo.deleteFoodEntry(entry)
        refreshTodayData()
    }

    func showEditWeight(for entry: FoodEntry) {
        editingEntry = entry
        editWeight = String(Int(entry.weightGrams))
        showEditDialog = true
    }

    func confirmEditWeight() {
        guard let entry = editingEntry, let newWeight = Double(editWeight) else { return }
        repo.updateFoodEntryWeight(entry, newWeight: newWeight)
        showEditDialog = false
        editingEntry = nil
        refreshTodayData()
    }

    func dismissEditDialog() {
        showEditDialog = false
        editingEntry = nil
    }

    func updateMultipleWeights(_ changes: [FoodEntry: Double]) {
        for (entry, weight) in changes {
            repo.updateFoodEntryWeight(entry, newWeight: weight)
        }
        refreshTodayData()
    }

    // MARK: - Barcode

    func onBarcodeScanned(_ barcode: String) {
        // This lets the same "Scan" flow work for both product barcodes and shared foods.
        if let url = URL(string: barcode), let shared = FoodShare.parseShareLink(url) {
            importedSharedFood = shared
            return
        }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                if let result = try await repo.lookupBarcodeWithCache(barcode) {
                    barcodeProductName = result.name
                    barcodeNutrientsPer100g = result.nutrients
                    barcodeWeight = "100"
                    showBarcodeWeightDialog = true
                } else {
                    errorMessage = String(format: String(localized: "Продукт не найден по штрих-коду: %@"), barcode)
                }
                isLoading = false
            } catch {
                isLoading = false
                errorMessage = String(format: String(localized: "Ошибка поиска: %@"), error.localizedDescription)
            }
        }
    }

    func lookupBarcodeForIngredient(_ barcode: String) async -> (name: String, cache: FoodCache?)? {
        await repo.lookupBarcodeForIngredient(barcode)
    }

    func confirmBarcodeAdd() {
        guard let name = barcodeProductName,
              let per100g = barcodeNutrientsPer100g,
              let weight = Double(barcodeWeight) else { return }
        let nutrients = per100g * (weight / 100.0)
        pendingFood = FoodAnalysisResult(
            foodName: name, foodNameEn: name,
            weightGrams: weight, nutrients: nutrients, fromCache: true
        )
        pendingFoodWeight = weight
        pendingFoodSource = "barcode"
        showBarcodeWeightDialog = false
        barcodeProductName = nil
        barcodeNutrientsPer100g = nil
        showConfirmDialog = true
    }

    func dismissBarcodeDialog() {
        showBarcodeWeightDialog = false
        barcodeProductName = nil
        barcodeNutrientsPer100g = nil
    }

    // MARK: - Photo

    func analyzePhoto(_ imageData: Data) {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let result = try await repo.identifyAndAnalyzeFoodFromPhoto(imageData)
                photoFoodName = result.foodName
                photoOriginalFoodName = result.foodName
                photoFoodNameEn = result.foodNameEn
                photoWeight = String(Int(result.weightGrams))
                photoNutrientsPer100g = result.nutrients
                showPhotoEditDialog = true
                isLoading = false
            } catch {
                isLoading = false
                if error.localizedDescription.contains("resolve host") || error.localizedDescription.contains("No address") {
                    errorMessage = String(localized: "Нет подключения к интернету. Проверьте сеть и попробуйте снова.")
                } else if error.localizedDescription.contains("timeout") {
                    errorMessage = String(localized: "Превышено время ожидания. Проверьте интернет и попробуйте снова.")
                } else {
                    errorMessage = String(format: String(localized: "Ошибка распознавания фото: %@"), error.localizedDescription)
                }
            }
        }
    }

    func confirmPhotoAnalysis() {
        let foodDesc = photoFoodName.trimmingCharacters(in: .whitespaces)
        guard !foodDesc.isEmpty else { return }
        let weightGrams = Double(photoWeight) ?? 200.0
        let nameChanged = foodDesc != photoOriginalFoodName.trimmingCharacters(in: .whitespaces)

        if let per100g = photoNutrientsPer100g, !nameChanged {
            showPhotoEditDialog = false
            isLoading = true
            let nameEn = photoFoodNameEn
            photoNutrientsPer100g = nil
            Task {
                let enriched = await repo.enrichMicrosWithAIPublic(per100g, foodNameEn: nameEn)
                let factor = weightGrams / 100.0
                let result = FoodAnalysisResult(
                    foodName: foodDesc, foodNameEn: nameEn,
                    weightGrams: weightGrams, nutrients: enriched * factor, fromCache: false
                )
                isLoading = false
                pendingFood = result
                pendingFoodWeight = weightGrams
                pendingFoodSource = "photo"
                showConfirmDialog = true
            }
        } else {
            showPhotoEditDialog = false
            isLoading = true
            Task {
                do {
                    let result = try await repo.analyzeSingleDish(foodDesc, weightGrams: weightGrams, useCache: false)
                    pendingFood = result
                    pendingFoodWeight = result.weightGrams
                    pendingFoodSource = "photo"
                    showConfirmDialog = true
                    isLoading = false
                } catch {
                    isLoading = false
                    errorMessage = String(format: String(localized: "Ошибка анализа: %@"), error.localizedDescription)
                }
            }
        }
    }

    func dismissPhotoEditDialog() {
        showPhotoEditDialog = false
    }

    // MARK: - Profile

    func updateProfile(gender: String, age: Int, weight: Double, height: Double, goals: String, onComplete: @escaping () -> Void) {
        // Only the expensive AI norms recalculation is gated behind an actual
        // change in physiological inputs. Language / units live elsewhere and
        // never reach this method, so they can't trigger a recalculation.
        let old = repo.getProfile()
        let physiologyChanged: Bool = {
            guard let old else { return true }
            return Gender.from(stored: gender) != Gender.from(stored: old.gender)
                || age != old.age
                || weight != old.weightKg
                || height != old.heightCm
                || goals.trimmingCharacters(in: .whitespacesAndNewlines) != old.goalsText.trimmingCharacters(in: .whitespacesAndNewlines)
        }()

        isLoading = true
        errorMessage = nil
        Task {
            do {
                repo.saveProfile(gender: gender, age: age, weight: weight, height: height, goals: goals)
                if physiologyChanged {
                    let _ = try await repo.calculateAndSaveNorms(gender: gender, age: age, weight: weight, height: height, goals: goals)
                }
                isLoading = false
                loadData()
                onComplete()
            } catch {
                isLoading = false
                errorMessage = String(format: String(localized: "Ошибка обновления профиля: %@"), error.localizedDescription)
            }
        }
    }

    // MARK: - Cache

    func deleteCachedFood(_ entry: FoodCache) {
        repo.deleteCachedFood(entry)
        cachedFoods = repo.getAllCachedFoods()
    }

    func deleteAllCachedFoods() {
        repo.deleteAllCachedFoods()
        cachedFoods = []
    }

    func deleteAllBarcodeEntries() {
        repo.deleteAllBarcodeEntries()
        cachedFoods = repo.getAllCachedFoods()
    }

    func addManualCachedFood(nameRu: String, nameEn: String, nutrients: NutrientData) {
        repo.addManualCachedFood(nameRu: nameRu, nameEn: nameEn, nutrients: nutrients)
        cachedFoods = repo.getAllCachedFoods()
    }

    /// Creates a custom dish from a list of ingredients. For each ingredient we call
    /// the same AI/USDA pipeline as the main input, sum the nutrients, normalize
    /// to 100g of the dish and save it as a regular cache entry (the Russian and English
    /// names are identical — it's a user-defined name, it isn't translated).
    func createCustomDish(name: String, ingredients: [(name: String, weight: Double, cached: FoodCache?)]) async throws {
        var total = NutrientData()
        var totalWeight: Double = 0
        for ing in ingredients {
            let trimmed = ing.name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, ing.weight > 0 else { continue }
            if let cached = ing.cached {
                let per100g = repo.parseNutrients(cached.nutrientsPer100gJson)
                total = total + per100g * (ing.weight / 100.0)
            } else {
                let weightStr = ing.weight.truncatingRemainder(dividingBy: 1) == 0
                    ? "\(Int(ing.weight))г"
                    : "\(ing.weight)г"
                let query = "\(trimmed) \(weightStr)"
                let results: [FoodAnalysisResult]
                do {
                    results = try await repo.analyzeFoodText(query)
                } catch {
                    throw NSError(domain: "CustomDish", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: String(format: String(localized: "Не удалось распознать «%@»: %@"), trimmed, error.localizedDescription)
                    ])
                }
                guard !results.isEmpty else {
                    throw NSError(domain: "CustomDish", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: String(format: String(localized: "Не удалось распознать «%@»"), trimmed)
                    ])
                }
                for r in results { total = total + r.nutrients }
            }
            totalWeight += ing.weight
        }
        guard totalWeight > 0 else {
            throw NSError(domain: "CustomDish", code: 2, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Сумма весов ингредиентов должна быть больше 0")
            ])
        }
        let per100g = total * (100.0 / totalWeight)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        repo.addManualCachedFood(nameRu: trimmedName, nameEn: trimmedName, nutrients: per100g)
        cachedFoods = repo.getAllCachedFoods()
    }

    func updateCachedFoodFull(_ entry: FoodCache, nameRu: String, nameEn: String, nutrients: NutrientData) {
        repo.updateCachedFoodFull(entry, nameRu: nameRu, nameEn: nameEn, nutrients: nutrients)
        cachedFoods = repo.getAllCachedFoods()
    }

    func addCachedFoodToToday(_ cache: FoodCache, weight: Double) {
        isLoading = true
        Task {
            defer { isLoading = false }
            let per100g: NutrientData
            if let enriched = try? await repo.enrichFatDetailsForCachedEntry(cache) {
                per100g = enriched
            } else {
                per100g = repo.parseNutrients(cache.nutrientsPer100gJson)
            }
            let nutrients = per100g * (weight / 100.0)
            repo.addFoodEntry(foodName: cache.keyOriginal, weightGrams: weight, nutrients: nutrients, source: "manual", fromCache: true)
            refreshTodayData()
        }
    }

    // MARK: - Helpers

    func parseNutrients(_ json: String) -> NutrientData {
        repo.parseNutrients(json)
    }

    func saveDailyNorms(_ norms: NutrientData) {
        repo.saveDailyNorms(norms)
        dailyNorms = norms
    }

    func quickAddFromCache(_ cache: FoodCache, weight: Double) {
        let per100g = repo.parseNutrients(cache.nutrientsPer100gJson)
        let nutrients = per100g * (weight / 100.0)
        repo.addFoodEntry(foodName: cache.keyOriginal, weightGrams: weight, nutrients: nutrients, source: "cache", fromCache: true)
        foodInput = ""
        refreshTodayData()
    }

    func clearError() { errorMessage = nil }

    func getEntriesForDate(_ date: String) -> [FoodEntry] {
        repo.getEntriesForDate(date)
    }

    private func extractWeight(from text: String) -> Double {
        WeightParser.parse(text).grams
    }
}
