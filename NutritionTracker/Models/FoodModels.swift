import Foundation

struct FoodAnalysisResult {
    let foodName: String
    let foodNameEn: String
    let weightGrams: Double
    let nutrients: NutrientData
    let fromCache: Bool
}
