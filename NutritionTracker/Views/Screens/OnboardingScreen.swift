import SwiftUI

struct OnboardingScreen: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var gender: Gender = .male
    @State private var age: String = ""
    @State private var weight: String = ""       // kg (metric) or lb (imperial)
    @State private var heightCm: String = ""     // cm, used in metric mode
    @State private var heightFeet: String = ""   // ft, imperial mode
    @State private var heightInches: String = "" // in, imperial mode
    @State private var goals: String = ""
    @State private var localError: String?
    @State private var unitSystem: UnitSystem = UnitSystem.current

    private var isImperial: Bool { unitSystem == .imperial }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Language — top of onboarding so users can switch before filling in data.
                HStack {
                    Spacer()
                    LanguagePickerButton()
                }

                Text("Настройка профиля")
                    .font(.largeTitle)
                    .bold()

                Text("Заполните данные для расчёта дневной нормы питания")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                // Gender
                VStack(alignment: .leading) {
                    Text("Пол").font(.headline)
                    Picker("Пол", selection: $gender) {
                        Text("Мужской").tag(Gender.male)
                        Text("Женский").tag(Gender.female)
                    }
                    .pickerStyle(.segmented)
                }

                // Units
                VStack(alignment: .leading) {
                    Text("Единицы измерения").font(.headline)
                    Picker("Единицы измерения", selection: $unitSystem) {
                        Text("Метрические (г)").tag(UnitSystem.metric)
                        Text("Имперские (oz)").tag(UnitSystem.imperial)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: unitSystem) { _, newValue in
                        UnitSystem.current = newValue
                    }
                }

                // Age
                VStack(alignment: .leading) {
                    Text("Возраст").font(.headline)
                    TextField("Возраст", text: $age)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                }

                // Weight
                VStack(alignment: .leading) {
                    Text(isImperial ? "Вес (фунты)" : "Вес (кг)").font(.headline)
                    TextField("Вес", text: $weight)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                }

                // Height
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

                // Goals
                VStack(alignment: .leading) {
                    Text("Цели и уровень активности").font(.headline)
                    TextEditor(text: $goals)
                        .frame(minHeight: 100)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColor.outlineVariant))
                }

                if viewModel.isLoading {
                    ProgressView("Рассчитываем нормы...")
                }

                if let error = localError ?? viewModel.errorMessage {
                    Text(error).foregroundColor(.red).font(.caption)
                }

                Button(action: submit) {
                    Text("Рассчитать нормы питания")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppColor.primary)
                        .cornerRadius(12)
                }
                .disabled(viewModel.isLoading)
            }
            .padding()
        }
    }

    private func submit() {
        // Parse weight/height honoring the selected unit system, converting to
        // the canonical kg / cm the profile stores.
        guard let a = Int(age),
              let rawWeight = Double(weight.replacingOccurrences(of: ",", with: ".")) else {
            localError = L("Введите корректные возраст, вес и рост")
            return
        }
        let weightKg: Double
        let heightCmValue: Double
        if isImperial {
            guard let ft = Double(heightFeet.replacingOccurrences(of: ",", with: ".")),
                  let inch = Double(heightInches.isEmpty ? "0" : heightInches.replacingOccurrences(of: ",", with: ".")) else {
                localError = L("Введите корректные возраст, вес и рост")
                return
            }
            weightKg = BodyUnits.poundsToKg(rawWeight)
            heightCmValue = BodyUnits.feetInchesToCm(feet: ft, inches: inch)
        } else {
            guard let h = Double(heightCm.replacingOccurrences(of: ",", with: ".")) else {
                localError = L("Введите корректные возраст, вес и рост")
                return
            }
            weightKg = rawWeight
            heightCmValue = h
        }
        if goals.trimmingCharacters(in: .whitespaces).isEmpty {
            localError = L("Опишите ваши цели")
            return
        }
        localError = nil
        viewModel.updateProfile(gender: gender.rawValue, age: a, weight: weightKg, height: heightCmValue, goals: goals) {
            // Profile saved, app will navigate to main
        }
    }
}
