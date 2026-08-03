import SwiftUI
import SwiftData
import UIKit

@main
struct NutritionTrackerApp: App {
    @StateObject private var viewModel = MainViewModel()
    @StateObject private var localization = LocalizationManager.shared
    @StateObject private var auth = AuthManager.shared

    // Brand green. A rich, deep green (#1B9E3E) specified explicitly in sRGB
    // so the color isn't muted by the display's color space.
    static let brandGreenUI = UIColor(
        displayP3Red: 0x1B/255.0, green: 0x9E/255.0, blue: 0x3E/255.0, alpha: 1.0
    )
    static let brandGreen = Color(.sRGB, red: 0x1B/255.0, green: 0x9E/255.0, blue: 0x3E/255.0)

    init() {
        // Global nav bar look: green background + white title/buttons on ALL screens
        // (like Android's TopAppBar). Otherwise child screens inherit the system white bar.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = Self.brandGreenUI
        appearance.shadowColor = .clear   // no translucent separator line
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]

        // Remove the "capsule" background under toolbar icons (iOS 26 draws them by default).
        let buttonAppearance = UIBarButtonItemAppearance()
        buttonAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.buttonAppearance = buttonAppearance
        appearance.doneButtonAppearance = buttonAppearance
        appearance.backButtonAppearance = buttonAppearance

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = .white   // white "back" button + icons
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(localization)
                .environmentObject(auth)
                .environment(\.locale, localization.locale)
                .tint(Color(Self.brandGreenUI))   // green accent for controls on all screens
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
        // Account deleted on another device -> notice, then the login screen.
        .alert("Аккаунт удалён", isPresented: $auth.accountDeletedNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Ваш аккаунт был удалён. Войдите снова, чтобы продолжить.")
        }
        // Full data load on login (busy indicator), then re-read the local VM.
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn {
                viewModel.reset()              // clean start for the new account
                Task {
                    await sync.pullOnLogin()
                    viewModel.loadData()
                }
            } else {
                viewModel.reset()              // on sign-out/deletion, clear all state
                sync.resetOnSignOut()
            }
        }
        // Silent daily sync when the app enters the active state.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && auth.isSignedIn {
                Task {
                    await sync.dailySyncIfNeeded()
                    viewModel.loadData()
                }
            }
        }
        // Profile just created during onboarding -> upload to the server immediately
        // (otherwise it would only go up on the next daily sync).
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
