import SwiftUI

struct IdentifiableNutrient: Identifiable {
    let key: String
    let name: String
    var id: String { key }
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
                    Text(title).font(.headline).foregroundColor(.primary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }

            if expanded {
                ForEach(Array(zip(nutrients, norms)), id: \.0.key) { (nutrient, norm) in
                    NutrientProgressBar(
                        key: nutrient.key,
                        name: nutrient.name,
                        value: nutrient.value,
                        target: norm.value,
                        hasTopFoods: NutrientTopFoods.data[nutrient.key] != nil,
                        onTap: {
                            breakdownNutrient = IdentifiableNutrient(key: nutrient.key, name: nutrient.name)
                        },
                        onInfoTap: {
                            topFoodsNutrient = IdentifiableNutrient(key: nutrient.key, name: nutrient.name)
                        }
                    )
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray5)).shadow(color: .black.opacity(0.08), radius: 3, y: 1))
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
    var upperRatio: Double = 1.5
    let onTap: () -> Void
    let onInfoTap: () -> Void

    private var percentage: Double {
        guard target > 0 else { return 0 }
        return value / target
    }

    private var progressColor: Color {
        let ratio = percentage
        if ratio > upperRatio * 1.3 { return .red }
        if ratio > upperRatio { return .orange }
        if ratio >= 0.8 { return .green }
        if ratio >= 0.4 { return .yellow }
        return .red
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
                        .foregroundColor(.blue.opacity(0.6))
                        .onTapGesture { onInfoTap() }
                }
                Text(name).font(.caption).lineLimit(1)
                Spacer()
                Text(String(format: "%.1f / %.1f", value, target))
                    .font(.caption)
                Text("(\(displayPercentage))")
                    .font(.caption)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressColor)
                        .frame(width: min(CGFloat(percentage) * geometry.size.width, geometry.size.width), height: 8)
                }
            }
            .frame(height: 8)
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
                    .background(Color(.systemGray5))

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(breakdown.enumerated()), id: \.offset) { _, item in
                                HStack {
                                    Text("\(item.name) (\(Int(item.weight))г)")
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
                            .background(Color(.systemGray5))
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(nutrientName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
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

    private var foods: [(food: String, valuePer100g: String)] {
        NutrientTopFoods.data[nutrientKey] ?? []
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if foods.isEmpty {
                    Spacer()
                    Text("Нет данных").foregroundColor(.secondary)
                    Spacer()
                } else {
                    Text("Содержание на 100 г продукта")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(foods.enumerated()), id: \.offset) { index, item in
                                HStack {
                                    Text("\(index + 1). \(item.food)")
                                        .font(.body)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(item.valuePer100g)
                                        .font(.callout)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 10)
                                Divider()
                            }
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Топ: \(nutrientName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(.thickMaterial)
    }
}
