import SwiftUI

struct StoreView: View {
    let games: [GameInfo]
    let onPlay: (GameInfo) -> Void

    @Environment(GamesViewModel.self) var viewModel

    @State private var carouselRequest: CarouselRequest?
    @FocusState private var focusedGameId: String?
    @State private var expandedGame: GameInfo? // Ajout pour la vue étendue directe
    @State private var searchText = ""
    @State private var selectedStore: String? = nil
    @Namespace private var carouselScope

    private var availableStores: [String] {
        let stores = Set(games.flatMap { $0.variants.map { $0.appStore } }
            .filter { $0 != "unknown" })
        return stores.sorted()
    }

    private var filteredGames: [GameInfo] {
        var result = games
        if !searchText.isEmpty {
            result = result.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
        if let store = selectedStore {
            result = result.filter { $0.variants.contains { $0.appStore == store } }
        }
        return result
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if games.isEmpty && viewModel.isLoading {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 40)], spacing: 40) {
                        ForEach(0..<12, id: \.self) { _ in GameCardSkeleton() }
                    }
                    .padding(60)
                }
                .allowsHitTesting(false)
            } else if filteredGames.isEmpty {
                emptyState
            } else {
                gameGrid
            }
        }
        .searchable(text: $searchText, prompt: "Search games")
        .overlay {
            if let req = carouselRequest {
                GameCarouselView(request: req, onPlay: onPlay, onDismiss: { lastId in
                    withAnimation(.easeInOut(duration: 0.25)) { carouselRequest = nil }
                    Task { @MainActor in focusedGameId = lastId }
                })
                .environment(viewModel)
                .focusScope(carouselScope)
                .transition(.opacity)
                .ignoresSafeArea()
            }
        }
        .fullScreenCover(item: $expandedGame) { game in
            ExpandedDetailView(game: game, onPlay: { g in
                expandedGame = nil
                onPlay(g)
            })
            .environment(viewModel)
        }
        .animation(.easeInOut(duration: 0.25), value: carouselRequest?.id)
    }

    private var gameGrid: some View {
        VStack(spacing: 0) {
            if availableStores.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        filterChip("All", isSelected: selectedStore == nil) { selectedStore = nil }
                        ForEach(availableStores, id: \.self) { store in
                            filterChip(storeName(store), isSelected: selectedStore == store) {
                                selectedStore = selectedStore == store ? nil : store
                            }
                        }
                    }
                    .padding(.horizontal, 60)
                }
                .scrollClipDisabled()
                .padding(.vertical, 32)
            }
            GameGrid(
                games: filteredGames,
                focusedId: $focusedGameId,
                showLibraryBadge: true,
                onSelect: { game in
                    carouselRequest = CarouselRequest(games: filteredGames, startId: game.id)
                },
                onExpand: { game in
                    expandedGame = game
                }
            )
        }
    }

    private func filterChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? .blue : nil)
    }

    private func storeName(_ store: String) -> String {
        GameVariant(id: "", appStore: store).storeName
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: viewModel.error != nil ? "exclamationmark.triangle" : "bag")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text(viewModel.error != nil ? "Failed to Load Games" : "No games available")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            if let err = viewModel.error {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(60)
    }
}
