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
        // Backfill the language-neutral cache key for rows created before this field existed.
        backfillKeyEnNormalizedIfNeeded()
    }

    var context: ModelContext {
        container.mainContext
    }

    /// Полное физическое удаление всех локальных данных пользователя.
    /// Используется при выходе/удалении аккаунта (не soft delete).
    func wipeAllLocalData() {
        for entry in (try? context.fetch(FetchDescriptor<FoodEntry>())) ?? [] { context.delete(entry) }
        for cache in (try? context.fetch(FetchDescriptor<FoodCache>())) ?? [] { context.delete(cache) }
        for norms in (try? context.fetch(FetchDescriptor<DailyNorms>())) ?? [] { context.delete(norms) }
        for profile in (try? context.fetch(FetchDescriptor<UserProfile>())) ?? [] { context.delete(profile) }
        try? context.save()
        // Чистим временные CSV-экспорты (история питания прошлого юзера).
        let tmp = FileManager.default.temporaryDirectory
        if let files = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
            for f in files where f.pathExtension == "csv" {
                try? FileManager.default.removeItem(at: f)
            }
        }
    }

    // MARK: - User Profile

    func getProfile() -> UserProfile? {
        let descriptor = FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return try? context.fetch(descriptor).first
    }

    func saveProfile(gender: String, age: Int, weight: Double, height: Double, goals: String) {
        // Обновляем существующий ряд (сохраняя updatedAt-семантику), иначе создаём.
        if let existing = getProfile() {
            existing.gender = gender; existing.age = age; existing.weightKg = weight
            existing.heightCm = height; existing.goalsText = goals
            existing.updatedAt = Date(); existing.deletedAt = nil
        } else {
            let profile = UserProfile(gender: gender, age: age, weightKg: weight, heightCm: height, goalsText: goals)
            context.insert(profile)
        }
        try? context.save()
    }

    // MARK: - Daily Norms

    func getDailyNorms() -> DailyNorms? {
        let descriptor = FetchDescriptor<DailyNorms>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return try? context.fetch(descriptor).first
    }

    func saveDailyNorms(nutrientsJson: String) {
        // Обновляем единственный ряд норм (для корректной синхронизации updatedAt).
        if let existing = getDailyNorms() {
            existing.nutrientsJson = nutrientsJson
            existing.updatedAt = Date(); existing.deletedAt = nil
        } else {
            let norms = DailyNorms(nutrientsJson: nutrientsJson)
            context.insert(norms)
        }
        try? context.save()
    }

    // MARK: - Food Entries

    func getEntriesForDate(_ date: String) -> [FoodEntry] {
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date == date && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func getEntriesForDateRange(start: String, end: String) -> [FoodEntry] {
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= start && $0.date <= end && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.date, order: .reverse), SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func getRecentDates(limit: Int = 14) -> [String] {
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let entries = (try? context.fetch(descriptor)) ?? []
        let dates = Array(Set(entries.map(\.date))).sorted(by: >)
        return Array(dates.prefix(limit))
    }

    func getAllDates() -> [String] {
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let entries = (try? context.fetch(descriptor)) ?? []
        return Array(Set(entries.map(\.date))).sorted(by: >)
    }

    func addFoodEntry(date: String, foodName: String, foodNameEn: String = "", weightGrams: Double, nutrients: NutrientData, source: String = "manual", fromCache: Bool = false) {
        let json = (try? JSONEncoder().encode(nutrients)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let entry = FoodEntry(date: date, foodName: foodName, foodNameEn: foodNameEn, weightGrams: weightGrams, nutrientsJson: json, source: source, fromCache: fromCache)
        context.insert(entry)
        try? context.save()
    }

    func updateFoodEntryWeight(entry: FoodEntry, newWeight: Double) {
        guard let oldNutrients = parseNutrients(entry.nutrientsJson) else { return }
        let factor = entry.weightGrams > 0 ? newWeight / entry.weightGrams : 1.0
        let newNutrients = oldNutrients * factor
        entry.weightGrams = newWeight
        entry.nutrientsJson = encodeNutrients(newNutrients)
        entry.updatedAt = Date()
        try? context.save()
    }

    func deleteFoodEntry(_ entry: FoodEntry) {
        // Soft delete — синхронизируется как tombstone (см. sync-architecture).
        entry.deletedAt = Date()
        entry.updatedAt = Date()
        try? context.save()
    }

    // MARK: - Food Cache

    func findInCache(key: String) -> FoodCache? {
        let normalized = normalizeKey(key)
        let descriptor = FetchDescriptor<FoodCache>(predicate: #Predicate { $0.keyNormalized == normalized && $0.deletedAt == nil })
        if let found = try? context.fetch(descriptor).first { return found }
        // Try by normalized English key (language-neutral canonical bridge).
        let descEn = FetchDescriptor<FoodCache>(predicate: #Predicate { $0.keyEnNormalized == normalized && $0.deletedAt == nil })
        return try? context.fetch(descEn).first
    }

    func saveToCache(keyOriginal: String, keyEn: String, nutrientsPer100g: NutrientData) {
        let normalized = normalizeKey(keyOriginal)
        let normalizedEn = normalizeKey(keyEn)
        // Если ряд уже есть (включая tombstone) — «воскрешаем»/обновляем его.
        let desc1 = FetchDescriptor<FoodCache>(predicate: #Predicate { $0.keyNormalized == normalized })
        if let existing = try? context.fetch(desc1).first {
            existing.nutrientsPer100gJson = encodeNutrients(nutrientsPer100g)
            existing.keyEn = keyEn; existing.keyEnNormalized = normalizedEn
            existing.deletedAt = nil; existing.updatedAt = Date()
            try? context.save()
            return
        }

        if !keyOriginal.hasPrefix("barcode:") {
            let desc2 = FetchDescriptor<FoodCache>(predicate: #Predicate { $0.keyEnNormalized == normalizedEn && $0.deletedAt == nil })
            if (try? context.fetch(desc2).first) != nil { return }
        }

        let json = encodeNutrients(nutrientsPer100g)
        let entry = FoodCache(keyOriginal: keyOriginal, keyNormalized: normalized, keyEn: keyEn, keyEnNormalized: normalizedEn, nutrientsPer100gJson: json)
        context.insert(entry)
        try? context.save()
    }

    func getAllCachedFoods() -> [FoodCache] {
        let descriptor = FetchDescriptor<FoodCache>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let all = (try? context.fetch(descriptor)) ?? []
        return all.filter { !$0.keyOriginal.hasPrefix("barcode:") && $0.deletedAt == nil }
    }

    func deleteCachedFood(_ entry: FoodCache) {
        if !entry.keyOriginal.hasPrefix("barcode:") {
            // Also soft-delete barcode entries for same product
            let keyEn = entry.keyEn
            let desc = FetchDescriptor<FoodCache>(predicate: #Predicate {
                $0.keyOriginal.contains("barcode:") && $0.keyEn == keyEn
            })
            if let related = try? context.fetch(desc) {
                for r in related { r.deletedAt = Date(); r.updatedAt = Date() }
            }
        }
        entry.deletedAt = Date()
        entry.updatedAt = Date()
        try? context.save()
    }

    func deleteAllCachedFoods() {
        let all = (try? context.fetch(FetchDescriptor<FoodCache>())) ?? []
        for item in all where item.deletedAt == nil {
            item.deletedAt = Date(); item.updatedAt = Date()
        }
        try? context.save()
    }

    /// Deletes only the products that originate from a barcode scan.
    /// Matches the Android behavior: removes every cache row whose keyEn is shared
    /// with a hidden `barcode:` entry (i.e. the visible product plus
    /// its technical barcode rows).
    func deleteAllBarcodeEntries() {
        let all = (try? context.fetch(FetchDescriptor<FoodCache>())) ?? []
        let targetKeyEns = Set(
            all.filter { $0.keyOriginal.hasPrefix("barcode:") }
               .map { $0.keyEn }
        )
        guard !targetKeyEns.isEmpty else { return }
        for item in all where targetKeyEns.contains(item.keyEn) && item.deletedAt == nil {
            item.deletedAt = Date(); item.updatedAt = Date()
        }
        try? context.save()
    }

    func updateCachedFoodNutrients(_ entry: FoodCache, nutrients: NutrientData) {
        entry.nutrientsPer100gJson = encodeNutrients(nutrients)
        entry.updatedAt = Date()
        try? context.save()
    }

    func updateCachedFoodFull(_ entry: FoodCache, nameRu: String, nameEn: String, nutrients: NutrientData) {
        entry.keyOriginal = nameRu
        entry.keyNormalized = normalizeKey(nameRu)
        entry.keyEn = nameEn
        entry.keyEnNormalized = normalizeKey(nameEn)
        entry.nutrientsPer100gJson = encodeNutrients(nutrients)
        entry.updatedAt = Date()
        try? context.save()
    }

    /// One-time backfill of `keyEnNormalized` for cache rows created before the
    /// language-neutral key was introduced. Cheap no-op once all rows are filled.
    func backfillKeyEnNormalizedIfNeeded() {
        let descriptor = FetchDescriptor<FoodCache>(predicate: #Predicate { $0.keyEnNormalized.isEmpty })
        guard let stale = try? context.fetch(descriptor), !stale.isEmpty else { return }
        for row in stale {
            row.keyEnNormalized = normalizeKey(row.keyEn)
        }
        try? context.save()
    }

    // MARK: - Sync (см. sync-architecture)

    private static func ms(_ date: Date) -> Int64 { Int64(date.timeIntervalSince1970 * 1000) }
    private static func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }

    /// Собрать локальную дельту (всё, что изменилось после `since` ms). since=0 → всё.
    func collectChanges(since: Int64) -> SyncPushRequest {
        let sinceDate = Self.date(since)

        var profileDTO: SyncProfileDTO?
        if let p = getProfile(), p.updatedAt > sinceDate {
            profileDTO = SyncProfileDTO(gender: p.gender, age: p.age, weightKg: p.weightKg,
                heightCm: p.heightCm, goalsText: p.goalsText,
                updatedAt: Self.ms(p.updatedAt), deletedAt: p.deletedAt.map(Self.ms))
        }

        var normsDTO: SyncNormsDTO?
        if let n = getDailyNorms(), n.updatedAt > sinceDate {
            normsDTO = SyncNormsDTO(nutrientsJson: n.nutrientsJson,
                updatedAt: Self.ms(n.updatedAt), deletedAt: n.deletedAt.map(Self.ms))
        }

        let entriesDesc = FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.updatedAt > sinceDate })
        let entries = ((try? context.fetch(entriesDesc)) ?? []).map { e in
            SyncEntryDTO(clientId: e.clientId, date: e.date, foodName: e.foodName,
                foodNameEn: e.foodNameEn, weightGrams: e.weightGrams, nutrientsJson: e.nutrientsJson,
                source: e.source, fromCache: e.fromCache, createdAt: Self.ms(e.createdAt),
                updatedAt: Self.ms(e.updatedAt), deletedAt: e.deletedAt.map(Self.ms))
        }

        let cacheDesc = FetchDescriptor<FoodCache>(predicate: #Predicate { $0.updatedAt > sinceDate })
        let cache = ((try? context.fetch(cacheDesc)) ?? []).map { c in
            SyncCacheDTO(keyNormalized: c.keyNormalized, keyOriginal: c.keyOriginal, keyEn: c.keyEn,
                keyEnNormalized: c.keyEnNormalized, nutrientsJson: c.nutrientsPer100gJson,
                createdAt: Self.ms(c.createdAt), updatedAt: Self.ms(c.updatedAt),
                deletedAt: c.deletedAt.map(Self.ms))
        }

        return SyncPushRequest(profile: profileDTO, norms: normsDTO, entries: entries, foodCache: cache)
    }

    /// Применить данные с сервера (last-write-wins по updatedAt).
    func applyPulled(_ resp: SyncPullResponse) {
        // Profile (1 ряд)
        if let dto = resp.profile {
            let existing = getProfile()
            if existing == nil || Self.date(dto.updatedAt) >= (existing!.updatedAt) {
                if let e = existing { context.delete(e) }
                let p = UserProfile(gender: dto.gender, age: dto.age, weightKg: dto.weightKg,
                    heightCm: dto.heightCm, goalsText: dto.goalsText)
                p.updatedAt = Self.date(dto.updatedAt)
                p.deletedAt = dto.deletedAt.map(Self.date)
                context.insert(p)
            }
        }
        // Norms (1 ряд)
        if let dto = resp.norms {
            let existing = getDailyNorms()
            if existing == nil || Self.date(dto.updatedAt) >= (existing!.updatedAt) {
                if let e = existing { context.delete(e) }
                let n = DailyNorms(nutrientsJson: dto.nutrientsJson)
                n.updatedAt = Self.date(dto.updatedAt)
                n.deletedAt = dto.deletedAt.map(Self.date)
                context.insert(n)
            }
        }
        // Food entries (по clientId)
        for dto in resp.entries {
            let cid = dto.clientId
            let desc = FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.clientId == cid })
            let existing = try? context.fetch(desc).first
            if let e = existing ?? nil {
                if Self.date(dto.updatedAt) >= e.updatedAt {
                    e.date = dto.date; e.foodName = dto.foodName; e.foodNameEn = dto.foodNameEn
                    e.weightGrams = dto.weightGrams; e.nutrientsJson = dto.nutrientsJson
                    e.source = dto.source; e.fromCache = dto.fromCache
                    e.updatedAt = Self.date(dto.updatedAt); e.deletedAt = dto.deletedAt.map(Self.date)
                }
            } else {
                let e = FoodEntry(date: dto.date, foodName: dto.foodName, foodNameEn: dto.foodNameEn,
                    weightGrams: dto.weightGrams, nutrientsJson: dto.nutrientsJson,
                    source: dto.source, fromCache: dto.fromCache)
                e.clientId = dto.clientId
                if let c = dto.createdAt { e.createdAt = Self.date(c) }
                e.updatedAt = Self.date(dto.updatedAt); e.deletedAt = dto.deletedAt.map(Self.date)
                context.insert(e)
            }
        }
        // Food cache (по keyNormalized)
        for dto in resp.foodCache {
            let key = dto.keyNormalized
            let desc = FetchDescriptor<FoodCache>(predicate: #Predicate { $0.keyNormalized == key })
            let existing = try? context.fetch(desc).first
            if let c = existing ?? nil {
                if Self.date(dto.updatedAt) >= c.updatedAt {
                    c.keyOriginal = dto.keyOriginal; c.keyEn = dto.keyEn
                    c.keyEnNormalized = dto.keyEnNormalized; c.nutrientsPer100gJson = dto.nutrientsJson
                    c.updatedAt = Self.date(dto.updatedAt); c.deletedAt = dto.deletedAt.map(Self.date)
                }
            } else {
                let c = FoodCache(keyOriginal: dto.keyOriginal, keyNormalized: dto.keyNormalized,
                    keyEn: dto.keyEn, keyEnNormalized: dto.keyEnNormalized,
                    nutrientsPer100gJson: dto.nutrientsJson)
                if let cr = dto.createdAt { c.createdAt = Self.date(cr) }
                c.updatedAt = Self.date(dto.updatedAt); c.deletedAt = dto.deletedAt.map(Self.date)
                context.insert(c)
            }
        }
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
