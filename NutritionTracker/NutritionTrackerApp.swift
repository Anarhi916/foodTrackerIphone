import SwiftUI
import SwiftData

@main
struct NutritionTrackerApp: App {
    @StateObject private var viewModel = MainViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .modelContainer(DatabaseManager.shared.container)
                .onOpenURL { url in
                    // Deep link path: HTTPS or custom-scheme URL → import shared food.
                    if let food = FoodShare.parseShareLink(url) {
                        viewModel.importedSharedFood = food
                    }
                }
                .sheet(item: $viewModel.importedSharedFood) { food in
                    ImportFoodSheet(food: food, viewModel: viewModel)
                }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var viewModel: MainViewModel

    var body: some View {
        Group {
            if viewModel.hasProfile {
                MainScreen(viewModel: viewModel)
            } else {
                OnboardingScreen(viewModel: viewModel)
            }
        }
    }
}

struct ImportFoodSheet: View {
    let food: SharedFood
    @ObservedObject var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text(food.nameRu)
                        .font(.title2).bold()
                        .multilineTextAlignment(.center)
                    if !food.nameEn.isEmpty {
                        Text(food.nameEn)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 24)

                VStack(spacing: 8) {
                    macroRow("Калории", value: food.nutrients.calories, unit: "ккал")
                    macroRow("Белки", value: food.nutrients.protein, unit: "г")
                    macroRow("Жиры", value: food.nutrients.fat, unit: "г")
                    macroRow("Углеводы", value: food.nutrients.carbs, unit: "г")
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                .padding(.horizontal)

                Text("Будет добавлен в сохранённые продукты")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }
            .navigationTitle("Добавить продукт?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        NutritionRepository.shared.addManualCachedFood(
                            nameRu: food.nameRu,
                            nameEn: food.nameEn.isEmpty ? food.nameRu : food.nameEn,
                            nutrients: food.nutrients
                        )
                        viewModel.cachedFoods = NutritionRepository.shared.getAllCachedFoods()
                        dismiss()
                    }
                }
            }
        }
    }

    private func macroRow(_ label: String, value: Double, unit: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(String(format: "%.1f %@", value, unit)).bold()
        }
    }
}

extension SharedFood: Identifiable {
    var id: String { nameRu + nameEn }
}
