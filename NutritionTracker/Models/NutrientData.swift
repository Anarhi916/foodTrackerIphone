import Foundation

struct NutrientData: Codable, Equatable {
    var calories: Double = 0.0
    var protein: Double = 0.0
    var fat: Double = 0.0
    var saturatedFat: Double = 0.0
    var monounsaturatedFat: Double = 0.0
    var polyunsaturatedFat: Double = 0.0
    var cholesterol: Double = 0.0
    var carbs: Double = 0.0
    var fiber: Double = 0.0
    var vitaminA: Double = 0.0
    var vitaminB1: Double = 0.0
    var vitaminB2: Double = 0.0
    var vitaminB3: Double = 0.0
    var vitaminB5: Double = 0.0
    var vitaminB6: Double = 0.0
    var vitaminB7: Double = 0.0
    var vitaminB9: Double = 0.0
    var vitaminB12: Double = 0.0
    var vitaminC: Double = 0.0
    var vitaminD: Double = 0.0
    var vitaminE: Double = 0.0
    var vitaminK: Double = 0.0
    var calcium: Double = 0.0
    var iron: Double = 0.0
    var magnesium: Double = 0.0
    var phosphorus: Double = 0.0
    var potassium: Double = 0.0
    var sodium: Double = 0.0
    var zinc: Double = 0.0
    var copper: Double = 0.0
    var manganese: Double = 0.0
    var selenium: Double = 0.0
    var iodine: Double = 0.0

    enum CodingKeys: String, CodingKey {
        case calories, protein, fat, carbs, fiber
        case saturatedFat = "saturated_fat"
        case monounsaturatedFat = "monounsaturated_fat"
        case polyunsaturatedFat = "polyunsaturated_fat"
        case cholesterol
        case vitaminA = "vitamin_a"
        case vitaminB1 = "vitamin_b1"
        case vitaminB2 = "vitamin_b2"
        case vitaminB3 = "vitamin_b3"
        case vitaminB5 = "vitamin_b5"
        case vitaminB6 = "vitamin_b6"
        case vitaminB7 = "vitamin_b7"
        case vitaminB9 = "vitamin_b9"
        case vitaminB12 = "vitamin_b12"
        case vitaminC = "vitamin_c"
        case vitaminD = "vitamin_d"
        case vitaminE = "vitamin_e"
        case vitaminK = "vitamin_k"
        case calcium, iron, magnesium, phosphorus, potassium, sodium, zinc, copper, manganese, selenium, iodine
    }

    static func + (lhs: NutrientData, rhs: NutrientData) -> NutrientData {
        NutrientData(
            calories: lhs.calories + rhs.calories,
            protein: lhs.protein + rhs.protein,
            fat: lhs.fat + rhs.fat,
            saturatedFat: lhs.saturatedFat + rhs.saturatedFat,
            monounsaturatedFat: lhs.monounsaturatedFat + rhs.monounsaturatedFat,
            polyunsaturatedFat: lhs.polyunsaturatedFat + rhs.polyunsaturatedFat,
            cholesterol: lhs.cholesterol + rhs.cholesterol,
            carbs: lhs.carbs + rhs.carbs,
            fiber: lhs.fiber + rhs.fiber,
            vitaminA: lhs.vitaminA + rhs.vitaminA,
            vitaminB1: lhs.vitaminB1 + rhs.vitaminB1,
            vitaminB2: lhs.vitaminB2 + rhs.vitaminB2,
            vitaminB3: lhs.vitaminB3 + rhs.vitaminB3,
            vitaminB5: lhs.vitaminB5 + rhs.vitaminB5,
            vitaminB6: lhs.vitaminB6 + rhs.vitaminB6,
            vitaminB7: lhs.vitaminB7 + rhs.vitaminB7,
            vitaminB9: lhs.vitaminB9 + rhs.vitaminB9,
            vitaminB12: lhs.vitaminB12 + rhs.vitaminB12,
            vitaminC: lhs.vitaminC + rhs.vitaminC,
            vitaminD: lhs.vitaminD + rhs.vitaminD,
            vitaminE: lhs.vitaminE + rhs.vitaminE,
            vitaminK: lhs.vitaminK + rhs.vitaminK,
            calcium: lhs.calcium + rhs.calcium,
            iron: lhs.iron + rhs.iron,
            magnesium: lhs.magnesium + rhs.magnesium,
            phosphorus: lhs.phosphorus + rhs.phosphorus,
            potassium: lhs.potassium + rhs.potassium,
            sodium: lhs.sodium + rhs.sodium,
            zinc: lhs.zinc + rhs.zinc,
            copper: lhs.copper + rhs.copper,
            manganese: lhs.manganese + rhs.manganese,
            selenium: lhs.selenium + rhs.selenium,
            iodine: lhs.iodine + rhs.iodine
        )
    }

    static func * (lhs: NutrientData, factor: Double) -> NutrientData {
        NutrientData(
            calories: lhs.calories * factor,
            protein: lhs.protein * factor,
            fat: lhs.fat * factor,
            saturatedFat: lhs.saturatedFat * factor,
            monounsaturatedFat: lhs.monounsaturatedFat * factor,
            polyunsaturatedFat: lhs.polyunsaturatedFat * factor,
            cholesterol: lhs.cholesterol * factor,
            carbs: lhs.carbs * factor,
            fiber: lhs.fiber * factor,
            vitaminA: lhs.vitaminA * factor,
            vitaminB1: lhs.vitaminB1 * factor,
            vitaminB2: lhs.vitaminB2 * factor,
            vitaminB3: lhs.vitaminB3 * factor,
            vitaminB5: lhs.vitaminB5 * factor,
            vitaminB6: lhs.vitaminB6 * factor,
            vitaminB7: lhs.vitaminB7 * factor,
            vitaminB9: lhs.vitaminB9 * factor,
            vitaminB12: lhs.vitaminB12 * factor,
            vitaminC: lhs.vitaminC * factor,
            vitaminD: lhs.vitaminD * factor,
            vitaminE: lhs.vitaminE * factor,
            vitaminK: lhs.vitaminK * factor,
            calcium: lhs.calcium * factor,
            iron: lhs.iron * factor,
            magnesium: lhs.magnesium * factor,
            phosphorus: lhs.phosphorus * factor,
            potassium: lhs.potassium * factor,
            sodium: lhs.sodium * factor,
            zinc: lhs.zinc * factor,
            copper: lhs.copper * factor,
            manganese: lhs.manganese * factor,
            selenium: lhs.selenium * factor,
            iodine: lhs.iodine * factor
        )
    }

    func macrosList() -> [(key: String, name: String, value: Double)] {
        [
            ("calories", String(localized: "Калории (ккал)"), calories),
            ("protein", String(localized: "Белки (г)"), protein),
            ("fat", String(localized: "Жиры (г)"), fat),
            ("carbs", String(localized: "Углеводы (г)"), carbs),
            ("fiber", String(localized: "Клетчатка (г)"), fiber)
        ]
    }

    func fatDetailsList() -> [(key: String, name: String, value: Double)] {
        [
            ("saturatedFat", String(localized: "Насыщенные жиры (г)"), saturatedFat),
            ("monounsaturatedFat", String(localized: "Мононенасыщенные жиры (г)"), monounsaturatedFat),
            ("polyunsaturatedFat", String(localized: "Полиненасыщенные жиры (г)"), polyunsaturatedFat),
            ("cholesterol", String(localized: "Холестерин (мг)"), cholesterol)
        ]
    }

    func vitaminsList() -> [(key: String, name: String, value: Double)] {
        [
            ("vitaminA", String(localized: "Витамин A (мкг)"), vitaminA),
            ("vitaminB1", String(localized: "Витамин B1 (мг)"), vitaminB1),
            ("vitaminB2", String(localized: "Витамин B2 (мг)"), vitaminB2),
            ("vitaminB3", String(localized: "Витамин B3 (мг)"), vitaminB3),
            ("vitaminB5", String(localized: "Витамин B5 (мг)"), vitaminB5),
            ("vitaminB6", String(localized: "Витамин B6 (мг)"), vitaminB6),
            ("vitaminB7", String(localized: "Витамин B7 (мкг)"), vitaminB7),
            ("vitaminB9", String(localized: "Витамин B9 (мкг)"), vitaminB9),
            ("vitaminB12", String(localized: "Витамин B12 (мкг)"), vitaminB12),
            ("vitaminC", String(localized: "Витамин C (мг)"), vitaminC),
            ("vitaminD", String(localized: "Витамин D (мкг)"), vitaminD),
            ("vitaminE", String(localized: "Витамин E (мг)"), vitaminE),
            ("vitaminK", String(localized: "Витамин K (мкг)"), vitaminK)
        ]
    }

    func mineralsList() -> [(key: String, name: String, value: Double)] {
        [
            ("calcium", String(localized: "Кальций (мг)"), calcium),
            ("iron", String(localized: "Железо (мг)"), iron),
            ("magnesium", String(localized: "Магний (мг)"), magnesium),
            ("phosphorus", String(localized: "Фосфор (мг)"), phosphorus),
            ("potassium", String(localized: "Калий (мг)"), potassium),
            ("sodium", String(localized: "Натрий (мг)"), sodium),
            ("zinc", String(localized: "Цинк (мг)"), zinc),
            ("copper", String(localized: "Медь (мг)"), copper),
            ("manganese", String(localized: "Марганец (мг)"), manganese),
            ("selenium", String(localized: "Селен (мкг)"), selenium),
            ("iodine", String(localized: "Йод (мкг)"), iodine)
        ]
    }

    func getByKey(_ key: String) -> Double {
        switch key {
        case "calories": return calories
        case "protein": return protein
        case "fat": return fat
        case "saturatedFat": return saturatedFat
        case "monounsaturatedFat": return monounsaturatedFat
        case "polyunsaturatedFat": return polyunsaturatedFat
        case "cholesterol": return cholesterol
        case "carbs": return carbs
        case "fiber": return fiber
        case "vitaminA": return vitaminA
        case "vitaminB1": return vitaminB1
        case "vitaminB2": return vitaminB2
        case "vitaminB3": return vitaminB3
        case "vitaminB5": return vitaminB5
        case "vitaminB6": return vitaminB6
        case "vitaminB7": return vitaminB7
        case "vitaminB9": return vitaminB9
        case "vitaminB12": return vitaminB12
        case "vitaminC": return vitaminC
        case "vitaminD": return vitaminD
        case "vitaminE": return vitaminE
        case "vitaminK": return vitaminK
        case "calcium": return calcium
        case "iron": return iron
        case "magnesium": return magnesium
        case "phosphorus": return phosphorus
        case "potassium": return potassium
        case "sodium": return sodium
        case "zinc": return zinc
        case "copper": return copper
        case "manganese": return manganese
        case "selenium": return selenium
        case "iodine": return iodine
        default: return 0.0
        }
    }

    mutating func setByKey(_ key: String, _ value: Double) {
        switch key {
        case "calories": calories = value
        case "protein": protein = value
        case "fat": fat = value
        case "saturatedFat": saturatedFat = value
        case "monounsaturatedFat": monounsaturatedFat = value
        case "polyunsaturatedFat": polyunsaturatedFat = value
        case "cholesterol": cholesterol = value
        case "carbs": carbs = value
        case "fiber": fiber = value
        case "vitaminA": vitaminA = value
        case "vitaminB1": vitaminB1 = value
        case "vitaminB2": vitaminB2 = value
        case "vitaminB3": vitaminB3 = value
        case "vitaminB5": vitaminB5 = value
        case "vitaminB6": vitaminB6 = value
        case "vitaminB7": vitaminB7 = value
        case "vitaminB9": vitaminB9 = value
        case "vitaminB12": vitaminB12 = value
        case "vitaminC": vitaminC = value
        case "vitaminD": vitaminD = value
        case "vitaminE": vitaminE = value
        case "vitaminK": vitaminK = value
        case "calcium": calcium = value
        case "iron": iron = value
        case "magnesium": magnesium = value
        case "phosphorus": phosphorus = value
        case "potassium": potassium = value
        case "sodium": sodium = value
        case "zinc": zinc = value
        case "copper": copper = value
        case "manganese": manganese = value
        case "selenium": selenium = value
        case "iodine": iodine = value
        default: break
        }
    }

    func allNutrientsList() -> [(key: String, displayName: String, value: Double)] {
        [
            ("calories", String(localized: "Калории (ккал)"), calories),
            ("protein", String(localized: "Белки (г)"), protein),
            ("fat", String(localized: "Жиры (г)"), fat),
            ("saturatedFat", String(localized: "Насыщенные жиры (г)"), saturatedFat),
            ("monounsaturatedFat", String(localized: "Мононенасыщенные жиры (г)"), monounsaturatedFat),
            ("polyunsaturatedFat", String(localized: "Полиненасыщенные жиры (г)"), polyunsaturatedFat),
            ("cholesterol", String(localized: "Холестерин (мг)"), cholesterol),
            ("carbs", String(localized: "Углеводы (г)"), carbs),
            ("fiber", String(localized: "Клетчатка (г)"), fiber),
            ("vitaminA", String(localized: "Витамин A (мкг)"), vitaminA),
            ("vitaminB1", String(localized: "Витамин B1 (мг)"), vitaminB1),
            ("vitaminB2", String(localized: "Витамин B2 (мг)"), vitaminB2),
            ("vitaminB3", String(localized: "Витамин B3 (мг)"), vitaminB3),
            ("vitaminB5", String(localized: "Витамин B5 (мг)"), vitaminB5),
            ("vitaminB6", String(localized: "Витамин B6 (мг)"), vitaminB6),
            ("vitaminB7", String(localized: "Витамин B7 (мкг)"), vitaminB7),
            ("vitaminB9", String(localized: "Витамин B9 (мкг)"), vitaminB9),
            ("vitaminB12", String(localized: "Витамин B12 (мкг)"), vitaminB12),
            ("vitaminC", String(localized: "Витамин C (мг)"), vitaminC),
            ("vitaminD", String(localized: "Витамин D (мкг)"), vitaminD),
            ("vitaminE", String(localized: "Витамин E (мг)"), vitaminE),
            ("vitaminK", String(localized: "Витамин K (мкг)"), vitaminK),
            ("calcium", String(localized: "Кальций (мг)"), calcium),
            ("iron", String(localized: "Железо (мг)"), iron),
            ("magnesium", String(localized: "Магний (мг)"), magnesium),
            ("phosphorus", String(localized: "Фосфор (мг)"), phosphorus),
            ("potassium", String(localized: "Калий (мг)"), potassium),
            ("sodium", String(localized: "Натрий (мг)"), sodium),
            ("zinc", String(localized: "Цинк (мг)"), zinc),
            ("copper", String(localized: "Медь (мг)"), copper),
            ("manganese", String(localized: "Марганец (мг)"), manganese),
            ("selenium", String(localized: "Селен (мкг)"), selenium),
            ("iodine", String(localized: "Йод (мкг)"), iodine)
        ]
    }
}
