import SwiftUI

struct OnboardingScreen: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var gender: String = "Мужской"
    @State private var age: String = ""
    @State private var weight: String = ""
    @State private var height: String = ""
    @State private var goals: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Добро пожаловать!")
                    .font(.largeTitle)
                    .bold()

                Text("Заполните профиль для расчёта персональных норм питания")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                // Gender
                VStack(alignment: .leading) {
                    Text("Пол").font(.headline)
                    Picker("Пол", selection: $gender) {
                        Text("Мужской").tag("Мужской")
                        Text("Женский").tag("Женский")
                    }
                    .pickerStyle(.segmented)
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
                    Text("Вес (кг)").font(.headline)
                    TextField("Вес", text: $weight)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                }

                // Height
                VStack(alignment: .leading) {
                    Text("Рост (см)").font(.headline)
                    TextField("Рост", text: $height)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                }

                // Goals
                VStack(alignment: .leading) {
                    Text("Цели и уровень активности").font(.headline)
                    TextEditor(text: $goals)
                        .frame(minHeight: 100)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                }

                if viewModel.isLoading {
                    ProgressView("Рассчитываем нормы...")
                }

                if let error = viewModel.errorMessage {
                    Text(error).foregroundColor(.red).font(.caption)
                }

                Button(action: submit) {
                    Text("Рассчитать нормы")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isValid ? Color.green : Color.gray)
                        .cornerRadius(12)
                }
                .disabled(!isValid || viewModel.isLoading)
            }
            .padding()
        }
    }

    private var isValid: Bool {
        guard let a = Int(age), a > 0,
              let w = Double(weight), w > 0,
              let h = Double(height), h > 0,
              !goals.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return true
    }

    private func submit() {
        guard let a = Int(age), let w = Double(weight), let h = Double(height) else { return }
        viewModel.updateProfile(gender: gender, age: a, weight: w, height: h, goals: goals) {
            // Profile saved, app will navigate to main
        }
    }
}
