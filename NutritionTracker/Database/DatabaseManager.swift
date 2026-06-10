import Foundation
import SwiftData

@MainActor
class DatabaseManager {
    static let shared = DatabaseManager()

    let container: ModelContainer

    private init() {
        // Ensure Application Support directory exists before SwiftData tries to create the store
        let fileManager = FileManager.default
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            if !fileManager.fileExists(atPath: appSupport.path) {
                try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
            }
        }

        let schema = Schema([
            UserProfile.self,
            DailyNorms.self,
            FoodEntry.self,
            FoodCache.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var context: ModelContext {
        container.mainContext
    }

    // MARK: - User Profile

    func getProfile() -> UserProfile? {
        let descriptor = FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return try? context.fetch(descriptor).first
    }

    func saveProfile(gender: String, age: Int, weight: Double, height: Double, goals: String) {
        let profile = UserProfile(gender: gender, age: age, weightKg: weight, heightCm: height, goalsText: goals)
        context.insert(profile)
        try? context.save()
    }

    // MARK: - Daily Norms

    func getDailyNorms() -> DailyNorms? {
        let descriptor = FetchDescriptor<DailyNorms>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return try? context.fetch(descriptor).first
    }

    func saveDailyNorms(nutrientsJson: String) {
        // Delete old norms
        let all = (try? context.fetch(FetchDescriptor<DailyNorms>())) ?? []
        for item in all { context.delete(item) }
        let norms = DailyNorms(nutrientsJson: nutrientsJson)
        context.insert(norms)
        try? context.save()
    }

    // MARK: - Food Entries

    func getEntriesForDate(_ date: String) -> [FoodEntry] {
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date == date },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func getEntriesForDateRange(start: String, end: String) -> [FoodEntry] {
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= start && $0.date <= end },
            sortBy: [SortDescriptor(\.date, order: .reverse), SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func getRecentDates(limit: Int = 14) -> [String] {
        let descriptor = FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let entries = (try? context.fetch(descriptor)) ?? []
        let dates = Array(Set(entries.map(\.date))).sorted(by: >)
        return Array(dates.prefix(limit))
    }

    func getAllDates() -> [String] {
        let descriptor = FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let entries = (try? context.fetch(descriptor)) ?? []
        return Array(Set(entries.map(\.date))).sorted(by: >)
    }

    func addFoodEntry(date: String, foodName: String, weightGrams: Double, nutrients: NutrientData, source: String = "manual", fromCache: Bool = false) {
        let json = (try? JSONEncoder().encode(nutrients)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let entry = FoodEntry(date: date, foodName: foodName, weightGrams: weightGrams, nutrientsJson: json, source: source, fromCache: fromCache)
        context.insert(entry)
        try? context.save()
    }

    func updateFoodEntryWeight(entry: FoodEntry, newWeight: Double) {
        guard let oldNutrients = parseNutrients(entry.nutrientsJson) else { return }
        let factor = entry.weightGrams > 0 ? newWeight / entry.weightGrams : 1.0
        let newNutrients = oldNutrients * factor
        entry.weightGrams = newWeight
        entry.nutrientsJson = encodeNutrients(newNutrients)
        try? context.save()
    }

    func deleteFoodEntry(_ entry: FoodEntry) {
        context.delete(entry)
        try? context.save()
    }

    func cleanupOldEntries() {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let cutoffStr = Self.dateFormatter.string(from: cutoffDate)
        let descriptor = FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.date < cutoffStr })
        if let old = try? context.fetch(descriptor) {
            for entry in old { context.delete(entry) }
            try? context.save()
        }
    }

    // MARK: - Food Cache

    func findInCache(key: String) -> FoodCache? {
        let normalized = normalizeKey(key)
        let descriptor = FetchDescriptor<FoodCache>(predicate: #Predicate { $0.keyNormalized == normalized })
        if let found = try? context.fetch(descriptor).first { return found }
        // Try by English key
        let descEn = FetchDescriptor<FoodCache>(predicate: #Predicate { $0.keyEn == normalized })
        return try? context.fetch(descEn).first
    }

    func saveToCache(keyOriginal: String, keyEn: String, nutrientsPer100g: NutrientData) {
        let normalized = normalizeKey(keyOriginal)
        // Check duplicates
        let desc1 = FetchDescriptor<FoodCache>(predicate: #Predicate { $0.keyNormalized == normalized })
        if (try? context.fetch(desc1).first) != nil { return }

        if !keyOriginal.hasPrefix("barcode:") && !keyOriginal.hasPrefix("supplement:") {
            let normalizedEn = normalizeKey(keyEn)
            let desc2 = FetchDescriptor<FoodCache>(predicate: #Predicate { $0.keyEn == normalizedEn })
            if (try? context.fetch(desc2).first) != nil { return }
        }

        let json = encodeNutrients(nutrientsPer100g)
        let entry = FoodCache(keyOriginal: keyOriginal, keyNormalized: normalized, keyEn: keyEn, nutrientsPer100gJson: json)
        context.insert(entry)
        try? context.save()
    }

    func getAllCachedFoods() -> [FoodCache] {
        let descriptor = FetchDescriptor<FoodCache>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let all = (try? context.fetch(descriptor)) ?? []
        return all.filter { !$0.keyOriginal.hasPrefix("barcode:") && !$0.keyOriginal.hasPrefix("supplement:") }
    }

    func deleteCachedFood(_ entry: FoodCache) {
        if !entry.keyOriginal.hasPrefix("barcode:") && !entry.keyOriginal.hasPrefix("supplement:") {
            // Also delete barcode/supplement entries for same product
            let keyEn = entry.keyEn
            let desc = FetchDescriptor<FoodCache>(predicate: #Predicate {
                ($0.keyOriginal.contains("barcode:") || $0.keyOriginal.contains("supplement:")) && $0.keyEn == keyEn
            })
            if let related = try? context.fetch(desc) {
                for r in related { context.delete(r) }
            }
        }
        context.delete(entry)
        try? context.save()
    }

    func deleteAllCachedFoods() {
        let all = (try? context.fetch(FetchDescriptor<FoodCache>())) ?? []
        for item in all { context.delete(item) }
        try? context.save()
    }

    func updateCachedFoodNutrients(_ entry: FoodCache, nutrients: NutrientData) {
        entry.nutrientsPer100gJson = encodeNutrients(nutrients)
        try? context.save()
    }

    func updateCachedFoodFull(_ entry: FoodCache, nameRu: String, nameEn: String, nutrients: NutrientData) {
        entry.keyOriginal = nameRu
        entry.keyNormalized = normalizeKey(nameRu)
        entry.keyEn = nameEn
        entry.nutrientsPer100gJson = encodeNutrients(nutrients)
        try? context.save()
    }

    // MARK: - Helpers

    func normalizeKey(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: " ")
    }

    func parseNutrients(_ json: String) -> NutrientData? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NutrientData.self, from: data)
    }

    func encodeNutrients(_ nutrients: NutrientData) -> String {
        guard let data = try? JSONEncoder().encode(nutrients),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func todayDate() -> String {
        dateFormatter.string(from: Date())
    }
}
