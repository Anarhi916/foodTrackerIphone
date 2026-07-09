import SwiftUI

struct EditProfileScreen: View {
    @ObservedObject var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
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
        .background(Color(.systemGray6))
        .navigationTitle("Профиль")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Profile Tab

private struct ProfileDataTab: View {
    @ObservedObject var viewModel: MainViewModel
    let dismiss: DismissAction
    @State private var gender: String = "Мужской"
    @State private var age: String = ""
    @State private var weight: String = ""
    @State private var height: String = ""
    @State private var goals: String = ""
    @State private var localError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Пол").font(.headline)
                    HStack(spacing: 20) {
                        Button(action: { gender = "Мужской" }) {
                            HStack(spacing: 6) {
                                Image(systemName: gender == "Мужской" ? "largecircle.fill.circle" : "circle")
                                    .foregroundColor(gender == "Мужской" ? .blue : .gray)
                                Text("Мужской")
                            }
                        }
                        .buttonStyle(.plain)
                        Button(action: { gender = "Женский" }) {
                            HStack(spacing: 6) {
                                Image(systemName: gender == "Женский" ? "largecircle.fill.circle" : "circle")
                                    .foregroundColor(gender == "Женский" ? .blue : .gray)
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
                    Text("Вес (кг)").font(.headline)
                    TextField("Вес", text: $weight)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                }

                VStack(alignment: .leading) {
                    Text("Рост (см)").font(.headline)
                    TextField("Рост", text: $height)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                }

                VStack(alignment: .leading) {
                    Text("Цели и уровень активности").font(.headline)
                    TextEditor(text: $goals)
                        .frame(minHeight: 100)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
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
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(12)
                }
                .disabled(viewModel.isLoading)
            }
            .padding()
        }
        .onAppear {
            if let profile = viewModel.userProfile {
                gender = profile.gender
                age = String(profile.age)
                weight = String(Int(profile.weightKg))
                height = String(Int(profile.heightCm))
                goals = profile.goalsText
            }
        }
    }

    private func submit() {
        guard let a = Int(age), let w = Double(weight), let h = Double(height) else {
            localError = "Введите корректные возраст, вес и рост"
            return
        }
        if goals.trimmingCharacters(in: .whitespaces).isEmpty {
            localError = "Опишите ваши цели"
            return
        }
        localError = nil
        viewModel.updateProfile(gender: gender, age: a, weight: w, height: h, goals: goals) {
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
    //   БЖУ и Калории       — first 5
    //   Витамины            — next 13
    //   Минералы и микро…   — the rest
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

                    normsSection(title: "БЖУ и Калории", items: macroKeys)
                    normsSection(title: "Витамины", items: vitaminKeys)
                    normsSection(title: "Минералы и микроэлементы", items: mineralKeys)
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
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray5)).shadow(color: .black.opacity(0.08), radius: 3, y: 1))
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
