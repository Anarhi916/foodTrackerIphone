import SwiftUI

struct MainScreen: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var showMenu = false
    @State private var editMode = false
    @State private var editedWeights: [FoodEntry: String] = [:]
    @State private var entryToDelete: FoodEntry?
    @State private var macroBreakdown: IdentifiableNutrient?
    @State private var macroTopFoods: IdentifiableNutrient?
    @State private var quickAddEntry: FoodCache?
    @State private var quickAddWeight: String = "100"
    @FocusState private var foodInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom green header (without the iOS 26 system glass capsules).
                BrandHeader(
                    String(localized: "Nutrition Tracker"),
                    leading: {
                        Menu {
                            NavigationLink(destination: EditProfileScreen(viewModel: viewModel)) {
                                Label("Профиль", systemImage: "person.circle")
                            }
                            NavigationLink(destination: SavedProductsScreen(viewModel: viewModel)) {
                                Label("Сохранённые продукты", systemImage: "archivebox")
                            }
                            NavigationLink(destination: HistoryScreen(viewModel: viewModel)) {
                                Label("История", systemImage: "clock")
                            }
                            NavigationLink(destination: StatisticsScreen(viewModel: viewModel)) {
                                Label("Статистика", systemImage: "chart.bar")
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 20))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                    },
                    trailing: {
                        NavigationLink(destination: HistoryScreen(viewModel: viewModel)) {
                            Image(systemName: "clock.arrow.circlepath").font(.system(size: 20))
                        }
                    }
                )
                ScrollView {
                    VStack(spacing: 12) {
                        // Food input
                        foodInputSection

                        // Error message
                        if let error = viewModel.errorMessage {
                            HStack {
                                Text(error)
                                    .foregroundColor(.red)
                                    .font(.caption)
                                Spacer()
                                Button("✕") { viewModel.clearError() }
                            }
                            .padding(.horizontal)
                        }

                        // Today's entries
                        foodEntriesTable

                        // Progress sections
                        if viewModel.dailyNorms != nil {
                            macrosSection
                            vitaminsSection
                            mineralsSection
                            fatDetailsSection
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.immediately)
                .background(AppColor.background)
            }
            .navigationBarHidden(true)
            .overlay {
                if viewModel.isLoading {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Анализируем…").font(AppFont.subheadline)
                        }
                        .padding(24)
                        .background(RoundedRectangle(cornerRadius: 12).fill(AppColor.surface))
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.showConfirmDialog) {
            confirmFoodSheet
        }
        .sheet(isPresented: $viewModel.showEditDialog) {
            editWeightSheet
        }
        .sheet(isPresented: $viewModel.showBarcodeWeightDialog) {
            barcodeWeightSheet
        }
        .sheet(isPresented: $viewModel.showPhotoEditDialog) {
            photoEditSheet
        }
        .alert("Добавить в приём пищи", isPresented: Binding(
            get: { quickAddEntry != nil },
            set: { if !$0 { quickAddEntry = nil } }
        )) {
            TextField("Вес (г)", text: $quickAddWeight)
                .keyboardType(.numberPad)
            Button("Добавить") {
                if let entry = quickAddEntry, let w = Double(quickAddWeight), w > 0 {
                    viewModel.quickAddFromCache(entry, weight: w)
                    quickAddEntry = nil
                    quickAddWeight = "100"
                }
            }
            Button("Отмена", role: .cancel) {
                quickAddEntry = nil
            }
        } message: {
            if let entry = quickAddEntry {
                let nutrients = viewModel.parseNutrients(entry.nutrientsPer100gJson)
                let w = Double(quickAddWeight) ?? 100
                let factor = w / 100.0
                Text("\(entry.keyOriginal)\n\(String(format: String(localized: "%.0f ккал • Б%.1f Ж%.1f У%.1f"), nutrients.calories * factor, nutrients.protein * factor, nutrients.fat * factor, nutrients.carbs * factor))")
            }
        }
    }

    // MARK: - Food Input

    private var suggestions: [FoodCache] {
        let input = viewModel.foodInput.lowercased()
        guard input.count >= 2, foodInputFocused else { return [] }
        let query = WeightParser.parse(input).name.trimmingCharacters(in: .whitespaces)
        return rankFoodSuggestions(
            query: query.isEmpty ? input : query,
            items: viewModel.cachedFoods,
            keyOriginal: { $0.keyOriginal },
            keyEn: { $0.keyEn }
        )
    }

    private var foodInputSection: some View {
        VStack(spacing: 8) {
            // Multiline input field (2-3 lines), like on Android.
            TextField("Что вы съели?", text: $viewModel.foodInput, axis: .vertical)
                .font(AppFont.body)
                .lineLimit(2...3)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppColor.surface)
                )
                .overlay(
                    // Border like Android's OutlinedTextField: gray when unfocused, green (thicker) when focused.
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            foodInputFocused ? AppColor.primary : AppColor.outline,
                            lineWidth: foodInputFocused ? 2 : 1
                        )
                )
                .animation(.easeInOut(duration: 0.15), value: foodInputFocused)
                .focused($foodInputFocused)

            // Suggestions from cache
            if !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(suggestions, id: \.keyNormalized) { entry in
                        let nutrients = viewModel.parseNutrients(entry.nutrientsPer100gJson)
                        Button {
                            quickAddWeight = "100"
                            quickAddEntry = entry
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.keyOriginal)
                                        .font(AppFont.subheadline)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Text(String(format: String(localized: "%.0f ккал • Б%.1f Ж%.1f У%.1f /100г"), nutrients.calories, nutrients.protein, nutrients.fat, nutrients.carbs))
                                        .font(AppFont.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(AppColor.primary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        if entry.keyNormalized != suggestions.last?.keyNormalized {
                            Divider().padding(.horizontal, 12)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 12).fill(AppColor.surfaceContainerHigh))
            }

            // Wide "Add" button at the bottom, like on Android.
            // disabled -> gray (Material filled Button), active -> rich green.
            let addDisabled = viewModel.foodInput.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isLoading
            Button(action: { foodInputFocused = false; viewModel.analyzeFood() }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("Добавить")
                }
                .font(AppFont.calloutBold)
                .foregroundColor(addDisabled ? AppColor.onDisabled : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 24).fill(addDisabled ? AppColor.disabledContainer : AppColor.primary))
            }
            .disabled(addDisabled)
            .padding(.vertical, 5)

            // 3 equal outlined icon buttons: Barcode / Photo (order as on Android).
            HStack(spacing: 8) {
                NavigationLink(destination: BarcodeScannerScreen(viewModel: viewModel, mode: .food)) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 20))
                        .foregroundColor(AppColor.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .overlay(RoundedRectangle(cornerRadius: 24).stroke(AppColor.primary.opacity(0.5), lineWidth: 1))
                }
                NavigationLink(destination: PhotoCaptureScreen(viewModel: viewModel)) {
                    Image(systemName: "camera")
                        .font(.system(size: 20))
                        .foregroundColor(AppColor.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .overlay(RoundedRectangle(cornerRadius: 24).stroke(AppColor.primary.opacity(0.5), lineWidth: 1))
                }
            }
        }
        .padding(12)
        .cardStyle()
    }

    // MARK: - Food Table

    private var foodEntriesTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            // "Today" title in a large font ABOVE the card (like Android headlineMedium).
            Text("Сегодня")
                .font(AppFont.cardTitle)

            // Edit button on the right, below the title (like Android).
            HStack {
                Spacer()
                if !viewModel.todayEntries.isEmpty {
                    if editMode {
                        Button("Отмена") {
                            editMode = false
                            editedWeights = [:]
                        }
                        .font(AppFont.subheadline)
                        Button("Сохранить") {
                            saveEditedWeights()
                        }
                        .font(AppFont.subheadlineBold)
                    } else {
                        Button {
                            editMode = true
                            editedWeights = [:]
                            for entry in viewModel.todayEntries {
                                editedWeights[entry] = String(Int(entry.weightGrams))
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "pencil")
                                Text("Редактировать")
                            }
                            .font(AppFont.subheadline)
                        }
                    }
                }
            }

            if viewModel.todayEntries.isEmpty {
                Text("Пока нет записей")
                    .font(AppFont.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .cardStyle()
            } else {
                // Separated pills like Android: no outer container card — the header, each
                // entry row and the totals row are individual 16-radius cards on the screen
                // background with small gaps between them.
                VStack(alignment: .leading, spacing: 6) {
                // Header — green primaryContainer bar (like Android).
                HStack {
                    if editMode {
                        Spacer().frame(width: 24)
                    }
                    Text("Продукт").font(AppFont.captionBold).frame(maxWidth: .infinity, alignment: .leading)
                    Text("Вес").font(AppFont.captionBold).frame(width: 50)
                    Text("Ккал").font(AppFont.captionBold).frame(width: 50)
                    Text("Б").font(AppFont.captionBold).frame(width: 36)
                    Text("Ж").font(AppFont.captionBold).frame(width: 36)
                    Text("У").font(AppFont.captionBold).frame(width: 36)
                }
                .foregroundColor(AppColor.onPrimaryContainer)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous).fill(AppColor.primaryContainer))

                ForEach(viewModel.todayEntries, id: \.self) { entry in
                    let nutrients = viewModel.parseNutrients(entry.nutrientsJson)
                    HStack {
                        if editMode {
                            Button {
                                entryToDelete = entry
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.system(size: 16))
                            }
                            .frame(width: 24)
                        }
                        HStack(spacing: 4) {
                            Text(entry.foodName).font(AppFont.caption).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if editMode {
                            TextField("", text: weightBinding(for: entry))
                                .font(AppFont.caption)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 50)
                        } else {
                            Text("\(Int(entry.weightGrams))г").font(AppFont.caption).lineLimit(1).minimumScaleFactor(0.8).frame(width: 50)
                        }
                        Text("\(Int(nutrients.calories))").font(AppFont.caption).lineLimit(1).minimumScaleFactor(0.8).frame(width: 50)
                        Text(String(format: "%.1f", nutrients.protein)).font(AppFont.caption).lineLimit(1).minimumScaleFactor(0.8).frame(width: 36)
                        Text(String(format: "%.1f", nutrients.fat)).font(AppFont.caption).lineLimit(1).minimumScaleFactor(0.8).frame(width: 36)
                        Text(String(format: "%.1f", nutrients.carbs)).font(AppFont.caption).lineLimit(1).minimumScaleFactor(0.8).frame(width: 36)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous).fill(AppColor.surfaceContainerHighest))
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Изменить вес") { viewModel.showEditWeight(for: entry) }
                        Button("Удалить", role: .destructive) { viewModel.deleteEntry(entry) }
                    }
                }

                // Totals — green secondaryContainer bar (like Android).
                HStack {
                    if editMode {
                        Spacer().frame(width: 24)
                    }
                    Text("Итого").font(AppFont.captionBold).frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(Int(viewModel.todayEntries.reduce(0) { $0 + Int($1.weightGrams) }))г").font(AppFont.captionBold).lineLimit(1).minimumScaleFactor(0.8).frame(width: 50)
                    Text("\(Int(viewModel.todayTotals.calories))").font(AppFont.captionBold).lineLimit(1).minimumScaleFactor(0.8).frame(width: 50)
                    Text(String(format: "%.1f", viewModel.todayTotals.protein)).font(AppFont.captionBold).lineLimit(1).minimumScaleFactor(0.8).frame(width: 36)
                    Text(String(format: "%.1f", viewModel.todayTotals.fat)).font(AppFont.captionBold).lineLimit(1).minimumScaleFactor(0.8).frame(width: 36)
                    Text(String(format: "%.1f", viewModel.todayTotals.carbs)).font(AppFont.captionBold).lineLimit(1).minimumScaleFactor(0.8).frame(width: 36)
                }
                .foregroundColor(AppColor.onSecondaryContainer)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous).fill(AppColor.secondaryContainer))
                } // VStack(spacing: 6) — separated pills
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .alert("Удалить?", isPresented: Binding(
            get: { entryToDelete != nil },
            set: { if !$0 { entryToDelete = nil } }
        )) {
            Button("Отмена", role: .cancel) { entryToDelete = nil }
            Button("Удалить", role: .destructive) {
                if let entry = entryToDelete {
                    viewModel.deleteEntry(entry)
                    editedWeights.removeValue(forKey: entry)
                    entryToDelete = nil
                    if viewModel.todayEntries.isEmpty { editMode = false }
                }
            }
        } message: {
            if let entry = entryToDelete {
                Text("Удалить \(entry.foodName) из дневника?")
            }
        }
    }

    private func weightBinding(for entry: FoodEntry) -> Binding<String> {
        Binding(
            get: { editedWeights[entry] ?? String(Int(entry.weightGrams)) },
            set: { editedWeights[entry] = $0 }
        )
    }

    private func saveEditedWeights() {
        var changes: [FoodEntry: Double] = [:]
        for (entry, weightStr) in editedWeights {
            if let newWeight = Double(weightStr), newWeight != entry.weightGrams {
                changes[entry] = newWeight
            }
        }
        if !changes.isEmpty {
            viewModel.updateMultipleWeights(changes)
        }
        editMode = false
        editedWeights = [:]
    }

    // MARK: - Progress Sections

    private var macrosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title in a large font ABOVE the card (like Android headlineMedium).
            Text("БЖУ и Калории")
                .font(AppFont.cardTitle)
            let nutrients = viewModel.todayTotals.macrosList()
            let norms = viewModel.dailyNorms?.macrosList() ?? []
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(zip(nutrients, norms)), id: \.0.key) { (nutrient, norm) in
                    NutrientProgressBar(
                        key: nutrient.key,
                        name: nutrient.name,
                        value: nutrient.value,
                        target: norm.value,
                        hasTopFoods: NutrientTopFoods.data[nutrient.key] != nil,
                        onTap: {
                            macroBreakdown = IdentifiableNutrient(key: nutrient.key, name: nutrient.name)
                        },
                        onInfoTap: {
                            macroTopFoods = IdentifiableNutrient(key: nutrient.key, name: nutrient.name)
                        }
                    )
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .sheet(item: $macroBreakdown) { item in
            NutrientBreakdownSheet(
                nutrientKey: item.key,
                nutrientName: item.name,
                entries: viewModel.todayEntries,
                parseNutrients: { viewModel.parseNutrients($0) }
            )
        }
        .sheet(item: $macroTopFoods) { item in
            NutrientTopFoodsSheet(
                nutrientKey: item.key,
                nutrientName: item.name
            )
        }
    }

    private var vitaminsSection: some View {
        NutrientProgressSection(
            title: String(localized: "Витамины"),
            nutrients: viewModel.todayTotals.vitaminsList(),
            norms: viewModel.dailyNorms?.vitaminsList() ?? [],
            entries: viewModel.todayEntries,
            parseNutrients: { viewModel.parseNutrients($0) },
            expandedByDefault: false
        )
    }

    private var mineralsSection: some View {
        NutrientProgressSection(
            title: String(localized: "Минералы"),
            nutrients: viewModel.todayTotals.mineralsList(),
            norms: viewModel.dailyNorms?.mineralsList() ?? [],
            entries: viewModel.todayEntries,
            parseNutrients: { viewModel.parseNutrients($0) },
            expandedByDefault: false
        )
    }

    private var fatDetailsSection: some View {
        NutrientProgressSection(
            title: String(localized: "Жиры (детализация)"),
            nutrients: viewModel.todayTotals.fatDetailsList(),
            norms: viewModel.dailyNorms?.fatDetailsList() ?? [],
            entries: viewModel.todayEntries,
            parseNutrients: { viewModel.parseNutrients($0) },
            expandedByDefault: false
        )
    }

    // MARK: - Sheets

    private var confirmFoodSheet: some View {
        NavigationStack {
            if let food = viewModel.pendingFood {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(food.foodName).font(.headline)
                        HStack {
                            Text("Вес (г):")
                            TextField("", value: $viewModel.pendingFoodWeight, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.decimalPad)
                                .frame(width: 80)
                        }
                        let nutrients = food.weightGrams > 0 && viewModel.pendingFoodWeight != food.weightGrams
                            ? food.nutrients * (viewModel.pendingFoodWeight / food.weightGrams)
                            : food.nutrients

                        Divider()
                        nutrientRow(String(localized: "Калории"), String(format: String(localized: "%.0f ккал"), nutrients.calories))
                        nutrientRow(String(localized: "Белки"), String(format: String(localized: "%.1f г"), nutrients.protein))
                        nutrientRow(String(localized: "Жиры"), String(format: String(localized: "%.1f г"), nutrients.fat))
                        nutrientRow(String(localized: "Углеводы"), String(format: String(localized: "%.1f г"), nutrients.carbs))
                        nutrientRow(String(localized: "Клетчатка"), String(format: String(localized: "%.1f г"), nutrients.fiber))

                        let fatDetails = nutrients.fatDetailsList().filter { $0.value > 0 }
                        if !fatDetails.isEmpty {
                            Divider()
                            Text("Жиры (детально):").font(.caption).bold()
                            ForEach(fatDetails, id: \.key) { item in
                                nutrientRow(item.name, String(format: "%.2f", item.value))
                            }
                        }

                        let vitamins = nutrients.vitaminsList().filter { $0.value > 0 }
                        if !vitamins.isEmpty {
                            Divider()
                            Text("Витамины:").font(.caption).bold()
                            ForEach(vitamins, id: \.key) { item in
                                nutrientRow(item.name, String(format: "%.2f", item.value))
                            }
                        }

                        let minerals = nutrients.mineralsList().filter { $0.value > 0 }
                        if !minerals.isEmpty {
                            Divider()
                            Text("Минералы:").font(.caption).bold()
                            ForEach(minerals, id: \.key) { item in
                                nutrientRow(item.name, String(format: "%.2f", item.value))
                            }
                        }
                    }
                    .padding()
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { viewModel.dismissConfirmDialog() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Добавить") { viewModel.confirmAddFood() }
                    }
                }
                .sheetChrome()
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func nutrientRow(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline).fontWeight(.medium)
        }
    }

    private var editWeightSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Изменить вес").font(.headline)
                TextField("Вес (г)", text: $viewModel.editWeight)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { viewModel.dismissEditDialog() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { viewModel.confirmEditWeight() }
                }
            }
            .sheetChrome()
        }
        .presentationDetents([.height(200)])
    }

    private var barcodeWeightSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Найден продукт").font(.headline)
                Text(viewModel.barcodeProductName ?? "").font(.subheadline).bold()
                HStack {
                    Text("Вес употреблённого (г):")
                    TextField("", text: $viewModel.barcodeWeight)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .frame(width: 80)
                }
                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { viewModel.dismissBarcodeDialog() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") { viewModel.confirmBarcodeAdd() }
                }
            }
            .sheetChrome()
        }
        .presentationDetents([.height(200)])
    }

    private var photoEditSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Распознано по фото").font(.headline)
                Text("Проверьте и при необходимости отредактируйте:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TextField("Название", text: $viewModel.photoFoodName, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Text("Вес (г):")
                    TextField("", text: $viewModel.photoWeight)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .frame(width: 80)
                }
                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { viewModel.dismissPhotoEditDialog() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Анализировать") { viewModel.confirmPhotoAnalysis() }
                }
            }
            .sheetChrome()
        }
        .presentationDetents([.medium])
    }

}
