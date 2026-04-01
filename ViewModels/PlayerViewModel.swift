import Foundation
import AVKit
import Combine
import MediaPlayer
import os

private let logger = Logger(subsystem: "com.dispatcharr.DispatcharrTV", category: "Player")

enum PlayerBackend {
    case avPlayer
    case vlcKit
}

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var currentChannel: Channel?
    @Published var currentProgram: Program?
    @Published var isPlaying = false
    @Published var showOverlay = false
    @Published var errorMessage: String?
    @Published var streamURL: URL?  // For VLC fallback
    @Published var backend: PlayerBackend = .avPlayer
    @Published var recordingConfirmation: String?

    private var channels: [Channel] = []
    private var currentIndex: Int = 0
    private var statusObserver: NSKeyValueObservation?
    private var lastChannelId: Int?

    func setChannelList(_ channels: [Channel]) {
        self.channels = channels.sorted { ($0.channelNumber ?? 0) < ($1.channelNumber ?? 0) }
    }

    func play(channel: Channel) async {
        // Store last channel before switching
        if let current = currentChannel, current.id != channel.id {
            lastChannelId = current.id
            UserDefaults.standard.set(current.id, forKey: Constants.lastChannelIdKey)
        }

        currentChannel = channel
        errorMessage = nil
        streamURL = nil

        // Update index for channel surfing
        if let idx = channels.firstIndex(where: { $0.id == channel.id }) {
            currentIndex = idx
        }

        // Check if channel has any streams
        if channel.streams == nil || channel.streams?.isEmpty == true {
            errorMessage = "No stream available for this channel"
            return
        }

        // Try to get the direct source URL and convert to m3u8 for AVPlayer
        if let hlsURL = await getHLSURL(for: channel) {
            logger.info("Trying AVPlayer with HLS: \(hlsURL.absoluteString.prefix(60))")
            await playWithAVPlayer(url: hlsURL, channel: channel)
        } else {
            // Fall back to VLC with Dispatcharr TS proxy
            logger.info("No HLS URL, falling back to VLC")
            await playWithVLC(channel: channel)
        }

        updateNowPlayingInfo()
    }

    // MARK: - Play Recording (same path as live TV)

    func playRecording(id: Int) async {
        errorMessage = nil
        streamURL = nil

        let baseURL = await APIClient.shared.serverBaseURL
        let token = await APIClient.shared.currentAccessToken
        var urlString = "\(baseURL)/proxy/hls/recording/\(id)"
        if let token {
            urlString += "?token=\(token)"
        }

        guard let hlsURL = URL(string: urlString) else {
            errorMessage = "Could not build recording URL"
            return
        }

        logger.info("Playing recording via HLS: \(hlsURL.absoluteString.prefix(60))")
        await playWithAVPlayer(url: hlsURL, channel: Channel(id: 0, uuid: "", name: "Recording", channelNumber: nil, logoId: nil, channelGroupId: nil, epgDataId: nil, tvgId: nil, isAdult: nil, streams: nil))
    }

    // MARK: - Last Channel

    func goToLastChannel() async {
        let targetId = lastChannelId ?? UserDefaults.standard.integer(forKey: Constants.lastChannelIdKey)
        guard targetId > 0, let channel = channels.first(where: { $0.id == targetId }) else { return }
        await play(channel: channel)
    }

    // MARK: - Channel Number Entry (tvOS)

    func goToChannelNumber(_ number: Int) async {
        if let channel = channels.first(where: { Int($0.channelNumber ?? -1) == number }) {
            await play(channel: channel)
        }
    }

    // MARK: - Now Playing Info

    private func updateNowPlayingInfo() {
        var info = [String: Any]()
        if let channel = currentChannel {
            info[MPMediaItemPropertyTitle] = channel.name
        }
        if let program = currentProgram {
            info[MPMediaItemPropertyArtist] = program.title
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Recording from Player

    func recordCurrentChannel() async {
        guard let channel = currentChannel else { return }
        let now = Date()
        let endTime = Calendar.current.date(byAdding: .hour, value: 2, to: now)!

        do {
            _ = try await DispatcharrAPI.createRecording(
                channelId: channel.id,
                startTime: now,
                endTime: endTime,
                program: nil
            )
            recordingConfirmation = "Recording scheduled for \(channel.name) (2 hours)"
            // Auto-dismiss after 3 seconds
            Task {
                try? await Task.sleep(for: .seconds(3))
                recordingConfirmation = nil
            }
        } catch {
            recordingConfirmation = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    // MARK: - Continue Watching (Recordings)

    static func savePlaybackPosition(recordingId: Int, position: TimeInterval) {
        UserDefaults.standard.set(position, forKey: "\(Constants.playbackPositionPrefix)\(recordingId)")
    }

    static func loadPlaybackPosition(recordingId: Int) -> TimeInterval? {
        let val = UserDefaults.standard.double(forKey: "\(Constants.playbackPositionPrefix)\(recordingId)")
        return val > 0 ? val : nil
    }

    static func clearPlaybackPosition(recordingId: Int) {
        UserDefaults.standard.removeObject(forKey: "\(Constants.playbackPositionPrefix)\(recordingId)")
    }

    // MARK: - Private

    private func getHLSURL(for channel: Channel) async -> URL? {
        guard let streamId = channel.streams?.first else { return nil }
        do {
            let sourceURL = try await DispatcharrAPI.getStreamURL(streamId: streamId)
            // Convert source .ts to .m3u8 for HLS
            let hlsSourceURL: String
            if sourceURL.hasSuffix(".ts") {
                hlsSourceURL = String(sourceURL.dropLast(3)) + ".m3u8"
            } else {
                hlsSourceURL = sourceURL
            }

            // Initialize the Dispatcharr HLS proxy for this channel
            let channelId = String(channel.id)
            try await DispatcharrAPI.initializeHLSStream(channelId: channel.id, streamURL: hlsSourceURL)
            logger.info("Initialized HLS proxy for channel \(channel.name)")

            // Return the proxy's stream URL
            let baseURL = await APIClient.shared.serverBaseURL
            let token = await APIClient.shared.currentAccessToken
            var proxyURL = "\(baseURL)/proxy/hls/stream/\(channelId)"
            if let token {
                proxyURL += "?token=\(token)"
            }
            return URL(string: proxyURL)
        } catch {
            logger.error("HLS proxy init failed: \(error), trying direct source")
            // Fall back to direct source URL
            return await getDirectHLSURL(for: channel)
        }
    }

    private func getDirectHLSURL(for channel: Channel) async -> URL? {
        guard let streamId = channel.streams?.first else { return nil }
        do {
            let sourceURL = try await DispatcharrAPI.getStreamURL(streamId: streamId)
            let hlsURLString: String
            if sourceURL.hasSuffix(".ts") {
                hlsURLString = String(sourceURL.dropLast(3)) + ".m3u8"
            } else {
                hlsURLString = sourceURL
            }
            return URL(string: hlsURLString)
        } catch {
            return nil
        }
    }

    private func playWithAVPlayer(url: URL, channel: Channel) async {
        backend = .avPlayer
        streamURL = nil

        #if !os(tvOS)
        // Ensure audio session is active for AirPlay
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        // Watch for failures to trigger VLC fallback
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .failed:
                    let err = item.error?.localizedDescription ?? "Unknown"
                    logger.error("AVPlayer failed: \(err), falling back to VLC")
                    await self.playWithVLC(channel: channel)
                case .readyToPlay:
                    logger.info("AVPlayer ready")
                default:
                    break
                }
            }
        }

        if let existing = player {
            existing.replaceCurrentItem(with: item)
        } else {
            player = AVPlayer(playerItem: item)
        }

        player?.play()
        isPlaying = true
        showOverlay = true

        scheduleHideOverlay()
    }

    private func playWithVLC(channel: Channel) async {
        backend = .vlcKit
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        statusObserver = nil

        guard let tsURL = await APIClient.shared.buildTSStreamURL(channelUUID: channel.uuid) else {
            errorMessage = "Could not build stream URL"
            return
        }

        let token = await APIClient.shared.currentAccessToken
        var urlString = tsURL.absoluteString
        if let token {
            urlString += "?token=\(token)"
        }

        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid stream URL"
            return
        }

        logger.info("Playing via VLC: \(url.absoluteString.prefix(60))")
        streamURL = url
        isPlaying = true
        showOverlay = true

        scheduleHideOverlay()
    }

    func channelUp() async {
        guard !channels.isEmpty else { return }
        currentIndex = (currentIndex + 1) % channels.count
        await play(channel: channels[currentIndex])
    }

    func channelDown() async {
        guard !channels.isEmpty else { return }
        currentIndex = (currentIndex - 1 + channels.count) % channels.count
        await play(channel: channels[currentIndex])
    }

    func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        statusObserver = nil
        streamURL = nil
        isPlaying = false
        currentChannel = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func toggleOverlay() {
        showOverlay.toggle()
        if showOverlay {
            scheduleHideOverlay()
        }
    }

    private func scheduleHideOverlay() {
        Task {
            try? await Task.sleep(for: .seconds(5))
            if showOverlay {
                showOverlay = false
            }
        }
    }
}
