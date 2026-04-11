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
        ZStack {
            Color.black.ignoresSafeArea()
            if games.isEmpty && viewModel.isLoading {
                ProgressView().scaleEffect(2).tint(.white)
            } else if games.isEmpty {
                emptyState
            } else {
                gameGrid
            }
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
                    Button {
                        selectedGame = game
                        showStream = true
                    } label: {
                        StoreCardLabel(game: game)
                    }
                    .buttonStyle(.card)
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

// MARK: - Store Card Label

private struct StoreCardLabel: View {
    let game: GameInfo

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GameBoxArt(url: game.boxArtUrl)

            LinearGradient(
                colors: [.black.opacity(0.7), .clear],
                startPoint: .bottom,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(game.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding(10)

            if game.isInLibrary {
                Text("In Library")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.green.opacity(0.85), in: Capsule())
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
    }
}
