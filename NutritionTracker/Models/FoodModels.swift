import Foundation

struct FoodAnalysisResult {
    let foodName: String
    let foodNameEn: String
    let weightGrams: Double
    let nutrients: NutrientData
    let fromCache: Bool
}

struct FoodIdentity: Codable {
    let foodName: String
    let foodNameEn: String
    let weightGrams: Double

    enum CodingKeys: String, CodingKey {
        case foodName = "food_name"
        case foodNameEn = "food_name_en"
        case weightGrams = "weight_grams"
    }
}

struct SupplementResult {
    let name: String
    let nutrientsPerServing: NutrientData
    let servingSize: String
    let fromCache: Bool
}
