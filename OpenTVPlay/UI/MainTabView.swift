import SwiftUI

struct MainTabView: View {
    @Environment(AuthManager.self) var authManager
    @State private var viewModel = GamesViewModel()

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                HomeView()
            }
            Tab("Library", systemImage: "books.vertical.fill") {
                LibraryView(games: viewModel.libraryGames)
            }
            Tab("Store", systemImage: "bag.fill") {
                StoreView(games: viewModel.mainGames)
            }
            Tab("Settings", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
        .environment(viewModel)
        .task { await viewModel.load(authManager: authManager) }
        .onChange(of: viewModel.streamSettings) { viewModel.saveSettings() }
    }
}
