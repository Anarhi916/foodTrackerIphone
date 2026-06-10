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
