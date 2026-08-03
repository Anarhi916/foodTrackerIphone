import SwiftUI
import SwiftData
import UIKit

@main
struct NutritionTrackerApp: App {
    @StateObject private var viewModel = MainViewModel()
    @StateObject private var localization = LocalizationManager.shared
    @StateObject private var auth = AuthManager.shared

    // Бренд-зелёный. Насыщенный глубокий зелёный (#1B9E3E), заданный явно в sRGB,
    // чтобы цвет не приглушался цветовым пространством дисплея.
    static let brandGreenUI = UIColor(
        displayP3Red: 0x1B/255.0, green: 0x9E/255.0, blue: 0x3E/255.0, alpha: 1.0
    )
    static let brandGreen = Color(.sRGB, red: 0x1B/255.0, green: 0x9E/255.0, blue: 0x3E/255.0)

    init() {
        // Глобальный вид навбара: зелёный фон + белый заголовок/кнопки на ВСЕХ экранах
        // (как Android TopAppBar). Иначе дочерние экраны наследуют системный белый бар.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = Self.brandGreenUI
        appearance.shadowColor = .clear   // без полупрозрачной разделительной линии
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]

        // Убрать «капсулы»-фон под toolbar-иконками (iOS 26 рисует их по умолчанию).
        let buttonAppearance = UIBarButtonItemAppearance()
        buttonAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.buttonAppearance = buttonAppearance
        appearance.doneButtonAppearance = buttonAppearance
        appearance.backButtonAppearance = buttonAppearance

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = .white   // кнопка «назад» + иконки белые
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(localization)
                .environmentObject(auth)
                .environment(\.locale, localization.locale)
                .tint(Color(Self.brandGreenUI))   // зелёный акцент для controls на всех экранах
                .id(localization.language)   // rebuild the whole tree on language change
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
    @EnvironmentObject var auth: AuthManager
    @StateObject private var sync = SyncManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !auth.isSignedIn {
                LoginScreen()
            } else if viewModel.hasProfile {
                MainScreen(viewModel: viewModel)
            } else {
                OnboardingScreen(viewModel: viewModel)
            }
        }
        .overlay {
            if sync.isInitialSyncing {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                        Text("Загружаем ваши данные...")
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                    .padding(28)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.black.opacity(0.5)))
                }
            }
        }
        // Аккаунт удалён с другого устройства → уведомление, затем экран входа.
        .alert("Аккаунт удалён", isPresented: $auth.accountDeletedNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Ваш аккаунт был удалён. Войдите снова, чтобы продолжить.")
        }
        // Полная загрузка данных при входе (busy indicator), затем перечитываем локальный VM.
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn {
                viewModel.reset()              // чистый старт для нового аккаунта
                Task {
                    await sync.pullOnLogin()
                    viewModel.loadData()
                }
            } else {
                viewModel.reset()              // при разлогине/удалении гасим всё состояние
                sync.resetOnSignOut()
            }
        }
        // Тихая ежедневная синхронизация при выходе приложения в активное состояние.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && auth.isSignedIn {
                Task {
                    await sync.dailySyncIfNeeded()
                    viewModel.loadData()
                }
            }
        }
        // Профиль только что создан в онбординге → сразу заливаем на сервер
        // (иначе он уйдёт только при следующей ежедневной синхронизации).
        .onChange(of: viewModel.hasProfile) { _, has in
            if has && auth.isSignedIn {
                Task { await sync.backgroundSync() }
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
            .sheetChrome()
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
