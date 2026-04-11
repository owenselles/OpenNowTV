import SwiftUI

struct StoreView: View {
    let games: [GameInfo]

    @Environment(AuthManager.self) var authManager
    @Environment(GamesViewModel.self) var viewModel

    @State private var selectedGame: GameInfo?
    @State private var showStream = false

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 40)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if games.isEmpty && viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(2)
                        .tint(.white)
                } else if games.isEmpty {
                    emptyState
                } else {
                    gameGrid
                }
            }
            .navigationTitle("Store")
        }
        .fullScreenCover(isPresented: $showStream) {
            if let game = selectedGame {
                StreamView(game: game, settings: viewModel.streamSettings, onDismiss: { showStream = false })
                    .environment(authManager)
            }
        }
    }

    private var gameGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 40) {
                ForEach(games) { game in
                    StoreCardView(game: game, isInLibrary: game.isInLibrary)
                        .onTapGesture {
                            selectedGame = game
                            showStream = true
                        }
                }
            }
            .padding(60)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "bag")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No games available")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Store Card

struct StoreCardView: View {
    let game: GameInfo
    let isInLibrary: Bool
    @Environment(\.isFocused) var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: game.boxArtUrl.flatMap { URL(string: $0) }) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(2/3, contentMode: .fill)
                    case .failure, .empty:
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.3))
                            .aspectRatio(2/3, contentMode: .fit)
                            .overlay {
                                Image(systemName: "gamecontroller")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.secondary)
                            }
                    @unknown default:
                        Color.gray.opacity(0.3)
                            .aspectRatio(2/3, contentMode: .fit)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if isInLibrary {
                    Text("In Library")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.green.opacity(0.85), in: Capsule())
                        .padding(8)
                }
            }
            .shadow(radius: isFocused ? 20 : 4)
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)

            Text(game.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .focusable()
        .buttonStyle(.plain)
    }
}
