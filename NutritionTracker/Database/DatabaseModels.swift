import Foundation
import SwiftData

@Model
final class UserProfile {
    var gender: String
    var age: Int
    var weightKg: Double
    var heightCm: Double
    var goalsText: String
    var createdAt: Date

    init(gender: String, age: Int, weightKg: Double, heightCm: Double, goalsText: String) {
        self.gender = gender
        self.age = age
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.goalsText = goalsText
        self.createdAt = Date()
    }
}

@Model
final class DailyNorms {
    var nutrientsJson: String
    var createdAt: Date

    init(nutrientsJson: String) {
        self.nutrientsJson = nutrientsJson
        self.createdAt = Date()
    }
}

@Model
final class FoodEntry {
    var date: String
    var foodName: String
    var weightGrams: Double
    var nutrientsJson: String
    var source: String
    var fromCache: Bool
    var createdAt: Date

    init(date: String, foodName: String, weightGrams: Double, nutrientsJson: String, source: String = "manual", fromCache: Bool = false) {
        self.date = date
        self.foodName = foodName
        self.weightGrams = weightGrams
        self.nutrientsJson = nutrientsJson
        self.source = source
        self.fromCache = fromCache
        self.createdAt = Date()
    }
}

@Model
final class FoodCache {
    @Attribute(.unique) var keyNormalized: String
    var keyOriginal: String
    var keyEn: String
    var nutrientsPer100gJson: String
    var createdAt: Date

    init(keyOriginal: String, keyNormalized: String, keyEn: String, nutrientsPer100gJson: String) {
        self.keyOriginal = keyOriginal
        self.keyNormalized = keyNormalized
        self.keyEn = keyEn
        self.nutrientsPer100gJson = nutrientsPer100gJson
        self.createdAt = Date()
    }
}
