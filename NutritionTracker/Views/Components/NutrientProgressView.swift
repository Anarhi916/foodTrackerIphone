import SwiftUI

struct IdentifiableNutrient: Identifiable {
    let key: String
    let name: String
    var id: String { key }
}

/// Per-nutrient upper-limit ratios (as a fraction of the daily target) used to color
/// the progress bars. Matches the Android app: strict limits for nutrients that are
/// harmful in excess (calories, saturated fat, sodium, fat-soluble vitamins A/D, toxic
/// minerals), lenient for water-soluble vitamins and beneficial fats.
enum NutrientLimits {
    private static let ratios: [String: Double] = [
        // Macros
        "calories": 1.15, "protein": 1.8, "fat": 1.3, "carbs": 1.3, "fiber": 3.0,
        // Fat details
        "saturatedFat": 1.0, "monounsaturatedFat": 3.0, "polyunsaturatedFat": 3.0, "cholesterol": 1.3,
        // Vitamins
        "vitaminA": 1.3, "vitaminB1": 2.0, "vitaminB2": 2.0, "vitaminB3": 2.0, "vitaminB5": 2.0,
        "vitaminB6": 2.0, "vitaminB7": 2.0, "vitaminB9": 2.0, "vitaminB12": 2.0,
        "vitaminC": 2.5, "vitaminD": 1.3, "vitaminE": 1.5, "vitaminK": 1.5,
        // Minerals
        "calcium": 1.5, "iron": 1.3, "magnesium": 1.5, "phosphorus": 1.5, "potassium": 1.5,
        "sodium": 1.2, "zinc": 1.5, "copper": 1.3, "manganese": 1.5, "selenium": 1.3, "iodine": 1.3
    ]

    static func upperRatio(for key: String) -> Double {
        ratios[key] ?? 1.5
    }
}

struct NutrientProgressSection: View {
    let title: String
    let nutrients: [(key: String, name: String, value: Double)]
    let norms: [(key: String, name: String, value: Double)]
    let entries: [FoodEntry]
    let parseNutrients: (String) -> NutrientData
    var expandedByDefault: Bool = true

    @State private var isExpanded: Bool?
    @State private var breakdownNutrient: IdentifiableNutrient?
    @State private var topFoodsNutrient: IdentifiableNutrient?

    private var expanded: Bool {
        isExpanded ?? expandedByDefault
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation { isExpanded = !expanded } }) {
                HStack {
                    Text(title).font(AppFont.sectionHeader).foregroundColor(.primary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(zip(nutrients, norms)), id: \.0.key) { (nutrient, norm) in
                        NutrientProgressBar(
                            key: nutrient.key,
                            name: nutrient.name,
                            value: nutrient.value,
                            target: norm.value,
                            hasTopFoods: NutrientTopFoods.data[nutrient.key] != nil,
                            showBar: nutrient.key != "cholesterol",
                            onTap: {
                                breakdownNutrient = IdentifiableNutrient(key: nutrient.key, name: nutrient.name)
                            },
                            onInfoTap: {
                                topFoodsNutrient = IdentifiableNutrient(key: nutrient.key, name: nutrient.name)
                            }
                        )
                    }
                }
                .padding(.top, 6)   // small gap between the section header and the progress rows
            }
        }
        .padding()
        .cardStyle()
        .sheet(item: $breakdownNutrient) { item in
            NutrientBreakdownSheet(
                nutrientKey: item.key,
                nutrientName: item.name,
                entries: entries,
                parseNutrients: parseNutrients
            )
        }
        .sheet(item: $topFoodsNutrient) { item in
            NutrientTopFoodsSheet(
                nutrientKey: item.key,
                nutrientName: item.name
            )
        }
    }
}

struct NutrientProgressBar: View {
    let key: String
    let name: String
    let value: Double
    let target: Double
    let hasTopFoods: Bool
    var upperRatio: Double? = nil
    /// Cholesterol hides the colored bar: dietary cholesterol correlates weakly with blood
    /// cholesterol, so a permanently "over limit" bar is alarmist — we keep the fact/target
    /// numbers but drop the scary progress fill.
    var showBar: Bool = true
    let onTap: () -> Void
    let onInfoTap: () -> Void

    private var effectiveUpperRatio: Double {
        upperRatio ?? NutrientLimits.upperRatio(for: key)
    }

    private var percentage: Double {
        guard target > 0 else { return 0 }
        return value / target
    }

    private var progressColor: Color {
        let ratio = percentage
        if ratio > effectiveUpperRatio * 1.3 { return AppColor.progressRed }
        if ratio > effectiveUpperRatio { return AppColor.progressOrange }
        if ratio >= 0.8 { return AppColor.progressGreen }
        if ratio >= 0.4 { return AppColor.progressYellow }
        return AppColor.progressRed
    }

    private var displayPercentage: String {
        "\(Int(percentage * 100))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if hasTopFoods {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundColor(AppColor.primary.opacity(0.6))
                        .onTapGesture { onInfoTap() }
                }
                Text(name).font(AppFont.caption).lineLimit(1)
                Spacer()
                Text(String(format: "%.1f / %.1f", value, target))
                    .font(AppFont.captionBold)
                Text("(\(displayPercentage))")
                    .font(AppFont.captionBold)
            }
            if showBar {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppColor.surfaceVariant)
                            .frame(height: 9)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(progressColor)
                            .frame(width: min(CGFloat(percentage) * geometry.size.width, geometry.size.width), height: 9)
                    }
                }
                .frame(height: 9)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Breakdown Sheet

struct NutrientBreakdownSheet: View {
    let nutrientKey: String
    let nutrientName: String
    let entries: [FoodEntry]
    let parseNutrients: (String) -> NutrientData
    @Environment(\.dismiss) private var dismiss

    private var breakdown: [(name: String, weight: Double, value: Double)] {
        entries.compactMap { entry in
            let nutrients = parseNutrients(entry.nutrientsJson)
            let val = nutrients.getByKey(nutrientKey)
            guard val > 0 else { return nil }
            return (entry.foodName, entry.weightGrams, val)
        }
        .sorted { $0.value > $1.value }
    }

    private var total: Double {
        breakdown.reduce(0) { $0 + $1.value }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if breakdown.isEmpty {
                    Spacer()
                    Text("Нет данных")
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    HStack {
                        Text("Продукт").font(.subheadline).bold().frame(maxWidth: .infinity, alignment: .leading)
                        Text("Кол-во").font(.subheadline).bold().frame(width: 70, alignment: .trailing)
                        Text("%").font(.subheadline).bold().frame(width: 45, alignment: .trailing)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(AppColor.surfaceContainerHigh)

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(breakdown.enumerated()), id: \.offset) { _, item in
                                HStack {
                                    Text("\(item.name) (\(WeightFormat.short(grams: item.weight)))")
                                        .font(.callout)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(String(format: "%.2f", item.value))
                                        .font(.callout)
                                        .frame(width: 70, alignment: .trailing)
                                    let pct = total > 0 ? Int(item.value / total * 100) : 0
                                    Text("\(pct)%")
                                        .font(.callout)
                                        .bold()
                                        .frame(width: 45, alignment: .trailing)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                Divider()
                            }

                            HStack {
                                Text("Итого")
                                    .font(.subheadline).bold()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(String(format: "%.2f", total))
                                    .font(.subheadline).bold()
                                    .frame(width: 70, alignment: .trailing)
                                Text("100%")
                                    .font(.subheadline).bold()
                                    .frame(width: 45, alignment: .trailing)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                            .background(AppColor.surfaceContainerHigh)
                        }
                    }
                }
            }
            .background(AppColor.background)
            .navigationTitle(nutrientName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .sheetChrome()
        }
        .presentationDetents([.medium])
        .presentationBackground(.thickMaterial)
    }
}

// MARK: - Top Foods Sheet

struct NutrientTopFoodsSheet: View {
    let nutrientKey: String
    let nutrientName: String
    @Environment(\.dismiss) private var dismiss

    private var info: NutrientTopFoods.NutrientInfo? {
        NutrientTopFoods.data[nutrientKey]
    }

    private var sortedFoods: [NutrientTopFoods.FoodSource] {
        (info?.foods ?? []).sorted { $0.per100g > $1.per100g }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let info, !sortedFoods.isEmpty {
                    Text("Содержание на 100 г продукта (% от дневной нормы)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(sortedFoods.enumerated()), id: \.offset) { index, item in
                                let pct = info.dailyValue > 0 ? Int(item.per100g / info.dailyValue * 100) : 0
                                HStack {
                                    Text("\(index + 1). \(NutrientTopFoods.localizedName(item.name))")
                                        .font(.body)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(formatFoodValue(item.per100g)) \(NutrientTopFoods.localizedUnit(info.unit)) \(String(format: L("(%lld%% дн.)"), pct))")
                                        .font(.callout)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 10)
                                Divider()
                            }
                        }
                    }
                } else {
                    Spacer()
                    Text("Нет данных").foregroundColor(.secondary)
                    Spacer()
                }
            }
            .background(AppColor.background)
            .navigationTitle("Топ-15: \(nutrientName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .sheetChrome()
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.thickMaterial)
    }

    private func formatFoodValue(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}
