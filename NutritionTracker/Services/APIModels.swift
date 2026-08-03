import Foundation

// Models only for OpenFoodFacts (barcode/supplements — the client parses OFF itself).
// OpenRouter/USDA models removed: those calls moved to the backend (see NetworkService).

// MARK: - OpenFoodFacts Models

struct OpenFoodFactsResponse: Decodable {
    let status: Int?
    let statusVerbose: String?
    let product: OFFProduct?

    enum CodingKeys: String, CodingKey {
        case status
        case statusVerbose = "status_verbose"
        case product
    }
}

struct OFFProduct: Decodable {
    let productName: String?
    let productNameEn: String?
    let productNameRu: String?
    let productNameUk: String?
    let brands: String?
    let nutriments: OFFNutriments?
    let servingSize: String?
    let servingQuantity: Double?
    let categoriesTags: [String]?

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case productNameEn = "product_name_en"
        case productNameRu = "product_name_ru"
        case productNameUk = "product_name_uk"
        case brands, nutriments
        case servingSize = "serving_size"
        case servingQuantity = "serving_quantity"
        case categoriesTags = "categories_tags"
    }
}

struct OFFNutriments: Decodable {
    let energyKcal100g: Double?
    let proteins100g: Double?
    let fat100g: Double?
    let carbohydrates100g: Double?
    let fiber100g: Double?
    let saturatedFat100g: Double?
    let monounsaturatedFat100g: Double?
    let polyunsaturatedFat100g: Double?
    let cholesterol100g: Double?
    let vitaminA100g: Double?
    let vitaminB1100g: Double?
    let vitaminB2100g: Double?
    let vitaminB3100g: Double?
    let vitaminB5100g: Double?
    let vitaminB6100g: Double?
    let vitaminB7100g: Double?
    let vitaminB9100g: Double?
    let vitaminB12100g: Double?
    let vitaminC100g: Double?
    let vitaminD100g: Double?
    let vitaminE100g: Double?
    let vitaminK100g: Double?
    let calcium100g: Double?
    let iron100g: Double?
    let magnesium100g: Double?
    let phosphorus100g: Double?
    let potassium100g: Double?
    let sodium100g: Double?
    let zinc100g: Double?
    let copper100g: Double?
    let manganese100g: Double?
    let selenium100g: Double?
    let iodine100g: Double?

    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case proteins100g = "proteins_100g"
        case fat100g = "fat_100g"
        case carbohydrates100g = "carbohydrates_100g"
        case fiber100g = "fiber_100g"
        case saturatedFat100g = "saturated-fat_100g"
        case monounsaturatedFat100g = "monounsaturated-fat_100g"
        case polyunsaturatedFat100g = "polyunsaturated-fat_100g"
        case cholesterol100g = "cholesterol_100g"
        case vitaminA100g = "vitamin-a_100g"
        case vitaminB1100g = "vitamin-b1_100g"
        case vitaminB2100g = "vitamin-b2_100g"
        case vitaminB3100g = "vitamin-pp_100g"
        case vitaminB5100g = "pantothenic-acid_100g"
        case vitaminB6100g = "vitamin-b6_100g"
        case vitaminB7100g = "biotin_100g"
        case vitaminB9100g = "vitamin-b9_100g"
        case vitaminB12100g = "vitamin-b12_100g"
        case vitaminC100g = "vitamin-c_100g"
        case vitaminD100g = "vitamin-d_100g"
        case vitaminE100g = "vitamin-e_100g"
        case vitaminK100g = "vitamin-k_100g"
        case calcium100g = "calcium_100g"
        case iron100g = "iron_100g"
        case magnesium100g = "magnesium_100g"
        case phosphorus100g = "phosphorus_100g"
        case potassium100g = "potassium_100g"
        case sodium100g = "sodium_100g"
        case zinc100g = "zinc_100g"
        case copper100g = "copper_100g"
        case manganese100g = "manganese_100g"
        case selenium100g = "selenium_100g"
        case iodine100g = "iodine_100g"
    }
}
