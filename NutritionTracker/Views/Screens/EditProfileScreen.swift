import SwiftUI

struct EditProfileScreen: View {
    @ObservedObject var viewModel: MainViewModel
    @EnvironmentObject var auth: AuthManager
    @StateObject private var sync = SyncManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @State private var isSyncing = false

    var body: some View {
        VStack(spacing: 0) {
            BrandHeader(
                String(localized: "Профиль"),
                leading: {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                    }
                },
                trailing: {
                    HStack(spacing: 16) {
                        // Forced sync (push + pull).
                        Button(action: {
                            guard !isSyncing else { return }
                            Task {
                                isSyncing = true
                                await sync.forceSyncNow()
                                viewModel.loadData()
                                isSyncing = false
                            }
                        }) {
                            if isSyncing {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                        }
                        Button(action: {
                            Task {
                                await auth.signOut()
                                dismiss()
                            }
                        }) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 18, weight: .semibold))
                        }
                    }
                }
            )
            Picker("", selection: $selectedTab) {
                Text("Профиль").tag(0)
                Text("Дневные нормы").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            if selectedTab == 0 {
                ProfileDataTab(viewModel: viewModel, dismiss: dismiss)
            } else {
                DailyNormsTab(viewModel: viewModel)
            }
        }
        .background(AppColor.background)
        .navigationBarHidden(true)
    }
}

// MARK: - Profile Tab

private struct ProfileDataTab: View {
    @ObservedObject var viewModel: MainViewModel
    @EnvironmentObject var auth: AuthManager
    let dismiss: DismissAction
    @State private var gender: Gender = .male
    @State private var age: String = ""
    @State private var weight: String = ""       // kg (metric) or lb (imperial)
    @State private var heightCm: String = ""     // cm, metric mode
    @State private var heightFeet: String = ""   // ft, imperial mode
    @State private var heightInches: String = "" // in, imperial mode
    @State private var goals: String = ""
    @State private var localError: String?
    @State private var unitSystem: UnitSystem = UnitSystem.current
    @State private var showDeleteAccount = false

    private var isImperial: Bool { unitSystem == .imperial }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Язык приложения").font(.headline)
                    LanguagePickerButton()
                }

                VStack(alignment: .leading) {
                    Text("Единицы измерения").font(.headline)
                    Picker("Единицы измерения", selection: $unitSystem) {
                        Text("Метрические (г)").tag(UnitSystem.metric)
                        Text("Имперские (oz)").tag(UnitSystem.imperial)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: unitSystem) { _, newValue in
                        UnitSystem.current = newValue
                        // Reinterpret the currently-entered values into the new unit
                        // so the fields stay consistent when the user toggles.
                        repopulateFieldsForUnitChange(to: newValue)
                    }
                }

                VStack(alignment: .leading) {
                    Text("Пол").font(.headline)
                    HStack(spacing: 20) {
                        Button(action: { gender = .male }) {
                            HStack(spacing: 6) {
                                Image(systemName: gender == .male ? "largecircle.fill.circle" : "circle")
                                    .foregroundColor(gender == .male ? AppColor.primary : .gray)
                                Text("Мужской")
                            }
                        }
                        .buttonStyle(.plain)
                        Button(action: { gender = .female }) {
                            HStack(spacing: 6) {
                                Image(systemName: gender == .female ? "largecircle.fill.circle" : "circle")
                                    .foregroundColor(gender == .female ? AppColor.primary : .gray)
                                Text("Женский")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading) {
                    Text("Возраст").font(.headline)
                    TextField("Возраст", text: $age)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                }

                VStack(alignment: .leading) {
                    Text(isImperial ? "Вес (фунты)" : "Вес (кг)").font(.headline)
                    TextField("Вес", text: $weight)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                }

                VStack(alignment: .leading) {
                    Text(isImperial ? "Рост (футы/дюймы)" : "Рост (см)").font(.headline)
                    if isImperial {
                        HStack {
                            TextField("Футы", text: $heightFeet)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                            TextField("Дюймы", text: $heightInches)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                        }
                    } else {
                        TextField("Рост", text: $heightCm)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                    }
                }

                VStack(alignment: .leading) {
                    Text("Цели и уровень активности").font(.headline)
                    TextEditor(text: $goals)
                        .frame(minHeight: 100)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColor.outlineVariant))
                }

                if viewModel.isLoading {
                    ProgressView("Пересчитываем нормы...")
                }

                if let error = localError ?? viewModel.errorMessage {
                    Text(error).foregroundColor(.red).font(.caption)
                }

                Button(action: submit) {
                    Text("Сохранить и пересчитать")
                        .font(.headline)
                        .foregroundColor(AppColor.onPrimary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppColor.primary)
                        .cornerRadius(12)
                }
                .disabled(viewModel.isLoading)

                // Account deletion (Apple requirement). Irreversible.
                Button(role: .destructive, action: { showDeleteAccount = true }) {
                    Text("Удалить аккаунт")
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .padding(.top, 8)
            }
            .padding()
        }
        .alert("Удалить аккаунт?", isPresented: $showDeleteAccount) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) {
                Task {
                    await auth.deleteAccount()
                    dismiss()
                }
            }
        } message: {
            Text("Аккаунт и все ваши данные будут удалены безвозвратно. Это действие нельзя отменить.")
        }
        .onAppear {
            if let profile = viewModel.userProfile {
                gender = Gender.from(stored: profile.gender)
                age = String(profile.age)
                goals = profile.goalsText
                fillBodyFields(weightKg: profile.weightKg, heightCm: profile.heightCm, unit: unitSystem)
            }
        }
    }

    /// Populate the weight/height text fields from canonical kg/cm in the given unit.
    private func fillBodyFields(weightKg: Double, heightCm cm: Double, unit: UnitSystem) {
        if unit == .imperial {
            weight = String(Int(BodyUnits.kgToPounds(weightKg).rounded()))
            let (ft, inch) = BodyUnits.cmToFeetInches(cm)
            heightFeet = String(ft)
            heightInches = String(inch)
        } else {
            weight = String(Int(weightKg.rounded()))
            heightCm = String(Int(cm.rounded()))
        }
    }

    /// When the user flips the unit toggle, convert whatever is currently entered
    /// into the new unit so the displayed values keep the same real measurement.
    private func repopulateFieldsForUnitChange(to newUnit: UnitSystem) {
        // Interpret current fields in the OLD unit -> canonical kg/cm.
        let oldUnit: UnitSystem = (newUnit == .imperial) ? .metric : .imperial
        let (kg, cm) = currentBodyInCanonical(assuming: oldUnit)
        guard let kg, let cm else { return }  // leave as-is if input incomplete
        fillBodyFields(weightKg: kg, heightCm: cm, unit: newUnit)
    }

    /// Read the current text fields, interpreting them in `unit`, returning kg/cm.
    private func currentBodyInCanonical(assuming unit: UnitSystem) -> (Double?, Double?) {
        let w = Double(weight.replacingOccurrences(of: ",", with: "."))
        if unit == .imperial {
            let ft = Double(heightFeet.replacingOccurrences(of: ",", with: "."))
            let inch = Double(heightInches.isEmpty ? "0" : heightInches.replacingOccurrences(of: ",", with: "."))
            let kg = w.map { BodyUnits.poundsToKg($0) }
            let cm = (ft != nil) ? BodyUnits.feetInchesToCm(feet: ft!, inches: inch ?? 0) : nil
            return (kg, cm)
        } else {
            let cm = Double(heightCm.replacingOccurrences(of: ",", with: "."))
            return (w, cm)
        }
    }

    private func submit() {
        guard let a = Int(age) else {
            localError = String(localized: "Введите корректные возраст, вес и рост")
            return
        }
        let (weightKg, heightCmValue) = currentBodyInCanonical(assuming: unitSystem)
        guard let weightKg, let heightCmValue else {
            localError = String(localized: "Введите корректные возраст, вес и рост")
            return
        }
        if goals.trimmingCharacters(in: .whitespaces).isEmpty {
            localError = String(localized: "Опишите ваши цели")
            return
        }
        localError = nil
        viewModel.updateProfile(gender: gender.rawValue, age: a, weight: weightKg, height: heightCmValue, goals: goals) {
            dismiss()
        }
    }
}

// MARK: - Daily Norms Tab

private struct DailyNormsTab: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var editMode = false
    @State private var editedValues: [String: String] = [:]

    // Grouping matches the Android app exactly (slices over allNutrientsList):
    //   Macros & Calories   — first 5
    //   Vitamins            — next 13
    //   Minerals & trace…   — the rest
    private var macroKeys: [(key: String, displayName: String, value: Double)] {
        let all = viewModel.dailyNorms?.allNutrientsList() ?? []
        return Array(all.prefix(5))
    }

    private var vitaminKeys: [(key: String, displayName: String, value: Double)] {
        let all = viewModel.dailyNorms?.allNutrientsList() ?? []
        return Array(all.dropFirst(5).prefix(13))
    }

    private var mineralKeys: [(key: String, displayName: String, value: Double)] {
        let all = viewModel.dailyNorms?.allNutrientsList() ?? []
        return Array(all.dropFirst(18))
    }

    var body: some View {
        if viewModel.dailyNorms == nil {
            VStack {
                Spacer()
                Text("Нормы ещё не рассчитаны")
                    .foregroundColor(.secondary)
                Text("Заполните профиль и нажмите\n\"Сохранить и пересчитать\"")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                Spacer()
            }
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    // Action buttons
                    HStack {
                        Spacer()
                        if editMode {
                            Button("Отмена") {
                                editMode = false
                                editedValues = [:]
                            }
                            Button("Сохранить") {
                                saveNorms()
                            }
                            .bold()
                        } else {
                            Button("Редактировать") {
                                enterEditMode()
                            }
                        }
                    }

                    normsSection(title: String(localized: "БЖУ и Калории"), items: macroKeys)
                    normsSection(title: String(localized: "Витамины"), items: vitaminKeys)
                    normsSection(title: String(localized: "Минералы и микроэлементы"), items: mineralKeys)
                }
                .padding()
            }
        }
    }

    private func normsSection(title: String, items: [(key: String, displayName: String, value: Double)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ForEach(items, id: \.key) { item in
                HStack {
                    Text(item.displayName)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if editMode {
                        TextField("", text: editBinding(for: item.key))
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                            .frame(width: 80)
                    } else {
                        Text(formatValue(item.value))
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .padding()
        .cardStyle()
    }

    private func editBinding(for key: String) -> Binding<String> {
        Binding(
            get: { editedValues[key] ?? "0" },
            set: { editedValues[key] = $0 }
        )
    }

    private func formatValue(_ value: Double) -> String {
        if value == value.rounded() && value < 10000 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private func enterEditMode() {
        guard let norms = viewModel.dailyNorms else { return }
        editedValues = [:]
        for item in norms.allNutrientsList() {
            editedValues[item.key] = formatValue(item.value)
        }
        editMode = true
    }

    private func saveNorms() {
        guard var norms = viewModel.dailyNorms else { return }
        for (key, valueStr) in editedValues {
            if let val = Double(valueStr) {
                norms.setByKey(key, val)
            }
        }
        viewModel.saveDailyNorms(norms)
        editMode = false
        editedValues = [:]
    }
}
