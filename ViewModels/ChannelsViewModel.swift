import Foundation
import os

private let logger = Logger(subsystem: "com.dispatcharr.DispatcharrTV", category: "ChannelsVM")

@MainActor
final class ChannelsViewModel: ObservableObject {
    @Published var channels: [Channel] = []
    @Published var groups: [ChannelGroup] = []
    @Published var logos: [Int: Logo] = [:]
    @Published var currentPrograms: [String: Program] = [:] // keyed by tvg_id
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var favorites: Set<Int> = []
    @Published var searchText: String = ""

    private var cacheTimestamp: Date?

    var allChannelsSorted: [Channel] {
        channels.sorted { ($0.channelNumber ?? 0) < ($1.channelNumber ?? 0) }
    }

    var filteredChannels: [Channel] {
        let sorted = allChannelsSorted
        if searchText.isEmpty { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var favoriteChannels: [Channel] {
        allChannelsSorted.filter { favorites.contains($0.id) }
    }

    init() {
        loadFavorites()
    }

    // MARK: - Favorites

    func toggleFavorite(channelId: Int) {
        if favorites.contains(channelId) {
            favorites.remove(channelId)
        } else {
            favorites.insert(channelId)
        }
        saveFavorites()
    }

    func isFavorite(_ channelId: Int) -> Bool {
        favorites.contains(channelId)
    }

    private func loadFavorites() {
        let stored = UserDefaults.standard.array(forKey: Constants.favoritesKey) as? [Int] ?? []
        favorites = Set(stored)
    }

    private func saveFavorites() {
        UserDefaults.standard.set(Array(favorites), forKey: Constants.favoritesKey)
    }

    // MARK: - Data Loading

    func loadAll(forceRefresh: Bool = false) async {
        // Check cache validity
        if !forceRefresh, let ts = cacheTimestamp,
           Date().timeIntervalSince(ts) < Constants.cacheTTL,
           !channels.isEmpty {
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            async let channelsTask = DispatcharrAPI.getChannels()
            async let groupsTask = DispatcharrAPI.getChannelGroups()
            async let logosTask = DispatcharrAPI.getLogos()

            let (fetchedChannels, fetchedGroups, fetchedLogos) = try await (
                channelsTask, groupsTask, logosTask
            )

            channels = fetchedChannels
            groups = fetchedGroups
            logos = Dictionary(fetchedLogos.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            cacheTimestamp = Date()

            // Load current programs
            await loadCurrentPrograms()
        } catch {
            logger.error("loadAll error: \(error)")
            errorMessage = error.localizedDescription
        }

        logger.info("Loaded \(self.channels.count) channels, \(self.groups.count) groups, \(self.logos.count) logos")
        isLoading = false
    }

    func loadCurrentPrograms() async {
        do {
            let uuids = channels.compactMap { $0.uuid }
            let programs = try await DispatcharrAPI.getCurrentPrograms(channelUUIDs: uuids)
            var programMap: [String: Program] = [:]
            for program in programs {
                if let tvgId = program.tvgId {
                    programMap[tvgId] = program
                }
            }
            currentPrograms = programMap
        } catch {
            // Non-critical, don't show error
        }
    }

    func currentProgram(for channel: Channel) -> Program? {
        if let tvgId = channel.tvgId, let prog = currentPrograms[tvgId] {
            return prog
        }
        // Also try matching by channel UUID
        return currentPrograms[channel.uuid]
    }

    func logoURL(for channel: Channel) async -> URL? {
        guard let logoId = channel.logoId, let logo = logos[logoId] else { return nil }
        guard let path = logo.resolvedURL else { return nil }
        return await APIClient.shared.buildLogoURL(logoPath: path)
    }
}

// Workaround: need a sync version for views
extension ChannelsViewModel {
    func logoURLSync(for channel: Channel) -> URL? {
        guard let logoId = channel.logoId, let logo = logos[logoId] else { return nil }
        guard let path = logo.resolvedURL else { return nil }
        if path.hasPrefix("http") {
            return URL(string: path)
        }
        return nil
    }
}
