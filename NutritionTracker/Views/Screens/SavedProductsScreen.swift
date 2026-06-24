import SwiftUI

struct SavedProductsScreen: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var searchQuery = ""
    @State private var showDeleteAllAlert = false
    @State private var showAddTypeDialog = false
    @State private var showAddManualDialog = false
    @State private var showAddDishDialog = false
    @State private var editingEntry: FoodCache?
    @State private var quickAddEntry: FoodCache?
    @State private var quickAddWeight = "100"
    @State private var deleteEntry: FoodCache?

    private var filteredFoods: [FoodCache] {
        if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            return viewModel.cachedFoods
        }
        let q = searchQuery.lowercased()
        return viewModel.cachedFoods.filter {
            $0.keyOriginal.lowercased().contains(q) || $0.keyEn.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Поиск...", text: $searchQuery)
                    .textFieldStyle(.plain)
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray5)))
            .padding(.horizontal)
            .padding(.top, 8)

            // Counter
            Text("\(filteredFoods.count) из \(viewModel.cachedFoods.count) продуктов")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)

            if viewModel.cachedFoods.isEmpty {
                Spacer()
                Text("Кеш пуст")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Продукты сохраняются автоматически\nпри первом добавлении")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredFoods, id: \.keyNormalized) { entry in
                            cachedFoodRow(entry)
                        }
                    }
                    .padding()
                }
            }
        }
        .background(Color(.systemGray6))
        .navigationTitle("Сохранённые продукты")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button { showAddTypeDialog = true } label: {
                        Image(systemName: "plus")
                    }
                    if !viewModel.cachedFoods.isEmpty {
                        Button { showDeleteAllAlert = true } label: {
                            Image(systemName: "trash").foregroundColor(.red)
                        }
                    }
                }
            }
        }
        .alert("Удалить все продукты?", isPresented: $showDeleteAllAlert) {
            Button("Удалить всё", role: .destructive) { viewModel.deleteAllCachedFoods() }
            Button("Отмена", role: .cancel) {}
        }
        .alert("Удалить?", isPresented: Binding(
            get: { deleteEntry != nil },
            set: { if !$0 { deleteEntry = nil } }
        )) {
            Button("Удалить", role: .destructive) {
                if let e = deleteEntry { viewModel.deleteCachedFood(e) }
                deleteEntry = nil
            }
            Button("Отмена", role: .cancel) { deleteEntry = nil }
        } message: {
            if let e = deleteEntry {
                Text("Удалить «\(e.keyOriginal)» из кеша?")
            }
        }
        .alert("Добавить в приём пищи", isPresented: Binding(
            get: { quickAddEntry != nil },
            set: { if !$0 { quickAddEntry = nil } }
        )) {
            TextField("Вес (г)", text: $quickAddWeight)
                .keyboardType(.numberPad)
            Button("Добавить") {
                if let entry = quickAddEntry, let w = Double(quickAddWeight), w > 0 {
                    viewModel.addCachedFoodToToday(entry, weight: w)
                    quickAddEntry = nil
                    quickAddWeight = "100"
                }
            }
            Button("Отмена", role: .cancel) { quickAddEntry = nil }
        } message: {
            if let entry = quickAddEntry {
                Text(entry.keyOriginal)
            }
        }
        .confirmationDialog("Что добавить?", isPresented: $showAddTypeDialog, titleVisibility: .visible) {
            Button("Продукт") { showAddManualDialog = true }
            Button("Блюдо из ингредиентов") { showAddDishDialog = true }
            Button("Отмена", role: .cancel) {}
        }
        .sheet(isPresented: $showAddManualDialog) {
            AddCachedFoodSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showAddDishDialog) {
            AddCustomDishSheet(viewModel: viewModel)
        }
        .sheet(item: $editingEntry) { entry in
            EditCachedFoodSheet(viewModel: viewModel, entry: entry)
        }
        .onAppear { viewModel.cachedFoods = NutritionRepository.shared.getAllCachedFoods() }
    }

    private func cachedFoodRow(_ entry: FoodCache) -> some View {
        let nutrients = viewModel.parseNutrients(entry.nutrientsPer100gJson)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.keyOriginal)
                    .font(.subheadline)
                    .lineLimit(2)
                Text(entry.keyEn)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text(String(format: "%.0f ккал • Б%.1f Ж%.1f У%.1f /100г", nutrients.calories, nutrients.protein, nutrients.fat, nutrients.carbs))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { quickAddWeight = "100"; quickAddEntry = entry } label: {
                Image(systemName: "plus.circle.fill").font(.title3).foregroundColor(.blue)
            }
            .buttonStyle(.plain)

            Button { editingEntry = entry } label: {
                Image(systemName: "pencil.circle.fill").font(.title3).foregroundColor(.orange)
            }
            .buttonStyle(.plain)

            Button { deleteEntry = entry } label: {
                Image(systemName: "xmark.circle.fill").font(.title3).foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray5)))
    }
}

// MARK: - Identifiable for FoodCache sheet
extension FoodCache: Identifiable {
    public var id: String { keyNormalized }
}

// MARK: - Add New Cached Food

struct AddCachedFoodSheet: View {
    @ObservedObject var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var nameRu = ""
    @State private var nameEn = ""
    @State private var nutrientValues: [String: String] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    TextField("Название *", text: $nameRu)
                        .textFieldStyle(.roundedBorder)
                    TextField("English name *", text: $nameEn)
                        .textFieldStyle(.roundedBorder)

                    Text("Нутриенты на 100г").font(.headline).padding(.top, 8)

                    ForEach(NutrientData().allNutrientsList(), id: \.key) { item in
                        HStack {
                            Text(item.displayName).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                            TextField("0", text: nutrientBinding(for: item.key))
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.decimalPad)
                                .frame(width: 80)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Новый продукт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .disabled(nameRu.trimmingCharacters(in: .whitespaces).isEmpty || nameEn.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func nutrientBinding(for key: String) -> Binding<String> {
        Binding(
            get: { nutrientValues[key] ?? "0" },
            set: { nutrientValues[key] = $0 }
        )
    }

    private func save() {
        var nutrients = NutrientData()
        for (key, valStr) in nutrientValues {
            let cleaned = valStr.replacingOccurrences(of: ",", with: ".")
            if let val = Double(cleaned) {
                nutrients.setByKey(key, val)
            }
        }
        viewModel.addManualCachedFood(nameRu: nameRu.trimmingCharacters(in: .whitespaces), nameEn: nameEn.trimmingCharacters(in: .whitespaces), nutrients: nutrients)
        dismiss()
    }
}

// MARK: - Edit Cached Food

struct EditCachedFoodSheet: View {
    @ObservedObject var viewModel: MainViewModel
    let entry: FoodCache
    @Environment(\.dismiss) private var dismiss
    @State private var nameRu = ""
    @State private var nameEn = ""
    @State private var nutrientValues: [String: String] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    TextField("Название", text: $nameRu)
                        .textFieldStyle(.roundedBorder)
                    TextField("English name", text: $nameEn)
                        .textFieldStyle(.roundedBorder)

                    Text("Нутриенты на 100г").font(.headline).padding(.top, 8)

                    ForEach(NutrientData().allNutrientsList(), id: \.key) { item in
                        HStack {
                            Text(item.displayName).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                            TextField("0", text: nutrientBinding(for: item.key))
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.decimalPad)
                                .frame(width: 80)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .disabled(nameRu.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            nameRu = entry.keyOriginal
            nameEn = entry.keyEn
            let nutrients = viewModel.parseNutrients(entry.nutrientsPer100gJson)
            for item in nutrients.allNutrientsList() {
                nutrientValues[item.key] = formatValue(item.value)
            }
        }
    }

    private func nutrientBinding(for key: String) -> Binding<String> {
        Binding(
            get: { nutrientValues[key] ?? "0" },
            set: { nutrientValues[key] = $0 }
        )
    }

    private func formatValue(_ value: Double) -> String {
        if value == 0 { return "0" }
        let s = String(format: "%.4f", value)
        // Strip trailing zeros
        var result = s
        while result.hasSuffix("0") { result.removeLast() }
        if result.hasSuffix(".") { result.removeLast() }
        return result
    }

    private func save() {
        var nutrients = NutrientData()
        for (key, valStr) in nutrientValues {
            let cleaned = valStr.replacingOccurrences(of: ",", with: ".")
            if let val = Double(cleaned) {
                nutrients.setByKey(key, val)
            }
        }
        viewModel.updateCachedFoodFull(entry, nameRu: nameRu.trimmingCharacters(in: .whitespaces), nameEn: nameEn.trimmingCharacters(in: .whitespaces), nutrients: nutrients)
        dismiss()
    }
}

// MARK: - Add Custom Dish (from ingredients)

/// Локальная модель строки ингредиента в форме создания блюда.
private struct IngredientInput: Identifiable {
    let id = UUID()
    var name: String = ""
    var weight: String = ""
}

/// Форма создания пользовательского блюда из ингредиентов.
/// Каждый ингредиент анализируется через `analyzeFoodText`, нутриенты суммируются,
/// нормализуются к 100г и сохраняются в кеш как обычная запись.
struct AddCustomDishSheet: View {
    @ObservedObject var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var dishName = ""
    @State private var ingredients: [IngredientInput] = [IngredientInput()]
    @State private var isProcessing = false
    @State private var errorMessage: String?

    private var canSave: Bool {
        guard !dishName.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        let valid = ingredients.filter { ing in
            !ing.name.trimmingCharacters(in: .whitespaces).isEmpty
                && (Double(ing.weight.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0
        }
        return !valid.isEmpty && !isProcessing
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Название блюда").font(.caption).foregroundColor(.secondary)
                        TextField("Например, мой коктейль", text: $dishName, axis: .vertical)
                            .lineLimit(1...3)
                            .textFieldStyle(.roundedBorder)

                        Text("Ингредиенты").font(.caption).foregroundColor(.secondary).padding(.top, 4)

                        ForEach($ingredients) { $ing in
                            ingredientRow($ing)
                        }

                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.top, 8)
                        }

                        Text("Нутриенты будут рассчитаны автоматически по составу.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                    .padding()
                }
                .disabled(isProcessing)

                if isProcessing {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView("Анализ ингредиентов...")
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
                        .shadow(radius: 4)
                }
            }
            .navigationTitle("Новое блюдо")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .disabled(isProcessing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") { saveDish() }
                        .disabled(!canSave)
                }
            }
        }
    }

    @ViewBuilder
    private func ingredientRow(_ ing: Binding<IngredientInput>) -> some View {
        let isLast = ingredients.last?.id == ing.wrappedValue.id
        HStack(spacing: 8) {
            TextField("Ингредиент", text: ing.name)
                .textFieldStyle(.roundedBorder)
            TextField("г", text: ing.weight)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
                .frame(width: 70)
            if isLast {
                Button { addIngredient() } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
            } else {
                Button { removeIngredient(ing.wrappedValue.id) } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func addIngredient() {
        ingredients.append(IngredientInput())
    }

    private func removeIngredient(_ id: UUID) {
        ingredients.removeAll { $0.id == id }
        if ingredients.isEmpty { ingredients.append(IngredientInput()) }
    }

    private func saveDish() {
        let trimmedName = dishName.trimmingCharacters(in: .whitespaces)
        let valid: [(name: String, weight: Double)] = ingredients.compactMap { ing in
            let n = ing.name.trimmingCharacters(in: .whitespaces)
            let w = Double(ing.weight.replacingOccurrences(of: ",", with: "."))
            guard !n.isEmpty, let weight = w, weight > 0 else { return nil }
            return (n, weight)
        }
        guard !trimmedName.isEmpty, !valid.isEmpty else { return }

        isProcessing = true
        errorMessage = nil
        Task {
            do {
                try await viewModel.createCustomDish(name: trimmedName, ingredients: valid)
                await MainActor.run {
                    isProcessing = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
