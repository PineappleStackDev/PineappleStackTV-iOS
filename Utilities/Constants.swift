import Foundation

enum Constants {
    static let defaultPort = 9191
    static let jwtRefreshThreshold: TimeInterval = 120 // refresh 2 min before expiry
    static let channelGridColumns = 5
    static let guideHoursAhead = 24
    static let guideHoursBehind = 1
    static let guideSlotMinutes = 30
    static let keychainService = "com.dispatcharrtv"
    static let keychainServerURL = "serverURL"
    static let keychainAccessToken = "accessToken"
    static let keychainRefreshToken = "refreshToken"
    static let keychainUsername = "username"

    // UserDefaults keys
    static let favoritesKey = "favoriteChannelIds"
    static let lastChannelIdKey = "lastChannelId"
    static let rememberServerKey = "rememberServer"
    static let savedServerURLKey = "savedServerURL"
    static let streamBufferSizeKey = "streamBufferSize"
    static let autoPlayKey = "autoPlayEnabled"
    static let playbackPositionPrefix = "playbackPosition_"
    static let channelsCacheTimestampKey = "channelsCacheTimestamp"
    static let guideCacheTimestampKey = "guideCacheTimestamp"
    static let cacheTTL: TimeInterval = 300 // 5 minutes
}
