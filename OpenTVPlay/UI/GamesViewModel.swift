import Foundation
import Observation

@Observable
class GamesViewModel {
    var mainGames: [GameInfo] = []
    var libraryGames: [GameInfo] = []
    var activeSessions: [ActiveSessionInfo] = []
    var isLoading = false
    var error: String?
    var libraryError: String?

    var favoriteIds: Set<String> = []
    var recentlyPlayedIds: [String] = []
    var streamSettings: StreamSettings = StreamSettings()

    private let gamesClient = GamesClient()
    private let cloudMatchClient = CloudMatchClient()

    init() {
        if let data = UserDefaults.standard.data(forKey: "gfn.favoriteIds"),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            self.favoriteIds = Set(ids)
        }
        if let data = UserDefaults.standard.data(forKey: "gfn.recentlyPlayed"),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            self.recentlyPlayedIds = ids
        }
        if let data = UserDefaults.standard.data(forKey: "gfn.streamSettings"),
           let settings = try? JSONDecoder().decode(StreamSettings.self, from: data) {
            self.streamSettings = settings
        }
    }

    // MARK: Computed

    var continuePlaying: [GameInfo] {
        let sessionAppIds = Set(activeSessions.compactMap { $0.appId })
        return mainGames.filter { game in
            game.variants.contains { v in
                guard let appId = v.appId else { return false }
                return sessionAppIds.contains(appId)
            }
        }
    }

    var favoriteGames: [GameInfo] {
        mainGames.filter { favoriteIds.contains($0.id) }
    }

    var recentlyPlayedGames: [GameInfo] {
        let activeIds = Set(continuePlaying.map { $0.id })
        return recentlyPlayedIds.compactMap { id in
            mainGames.first { $0.id == id && !activeIds.contains($0.id) }
        }
    }

    // MARK: Load

    func load(authManager: AuthManager) async {
        isLoading = true
        error = nil
        libraryError = nil
        do {
            let token = try await authManager.resolveToken()
            let streamingUrl = authManager.session?.provider.streamingServiceUrl ?? NVIDIAAuth.defaultStreamingUrl
            let base = streamingUrl.hasSuffix("/") ? String(streamingUrl.dropLast()) : streamingUrl

            mainGames = try await gamesClient.fetchMainGames(token: token, streamingBaseUrl: base)

            // Non-fatal — may be empty if no games are linked to account
            do {
                libraryGames = try await gamesClient.fetchLibrary(token: token, streamingBaseUrl: base)
            } catch {
                libraryError = error.localizedDescription
                libraryGames = []
            }

            // Non-fatal — may fail if no active sessions or server returns 404
            activeSessions = (try? await cloudMatchClient.getActiveSessions(token: token, base: base)) ?? []
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func refreshActiveSessions(authManager: AuthManager) async {
        guard let token = try? await authManager.resolveToken() else { return }
        let streamingUrl = authManager.session?.provider.streamingServiceUrl ?? NVIDIAAuth.defaultStreamingUrl
        let base = streamingUrl.hasSuffix("/") ? String(streamingUrl.dropLast()) : streamingUrl
        activeSessions = (try? await cloudMatchClient.getActiveSessions(token: token, base: base)) ?? []
    }

    // MARK: Recently Played

    func recordPlayed(_ game: GameInfo) {
        recentlyPlayedIds.removeAll { $0 == game.id }
        recentlyPlayedIds.insert(game.id, at: 0)
        if recentlyPlayedIds.count > 10 { recentlyPlayedIds = Array(recentlyPlayedIds.prefix(10)) }
        let data = try? JSONEncoder().encode(recentlyPlayedIds)
        UserDefaults.standard.set(data, forKey: "gfn.recentlyPlayed")
    }

    // MARK: Favorites

    func toggleFavorite(_ id: String) {
        if favoriteIds.contains(id) {
            favoriteIds.remove(id)
        } else {
            favoriteIds.insert(id)
        }
        saveFavorites()
    }

    func isFavorite(_ id: String) -> Bool {
        favoriteIds.contains(id)
    }

    // MARK: Persistence

    func saveFavorites() {
        let data = try? JSONEncoder().encode(Array(favoriteIds))
        UserDefaults.standard.set(data, forKey: "gfn.favoriteIds")
    }

    func saveSettings() {
        let data = try? JSONEncoder().encode(streamSettings)
        UserDefaults.standard.set(data, forKey: "gfn.streamSettings")
    }
}
