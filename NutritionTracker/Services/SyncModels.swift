import Foundation

// Sync DTOs. Time is epoch milliseconds (Int64), matching the backend and Android.
// deletedAt != nil -> tombstone (record deleted, synced).

struct SyncProfileDTO: Codable {
    var gender: String
    var age: Int
    var weightKg: Double
    var heightCm: Double
    var goalsText: String
    var updatedAt: Int64
    var deletedAt: Int64?
}

struct SyncNormsDTO: Codable {
    var nutrientsJson: String
    var updatedAt: Int64
    var deletedAt: Int64?
}

struct SyncEntryDTO: Codable {
    var clientId: String
    var date: String
    var foodName: String
    var foodNameEn: String
    var weightGrams: Double
    var nutrientsJson: String
    var source: String
    var fromCache: Bool
    var createdAt: Int64?
    var updatedAt: Int64
    var deletedAt: Int64?
}

struct SyncCacheDTO: Codable {
    var keyNormalized: String
    var keyOriginal: String
    var keyEn: String
    var keyEnNormalized: String
    var nutrientsJson: String
    var createdAt: Int64?
    var updatedAt: Int64
    var deletedAt: Int64?
}

struct SyncPushRequest: Codable {
    var profile: SyncProfileDTO?
    var norms: SyncNormsDTO?
    var entries: [SyncEntryDTO]
    var foodCache: [SyncCacheDTO]
}

struct SyncPushResponse: Codable {
    var ok: Bool
    var serverTime: Int64
}

struct SyncPullResponse: Codable {
    var profile: SyncProfileDTO?
    var norms: SyncNormsDTO?
    var entries: [SyncEntryDTO]
    var foodCache: [SyncCacheDTO]
    var serverTime: Int64
}
