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

    @Published var showSupplementDialog: Bool = false
    @Published var supplementName: String?
    @Published var supplementNutrientsPerServing: NutrientData?
    @Published var supplementServingSize: String = ""
    @Published var supplementServings: String = "1"

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
                    pendingFoodWeight = result.weightGrams > 0 ? result.weightGrams : extractWeight(from: input)
                    pendingFoodSource = "manual"
                    cachedFoods = repo.getAllCachedFoods()
                    showConfirmDialog = true
                } else {
                    for result in results {
                        let weight = result.weightGrams > 0 ? result.weightGrams : 100.0
                        repo.addFoodEntry(foodName: result.foodName, weightGrams: weight, nutrients: result.nutrients, source: "manual", fromCache: result.fromCache)
                    }
                    foodInput = ""
                    refreshTodayData()
                }
                isLoading = false
            } catch {
                isLoading = false
                errorMessage = "Ошибка анализа: \(error.localizedDescription)"
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

        repo.addFoodEntry(foodName: food.foodName, weightGrams: newWeight, nutrients: nutrients, source: pendingFoodSource, fromCache: food.fromCache)
        showConfirmDialog = false
        pendingFood = nil
        foodInput = ""
        refreshTodayData()
    }

    func dismissConfirmDialog() {
        showConfirmDialog = false
        pendingFood = nil
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
        // If the scanned code is actually a NutriTrack share QR, parse and import.
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
                    errorMessage = "Продукт не найден по штрих-коду: \(barcode)"
                }
                isLoading = false
            } catch {
                isLoading = false
                errorMessage = "Ошибка поиска: \(error.localizedDescription)"
            }
        }
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

    // MARK: - Supplement

    func onSupplementBarcodeScanned(_ barcode: String) {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                if let result = try await repo.lookupSupplementBarcode(barcode) {
                    supplementName = result.name
                    supplementNutrientsPerServing = result.nutrientsPerServing
                    supplementServingSize = result.servingSize
                    supplementServings = "1"
                    showSupplementDialog = true
                } else {
                    errorMessage = "БАД не найден по штрих-коду: \(barcode)"
                }
                isLoading = false
            } catch {
                isLoading = false
                errorMessage = "Ошибка поиска БАД: \(error.localizedDescription)"
            }
        }
    }

    func confirmSupplementAdd() {
        guard let name = supplementName,
              let perServing = supplementNutrientsPerServing,
              let servings = Double(supplementServings) else { return }
        let nutrients = perServing * servings
        repo.addFoodEntry(foodName: "💊 \(name)", weightGrams: servings, nutrients: nutrients, source: "supplement", fromCache: true)
        showSupplementDialog = false
        supplementName = nil
        supplementNutrientsPerServing = nil
        refreshTodayData()
    }

    func dismissSupplementDialog() {
        showSupplementDialog = false
        supplementName = nil
        supplementNutrientsPerServing = nil
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
                    errorMessage = "Нет подключения к интернету. Проверьте сеть и попробуйте снова."
                } else if error.localizedDescription.contains("timeout") {
                    errorMessage = "Превышено время ожидания. Проверьте интернет и попробуйте снова."
                } else {
                    errorMessage = "Ошибка распознавания фото: \(error.localizedDescription)"
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
                    errorMessage = "Ошибка анализа: \(error.localizedDescription)"
                }
            }
        }
    }

    func dismissPhotoEditDialog() {
        showPhotoEditDialog = false
    }

    // MARK: - Profile

    func updateProfile(gender: String, age: Int, weight: Double, height: Double, goals: String, onComplete: @escaping () -> Void) {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                repo.saveProfile(gender: gender, age: age, weight: weight, height: height, goals: goals)
                let _ = try await repo.calculateAndSaveNorms(gender: gender, age: age, weight: weight, height: height, goals: goals)
                isLoading = false
                loadData()
                onComplete()
            } catch {
                isLoading = false
                errorMessage = "Ошибка обновления профиля: \(error.localizedDescription)"
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

    func addManualCachedFood(nameRu: String, nameEn: String, nutrients: NutrientData) {
        repo.addManualCachedFood(nameRu: nameRu, nameEn: nameEn, nutrients: nutrients)
        cachedFoods = repo.getAllCachedFoods()
    }

    /// Создаёт кастомное блюдо из списка ингредиентов. Для каждого ингредиента вызываем
    /// тот же AI/USDA-pipeline что и при основном вводе, суммируем нутриенты, нормализуем
    /// к 100г блюда и сохраняем как обычную запись в кеш (имя на русском и английском
    /// одинаковое — это пользовательское имя, оно не переводится).
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
                        NSLocalizedDescriptionKey: "Не удалось распознать «\(trimmed)»: \(error.localizedDescription)"
                    ])
                }
                guard !results.isEmpty else {
                    throw NSError(domain: "CustomDish", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Не удалось распознать «\(trimmed)»"
                    ])
                }
                for r in results { total = total + r.nutrients }
            }
            totalWeight += ing.weight
        }
        guard totalWeight > 0 else {
            throw NSError(domain: "CustomDish", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Сумма весов ингредиентов должна быть больше 0"
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
        let per100g = repo.parseNutrients(cache.nutrientsPer100gJson)
        let nutrients = per100g * (weight / 100.0)
        repo.addFoodEntry(foodName: cache.keyOriginal, weightGrams: weight, nutrients: nutrients, source: "cache", fromCache: true)
        refreshTodayData()
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
        let pattern = #"(\d+)\s*(г|гр|грамм|g|ml|мл)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return 0 }
        return Double(text[range]) ?? 0
    }
}
