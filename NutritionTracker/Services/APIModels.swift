import Foundation

// MARK: - OpenRouter Models

struct OpenRouterRequest: Encodable {
    let model: String
    let messages: [OpenRouterMessage]
    let temperature: Float
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

struct OpenRouterMessage: Encodable {
    let role: String
    let content: OpenRouterContent

    enum CodingKeys: String, CodingKey {
        case role, content
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        switch content {
        case .text(let text):
            try container.encode(text, forKey: .content)
        case .parts(let parts):
            try container.encode(parts, forKey: .content)
        }
    }
}

enum OpenRouterContent {
    case text(String)
    case parts([OpenRouterContentPart])
}

struct OpenRouterContentPart: Encodable {
    let type: String
    let text: String?
    let imageUrl: OpenRouterImageUrl?

    enum CodingKeys: String, CodingKey {
        case type, text
        case imageUrl = "image_url"
    }
}

struct OpenRouterImageUrl: Encodable {
    let url: String
}

struct OpenRouterResponse: Decodable {
    let id: String?
    let choices: [OpenRouterChoice]?
    let error: OpenRouterError?
}

struct OpenRouterChoice: Decodable {
    let message: OpenRouterResponseMessage?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

struct OpenRouterResponseMessage: Decodable {
    let content: String?
    let reasoning: String?
}

struct OpenRouterError: Decodable {
    let code: Int?
    let message: String?
}

// MARK: - USDA Models

struct UsdaSearchResponse: Decodable {
    let foods: [UsdaFood]?
    let totalHits: Int?
}

struct UsdaFood: Decodable {
    let fdcId: Int?
    let description: String?
    let dataType: String?
    let foodNutrients: [UsdaFoodNutrient]?
}

struct UsdaFoodNutrient: Decodable {
    let nutrientId: Int?
    let nutrientName: String?
    let nutrientNumber: String?
    let unitName: String?
    let value: Double?

    // USDA nutrient IDs
    static let ENERGY = 1008
    static let PROTEIN = 1003
    static let FAT = 1004
    static let SATURATED_FAT = 1258
    static let MONOUNSATURATED_FAT = 1292
    static let POLYUNSATURATED_FAT = 1293
    static let CHOLESTEROL = 1253
    static let CARBS = 1005
    static let FIBER = 1079
    static let VITAMIN_A = 1106
    static let VITAMIN_B1 = 1165
    static let VITAMIN_B2 = 1166
    static let VITAMIN_B3 = 1167
    static let VITAMIN_B5 = 1170
    static let VITAMIN_B6 = 1175
    static let VITAMIN_B7 = 1176
    static let VITAMIN_B9 = 1177
    static let VITAMIN_B12 = 1178
    static let VITAMIN_C = 1162
    static let VITAMIN_D = 1114
    static let VITAMIN_E = 1109
    static let VITAMIN_K = 1185
    static let CALCIUM = 1087
    static let IRON = 1089
    static let MAGNESIUM = 1090
    static let PHOSPHORUS = 1091
    static let POTASSIUM = 1092
    static let SODIUM = 1093
    static let ZINC = 1095
    static let COPPER = 1098
    static let MANGANESE = 1101
    static let SELENIUM = 1103
    static let IODINE = 1100
}

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
    let brands: String?
    let nutriments: OFFNutriments?
    let servingSize: String?
    let servingQuantity: Double?
    let categoriesTags: [String]?

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case productNameEn = "product_name_en"
        case brands, nutriments
        case servingSize = "serving_size"
        case servingQuantity = "serving_quantity"
        case categoriesTags = "categories_tags"
    }
}

struct OFFSearchResponse: Decodable {
    let count: Int?
    let products: [OFFProduct]?
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
