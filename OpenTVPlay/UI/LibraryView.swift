import SwiftUI

struct LibraryView: View {
    @Environment(AuthManager.self) var authManager
    @State private var games: [GameInfo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedGame: GameInfo?
    @State private var showStream = false

    private let gamesClient = GamesClient()

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 40)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if isLoading {
                    ProgressView()
                        .scaleEffect(2)
                        .tint(.white)
                } else if let errorMessage {
                    errorView(errorMessage)
                } else {
                    gameGrid
                }
            }
            .navigationTitle("Games")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out") { authManager.logout() }
                }
            }
        }
        .task { await loadGames() }
        .fullScreenCover(isPresented: $showStream) {
            if let game = selectedGame {
                StreamView(game: game, onDismiss: { showStream = false })
                    .environment(authManager)
            }
        }
    }

    // MARK: Game Grid

    private var gameGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 40) {
                ForEach(games) { game in
                    GameCardView(game: game)
                        .onTapGesture {
                            selectedGame = game
                            showStream = true
                        }
                }
            }
            .padding(60)
        }
    }

    // MARK: Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.yellow)
            Text("Failed to load games")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await loadGames() } }
                .buttonStyle(.bordered)
        }
        .padding(60)
    }

    // MARK: Load

    private func loadGames() async {
        isLoading = true
        errorMessage = nil
        do {
            let token = try await authManager.resolveToken()
            let streamingUrl = authManager.session?.provider.streamingServiceUrl ?? NVIDIAAuth.defaultStreamingUrl
            games = try await gamesClient.fetchMainGames(token: token, streamingBaseUrl: streamingUrl)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Game Card

struct GameCardView: View {
    let game: GameInfo
    @Environment(\.isFocused) var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Box art
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
            .shadow(radius: isFocused ? 20 : 4)
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)

            // Title
            Text(game.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .focusable()
        .buttonStyle(.plain)
    }
}
