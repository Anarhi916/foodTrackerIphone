import SwiftUI

struct HistoryScreen: View {
    @ObservedObject var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var expandedDates: Set<String> = []
    @State private var editingDates: Set<String> = []
    @State private var editedWeights: [String: [FoodEntry: String]] = [:]
    @State private var allDates: [String] = []
    @State private var showAddFoodSheet = false
    @State private var addFoodTargetDate = ""

    var body: some View {
        VStack(spacing: 0) {
            BrandHeader(
                L("История"),
                leading: {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                    }
                }
            )
            ScrollView {
                VStack(spacing: 12) {
                    if allDates.isEmpty {
                        Text("Нет данных")
                            .foregroundColor(.secondary)
                            .padding(.top, 40)
                    } else {
                        ForEach(allDates, id: \.self) { date in
                            dayCard(for: date)
                        }
                    }
                }
                .padding()
            }
            .background(AppColor.background)
        }
        .navigationBarHidden(true)
        .onAppear { allDates = NutritionRepository.shared.getAllDates() }
        .sheet(isPresented: $showAddFoodSheet) {
            AddFoodToDateView(date: addFoodTargetDate, viewModel: viewModel) {
                showAddFoodSheet = false
            }
        }
    }

    private func dayCard(for date: String) -> some View {
        let isExpanded = expandedDates.contains(date)
        let isEditing = editingDates.contains(date)
        let entries = viewModel.getEntriesForDate(date)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: {
                    withAnimation {
                        if expandedDates.contains(date) {
                            expandedDates.remove(date)
                            editingDates.remove(date)
                            editedWeights.removeValue(forKey: date)
                        } else {
                            expandedDates.insert(date)
                        }
                    }
                }) {
                    HStack {
                        Text(formatDate(date))
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                }
                if isExpanded {
                    if isEditing {
                        Button("Отмена") {
                            editedWeights.removeValue(forKey: date)
                            editingDates.remove(date)
                        }
                        .font(.subheadline)
                        Button("Сохранить") {
                            saveWeights(for: date, entries: entries)
                        }
                        .font(.subheadline)
                        .bold()
                    } else {
                        Button(action: {
                            editedWeights[date] = Dictionary(uniqueKeysWithValues: entries.map {
                                ($0, String(Int($0.weightGrams)))
                            })
                            editingDates.insert(date)
                        }) {
                            Image(systemName: "pencil")
                                .font(.title2)
                                .foregroundColor(AppColor.primary)
                        }
                    }
                }
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.secondary)
                    .onTapGesture {
                        withAnimation {
                            if expandedDates.contains(date) {
                                expandedDates.remove(date)
                                editingDates.remove(date)
                                editedWeights.removeValue(forKey: date)
                            } else {
                                expandedDates.insert(date)
                            }
                        }
                    }
            }

            if isExpanded {
                if entries.isEmpty {
                    Text("Нет записей")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if isEditing {
                        Button(action: {
                            addFoodTargetDate = date
                            showAddFoodSheet = true
                        }) {
                            Label("Добавить", systemImage: "plus")
                                .font(.subheadline)
                        }
                    }
                } else {
                    let totals = entries.reduce(NutrientData()) { acc, entry in
                        acc + viewModel.parseNutrients(entry.nutrientsJson)
                    }

                    HStack(spacing: 8) {
                        summaryChip(L("Ккал"), value: String(format: "%.0f", totals.calories))
                        summaryChip(L("Б"), value: String(format: "%.1f %@", totals.protein, L("г")))
                        summaryChip(L("Ж"), value: String(format: "%.1f %@", totals.fat, L("г")))
                        summaryChip(L("У"), value: String(format: "%.1f %@", totals.carbs, L("г")))
                    }

                    if isEditing {
                        Button(action: {
                            addFoodTargetDate = date
                            showAddFoodSheet = true
                        }) {
                            Label("Добавить", systemImage: "plus")
                                .font(.subheadline)
                        }
                        .padding(.bottom, 4)
                    }

                    // Column header
                    HStack(spacing: 4) {
                        Text("Продукт").font(.caption2).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        Text("Вес").font(.caption2).foregroundColor(.secondary).frame(width: 52, alignment: .trailing)
                        Text("Ккал").font(.caption2).foregroundColor(.secondary).frame(width: 52, alignment: .trailing)
                        if isEditing { Spacer().frame(width: 28) }
                    }

                    ForEach(entries, id: \.self) { entry in
                        let nutrients = viewModel.parseNutrients(entry.nutrientsJson)
                        HStack(spacing: 4) {
                            Text(entry.foodName)
                                .font(.caption)
                                .lineLimit(isEditing ? 1 : 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if isEditing {
                                TextField("г", text: Binding(
                                    get: { editedWeights[date]?[entry] ?? String(Int(entry.weightGrams)) },
                                    set: { editedWeights[date]?[entry] = $0 }
                                ))
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 52)
                                .font(.caption2)
                                Button(action: { viewModel.deleteEntry(entry) }) {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                .frame(width: 28, height: 28)
                            } else {
                                Text(WeightFormat.short(grams: entry.weightGrams))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 52, alignment: .trailing)
                                Text("\(Int(nutrients.calories))")
                                    .font(.caption2)
                                    .frame(width: 52, alignment: .trailing)
                            }
                        }
                    }

                    if let norms = viewModel.dailyNorms {
                        Divider()
                        let bars: [(name: String, value: Double, target: Double, unit: String, upperRatio: Double, showBar: Bool)] = [
                            (L("Калории"), totals.calories, norms.calories, L("ккал"), 1.5, true),
                            (L("Белки"), totals.protein, norms.protein, L("г"), 1.5, true),
                            (L("Жиры"), totals.fat, norms.fat, L("г"), 1.5, true),
                            (L("Углеводы"), totals.carbs, norms.carbs, L("г"), 1.5, true),
                            (L("Клетчатка"), totals.fiber, norms.fiber, L("г"), 1.5, true),
                            (L("Насыщ. жиры"), totals.saturatedFat, norms.saturatedFat, L("г"), 1.0, true),
                            (L("Мононенасыщ."), totals.monounsaturatedFat, norms.monounsaturatedFat, L("г"), 3.0, true),
                            (L("Полиненасыщ."), totals.polyunsaturatedFat, norms.polyunsaturatedFat, L("г"), 3.0, true),
                            // Cholesterol: keep fact/target numbers, hide the (perpetually red) bar
                            (L("Холестерин"), totals.cholesterol, norms.cholesterol, L("мг"), 1.3, false)
                        ]
                        ForEach(bars, id: \.name) { bar in
                            historyProgressBar(name: bar.name, value: bar.value, target: bar.target, unit: bar.unit, upperRatio: bar.upperRatio, showBar: bar.showBar)
                        }
                    }
                }
            }
        }
        .padding()
        .cardStyle()
    }

    private func saveWeights(for date: String, entries: [FoodEntry]) {
        if let weights = editedWeights[date] {
            let changes = Dictionary(uniqueKeysWithValues:
                weights.compactMap { (entry, str) -> (FoodEntry, Double)? in
                    guard let d = Double(str.replacingOccurrences(of: ",", with: ".")), d > 0 else { return nil }
                    return (entry, d)
                }
            )
            if !changes.isEmpty { viewModel.updateMultipleWeights(changes) }
        }
        editedWeights.removeValue(forKey: date)
        editingDates.remove(date)
    }

    private func summaryChip(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.caption).bold()
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(AppColor.surfaceVariant))
    }

    private func historyProgressBar(name: String, value: Double, target: Double, unit: String, upperRatio: Double, showBar: Bool = true) -> some View {
        let pct = target > 0 ? value / target : 0
        let color: Color = {
            if pct > upperRatio * 1.3 { return AppColor.progressRed }
            if pct > upperRatio { return AppColor.progressOrange }
            if pct >= 0.8 { return AppColor.progressGreen }
            if pct >= 0.4 { return AppColor.progressYellow }
            return AppColor.progressRed
        }()
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name).font(.caption2)
                Spacer()
                Text(String(format: "%.1f / %.1f %@ (%d%%)", value, target, unit, Int(pct * 100)))
                    .font(.caption2)
            }
            if showBar {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(AppColor.surfaceVariant).frame(height: 7)
                        RoundedRectangle(cornerRadius: 3).fill(color)
                            .frame(width: min(CGFloat(pct) * geo.size.width, geo.size.width), height: 7)
                    }
                }
                .frame(height: 7)
            }
        }
    }

    private func formatDate(_ dateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateStr) else { return dateStr }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return L("Сегодня") }
        if calendar.isDateInYesterday(date) { return L("Вчера") }

        let display = DateFormatter()
        display.locale = .current
        display.setLocalizedDateFormatFromTemplate("ddMMyyyy")
        return display.string(from: date)
    }
}

private struct AddFoodToDateView: View {
    let date: String
    let viewModel: MainViewModel
    let onDismiss: () -> Void

    @State private var foodName = ""
    @State private var weight = ""
    @State private var cachedFood: FoodCache? = nil
    @State private var isLoading = false
    @State private var error: String? = nil

    private var suggestions: [FoodCache] {
        guard foodName.count >= 2, cachedFood == nil else { return [] }
        let q = foodName.lowercased()
        return viewModel.cachedFoods
            .filter { $0.keyOriginal.lowercased().contains(q) || $0.keyEn.lowercased().contains(q) }
            .prefix(4)
            .map { $0 }
    }

    private var weightOk: Bool {
        (Double(weight.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Продукт", text: $foodName)
                        .onChange(of: foodName) { _ in cachedFood = nil }
                    if !suggestions.isEmpty {
                        ForEach(suggestions, id: \.keyOriginal) { item in
                            Button(action: {
                                foodName = item.keyOriginal
                                cachedFood = item
                            }) {
                                Text(item.keyOriginal)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    TextField("Вес (г)", text: $weight)
                        .keyboardType(.decimalPad)
                }
                if isLoading {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.8)
                            Text("Анализируем…").font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                }
                if let err = error {
                    Section {
                        Text(err).font(.subheadline).foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Добавить продукт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { if !isLoading { onDismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        guard let w = Double(weight.replacingOccurrences(of: ",", with: ".")) else { return }
                        isLoading = true
                        error = nil
                        viewModel.addFoodForDate(
                            name: foodName.trimmingCharacters(in: .whitespaces),
                            weightGrams: w,
                            date: date,
                            cachedFood: cachedFood,
                            onSuccess: { onDismiss() },
                            onError: { msg in isLoading = false; error = msg }
                        )
                    }
                    .disabled(foodName.trimmingCharacters(in: .whitespaces).isEmpty || !weightOk || isLoading)
                }
            }
            .sheetChrome()
        }
        .presentationBackground(Color(.systemBackground))
        .presentationDetents([.medium])
    }
}
