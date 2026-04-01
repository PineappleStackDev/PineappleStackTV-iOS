# PineappleStackTV: Complete Reference for Android TV Port

Extracted from all 28 Swift source files in the iOS/tvOS app.

---

## 1. API ENDPOINTS

Base URL is user-configured (stored in Keychain). Default port: **9191**.
All authenticated requests use `Authorization: Bearer <access_token>`.
Content-Type for POST bodies: `application/json`.

### Authentication

| Method | Path | Auth | Request Body | Response |
|--------|------|------|-------------|----------|
| POST | `/api/accounts/token/` | No | `{ "username": string, "password": string }` | `{ "access": string, "refresh": string }` |
| POST | `/api/accounts/token/refresh/` | No | `{ "refresh": string }` | `{ "access": string }` |

### Channels

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| GET | `/api/channels/channels/` | Yes | Returns `Channel[]` |
| GET | `/api/channels/channels/summary/` | Yes | Returns `Channel[]` (lighter payload, not currently used) |
| GET | `/api/channels/groups/` | Yes | Returns `ChannelGroup[]` |
| GET | `/api/channels/profiles/` | Yes | Returns `ChannelProfile[]` (not currently used in UI) |
| GET | `/api/channels/logos/?page={n}` | Yes | Paginated. Returns `{ count, next, previous, results: Logo[] }` |
| GET | `/api/channels/streams/{streamId}/` | Yes | Returns `{ "url": string }` (the raw source stream URL) |

### EPG (Electronic Program Guide)

| Method | Path | Auth | Request/Response |
|--------|------|------|-----------------|
| GET | `/api/epg/epgdata/` | Yes | Returns `EPGData[]` (maps epg_data_id to tvg_id) |
| GET | `/api/epg/grid/` | Yes | Returns `{ "data": Program[] }` |
| POST | `/api/epg/current-programs/` | Yes | Body: `{ "channel_uuids": string[] or null }`. Returns `Program[]` |

### Recordings

| Method | Path | Auth | Request/Response |
|--------|------|------|-----------------|
| GET | `/api/channels/recordings/` | Yes | Returns `Recording[]` |
| POST | `/api/channels/recordings/` | Yes | Body: `CreateRecordingRequest`. Returns `Recording` |
| POST | `/api/channels/recordings/{id}/stop/` | Yes | Body: `{}`. No response body (2xx = success) |
| POST | `/api/channels/recordings/{id}/extend/` | Yes | Body: `{ "minutes": int }`. No response body |
| DELETE | `/api/channels/recordings/{id}/` | Yes | No response body |
| GET | `/api/channels/recordings/{id}/file/` | Yes | Returns the recording file (used to build playback URL) |

### Recurring Recording Rules

| Method | Path | Auth | Request/Response |
|--------|------|------|-----------------|
| GET | `/api/channels/recurring-rules/` | Yes | Returns `RecurringRule[]` |
| POST | `/api/channels/recurring-rules/` | Yes | Body: `CreateRecurringRuleRequest`. Returns `RecurringRule` |
| DELETE | `/api/channels/recurring-rules/{id}/` | Yes | No response body |

### HLS Proxy (Stream Playback)

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| POST | `/proxy/hls/initialize/{channelId}` | Yes | Body: `{ "url": string }`. Starts HLS proxy for channel |
| GET | `/proxy/hls/stream/{channelId}?token={jwt}` | Token in query | HLS playlist (.m3u8) for live TV |
| GET | `/proxy/ts/stream/{channelUUID}?token={jwt}` | Token in query | Raw TS stream (VLC fallback) |
| GET | `/proxy/hls/recording/{recordingId}?token={jwt}` | Token in query | HLS playlist for recording playback |

---

## 2. DATA MODELS

### Channel
```
id: Int
uuid: String
name: String
channel_number: Double? (nullable)
logo_id: Int? (nullable, FK to Logo)
channel_group_id: Int? (nullable, FK to ChannelGroup)
epg_data_id: Int? (nullable, FK to EPGData)
tvg_id: String? (nullable, used for EPG matching)
is_adult: Bool? (nullable)
streams: [Int]? (nullable, array of stream IDs)
```

### ChannelGroup
```
id: Int
name: String
```

### ChannelProfile
```
id: Int
name: String
```

### Logo
```
id: Int
url: String? (nullable, external URL)
file: String? (nullable, server-relative path)
```
Resolved URL: prefer `url`, fall back to `file`. If path starts with "http", use as-is; otherwise prepend baseURL.

### Program
```
id: String (can come as String or Int from API; always stored as String)
start_time: String (ISO 8601)
end_time: String (ISO 8601)
title: String
sub_title: String? (nullable)
description: String? (nullable)
tvg_id: String? (nullable, links to Channel.tvg_id or EPGData.tvg_id)
season: Int? (nullable)
episode: Int? (nullable)
is_new: Bool? (nullable)
is_live: Bool? (nullable)
is_premiere: Bool? (nullable)
is_finale: Bool? (nullable)
```

### EPGData
```
id: Int
tvg_id: String? (nullable)
name: String? (nullable)
```
Used to build mapping: `epg_data_id -> tvg_id` for channels where `channel.tvg_id` differs from the EPG grid's tvg_id.

### EPGGridResponse
```
data: Program[]
```

### CurrentProgramsRequest
```
channel_uuids: String[]? (nullable)
```

### PaginatedResponse<T>
```
count: Int? (nullable)
next: String? (nullable, URL to next page)
previous: String? (nullable)
results: T[]
```

### Recording
```
id: Int
channel: Int (FK to Channel.id)
start_time: String (ISO 8601)
end_time: String (ISO 8601)
task_id: String? (nullable)
custom_properties: RecordingProperties? (nullable)
```

### RecordingProperties
```
file_path: String? (nullable)
file_name: String? (nullable)
status: String? (nullable; values: "scheduled", "recording", "completed", "interrupted", "failed")
program: RecordingProgram? (nullable)
poster_url: String? (nullable)
file_url: String? (nullable)
```

### RecordingProgram
```
title: String? (nullable)
description: String? (nullable)
season: Int? (nullable)
episode: Int? (nullable)
```

### CreateRecordingRequest
```
channel: Int
start_time: String (ISO 8601)
end_time: String (ISO 8601)
custom_properties: Object? (nullable, contains "program" sub-object with title/description/season/episode)
```

### RecurringRule
```
id: Int
channel: Int (FK to Channel.id)
name: String? (nullable)
days_of_week: [Int]? (nullable; 0=Sunday, 1=Monday, ... 6=Saturday)
start_time: String (HH:mm:ss format)
end_time: String (HH:mm:ss format)
enabled: Bool
start_date: String? (nullable)
end_date: String? (nullable)
```

### CreateRecurringRuleRequest
```
channel: Int
name: String
days_of_week: [Int]
start_time: String (HH:mm:ss)
end_time: String (HH:mm:ss)
enabled: Bool
```

### AuthTokenResponse
```
access: String (JWT)
refresh: String (JWT)
```

### TokenRefreshResponse
```
access: String (JWT)
```

---

## 3. AUTH FLOW

### Login
1. User enters server URL, username, password on LoginView.
2. URL normalization:
   - If no scheme, prepend `http://` for IP addresses/localhost, `https://` for domain names.
   - If IP/localhost and no explicit port, append `:9191`.
3. Call `POST /api/accounts/token/` with `{ username, password }`.
4. On success, store in secure storage (Keychain on iOS):
   - `serverURL`
   - `accessToken`
   - `refreshToken`
   - `username`
5. Optionally save server URL to UserDefaults if "Remember Server" is toggled on.

### Auto-login on App Launch
1. Check Keychain for saved `serverURL`, `accessToken`, `refreshToken`.
2. If all three exist, configure the API client and set `isAuthenticated = true`.
3. No explicit token validation on launch; first API call will trigger refresh if expired.

### Token Refresh (Automatic)
1. On any API call returning HTTP 401 (and not already retrying):
   - Call `POST /api/accounts/token/refresh/` with the saved refresh token.
   - On success: update stored access token, retry original request with new token.
   - On failure (401 from refresh): clear both tokens, set unauthenticated state.
2. Only one refresh attempt per request (retried flag prevents loops).

### Logout
1. Clear tokens from API client memory.
2. Delete all Keychain entries (serverURL, accessToken, refreshToken, username).
3. Set `isAuthenticated = false`.
4. Keep server URL in memory if "Remember Server" is on; clear otherwise.

### Token Placement
- Most requests: `Authorization: Bearer <token>` header.
- Stream URLs (HLS/TS): token passed as `?token=<jwt>` query parameter (because media players can't set custom headers).

---

## 4. UI SCREENS AND NAVIGATION

### App Structure
Root: `PineappleStackTVApp`
- If NOT authenticated: show **LoginView**
- If authenticated: show **TabView** with 4 tabs:

#### Tab 1: Live TV (ChannelGridView)
- Searchable channel grid (adaptive grid layout, 280x180 cards)
- **Favorites section** at top (horizontal scroll on tvOS, grid on iOS)
- **All Channels section** below
- Each card (ChannelCardView) shows: logo, channel number, name, current program title, progress bar
- Tap card: opens **PlayerView** as fullScreenCover
- Long-press/context: toggle favorite (star icon on card)
- tvOS: supports number pad entry for direct channel tuning (2-second buffer before switching)
- Pull-to-refresh reloads channels
- Data loaded on appear: channels, groups, logos, EPG guide (in parallel)

#### Tab 2: Guide (GuideView)
- Traditional EPG grid: channels on left column, time slots across top
- Horizontal + vertical scrollable with pinned time header
- Time range: 1 hour behind to 24 hours ahead, 30-minute slots
- Currently airing programs highlighted in blue
- Tap program: opens **ProgramDetailView** as sheet
  - Shows title, subtitle, season/episode, NEW/LIVE badges, description, channel info
  - Buttons: "Watch Now" (if currently airing), "Record" (single), "Record Series" (recurring rule)
- tvOS: focus-based navigation with scale/border effects on focused program blocks

#### Tab 3: Recordings (RecordingsListView)
- Three sections:
  1. **Recording Now**: in-progress recordings with stop/extend buttons (+15/+30/+60 min)
  2. **Scheduled**: upcoming recordings with delete via context menu
  3. **Completed**: grouped by show name, sorted newest first within each group
     - Tap to play; shows resume indicator if position was saved
     - Context menu: delete, clear resume position
     - Section header context menu: retention rules (Keep All/3/5/10), delete all episodes
  4. **Series Rules**: recurring recording rules with enabled/disabled indicator, delete via context menu
- In-progress recordings auto-refresh every 15 seconds
- Playing an in-progress recording shows a choice dialog: "Watch from Start" or "Go to Live"
- Retention rules stored in UserDefaults (`recording_retention` key, `{ showName: maxCount }`)

#### Tab 4: Settings (SettingsView)
- Server info display (URL, username)
- Playback settings: buffer size (Low/Medium/High), auto-play toggle
- Clear image cache button
- Logout button
- App version display

### PlayerView (Full Screen)
Two backends with automatic fallback:
1. **AVPlayer** (primary): presents AVPlayerViewController modally via UIKit bridge
   - Supports PiP, AirPlay, external display
   - On failure: automatically falls back to VLC
2. **VLCKit** (fallback): custom VLC media player view
   - Shows channel name overlay, record button, last channel button, AirPlay picker, close button
   - Recording confirmation toast auto-dismisses after 3 seconds

### PlayerOverlayView (tvOS overlay on player)
- Top bar: channel logo, number, name, current program info (title, subtitle, time, S##E##, NEW badge)
- Bottom bar: navigation hints ("Up/Down: Change Channel", "Menu: Close")
- Gradient backgrounds for readability

---

## 5. PLAYER IMPLEMENTATION

### Live TV Playback Flow
1. User selects a channel.
2. Check `channel.streams` array; if empty, show error.
3. Get source URL: `GET /api/channels/streams/{streams[0]}/` returns `{ "url": "..." }`.
4. Convert source URL: if ends in `.ts`, replace with `.m3u8`.
5. Initialize HLS proxy: `POST /proxy/hls/initialize/{channelId}` with `{ "url": "<m3u8_url>" }`.
6. Build proxy stream URL: `{baseURL}/proxy/hls/stream/{channelId}?token={jwt}`.
7. Play with AVPlayer. If AVPlayer fails (status observation), fall back to VLC.

### VLC Fallback Flow
1. Build TS stream URL: `{baseURL}/proxy/ts/stream/{channelUUID}?token={jwt}`.
2. Create VLCMedia with options: `network-caching: 1500, clock-jitter: 0, clock-synchro: 0`.
3. Set media on VLCMediaPlayer and play.

### Direct HLS Fallback
If HLS proxy initialization fails, try playing the source URL directly (with .ts-to-.m3u8 conversion).

### Recording Playback Flow
1. Build URL: `{baseURL}/proxy/hls/recording/{recordingId}?token={jwt}`.
2. Play with AVPlayer (same AVPlayerPresenter as live TV).

### Channel Surfing
- `channelUp()` / `channelDown()`: cycle through sorted channel list (wraps around).
- Last channel tracking: saved to UserDefaults, accessible via `goToLastChannel()`.
- Direct channel number entry (tvOS): accumulates digits for 2 seconds, then tunes.

### Playback Position (Recordings)
- Saved to UserDefaults as `playbackPosition_{recordingId}` (TimeInterval/Double).
- Resume indicator shown in recordings list if position exists.
- Can be cleared manually via context menu.

### Audio/Video Session (iOS)
```
AVAudioSession.setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo)
AVAudioSession.setActive(true)
```
Set at app init and before AVPlayer playback.

### Now Playing Info
Sets `MPNowPlayingInfoCenter` with channel name (title) and program name (artist).

---

## 6. CONSTANTS AND CONFIGURATION

```
defaultPort = 9191
jwtRefreshThreshold = 120 seconds (not actively used; refresh is triggered by 401)
channelGridColumns = 5
guideHoursAhead = 24
guideHoursBehind = 1
guideSlotMinutes = 30
cacheTTL = 300 seconds (5 minutes, for channels and guide data)

Keychain service identifier: "com.pineapplestacktv"
Keychain keys: "serverURL", "accessToken", "refreshToken", "username"

UserDefaults keys:
  "favoriteChannelIds" -> [Int]
  "lastChannelId" -> Int
  "rememberServer" -> Bool
  "savedServerURL" -> String
  "streamBufferSize" -> String ("Low"/"Medium"/"High")
  "autoPlayEnabled" -> Bool
  "playbackPosition_{id}" -> Double
  "channelsCacheTimestamp" -> (unused in code, defined in constants)
  "guideCacheTimestamp" -> (unused in code, defined in constants)
  "recording_retention" -> [String: Int] (show name to max episode count)
```

---

## 7. DATE FORMATTING

All dates from the API are ISO 8601 strings. Two parsers are tried in order:
1. ISO 8601 with fractional seconds (`2024-01-15T14:30:00.000Z`)
2. ISO 8601 without fractional seconds (`2024-01-15T14:30:00Z`)

Display formatters:
- `timeOnly`: "h:mm a" (12-hour with AM/PM)
- `dateOnly`: medium date style
- `dateTime`: medium date + short time
- `timeOnly24h`: "HH:mm:ss" (24-hour, used for recurring rules)
- `dayOfWeekShort`: "EEE" (Mon, Tue, etc.)

---

## 8. IMAGE CACHING

Custom two-tier cache for channel logos:
1. **Memory**: NSCache with 200 item limit
2. **Disk**: PNG files in app's caches directory under "ImageCache/"
3. Cache key: base64 of URL string, truncated to 64 chars
4. `CachedAsyncImage` is a drop-in SwiftUI view that checks cache before downloading

---

## 9. ERROR HANDLING

API errors are an enum:
- `invalidURL(path)`: malformed URL construction
- `invalidResponse`: non-HTTP response
- `httpError(statusCode)`: any non-2xx status
- `notAuthenticated`: no refresh token or refresh failed with 401
- `decodingError(underlyingError)`: JSON parsing failure

All ViewModels surface errors via `@Published var errorMessage: String?` for UI display.

---

## 10. NETWORK CLIENT DETAILS

- `URLSession` with 30s request timeout, 300s resource timeout.
- `JSONEncoder` / `JSONDecoder` with default settings (no snake_case conversion; models use CodingKeys for mapping).
- The APIClient is an `actor` (Swift concurrency) ensuring thread-safe token management.
- Single retry on 401 with token refresh; no retry on other errors.
- `postNoResponse` variant for endpoints that return no body (stop, extend).

---

## 11. ANDROID TV PORTING NOTES

### Equivalent Android Components
| iOS | Android TV |
|-----|-----------|
| AVPlayer + AVPlayerViewController | ExoPlayer (Media3) + PlayerView |
| VLCKit (VLCMediaPlayer) | VLC Android SDK or ExoPlayer TS extractor |
| SwiftUI TabView | Leanback BrowseSupportFragment or Compose TV Navigation |
| SwiftUI LazyVGrid | Compose TV LazyVerticalGrid or Leanback VerticalGridFragment |
| Keychain | Android Keystore + EncryptedSharedPreferences |
| UserDefaults | SharedPreferences / DataStore |
| NSCache + disk cache | Coil or Glide with disk cache |
| AVAudioSession | AudioManager focus handling |
| MPNowPlayingInfoCenter | MediaSession |
| AirPlay (AVRoutePickerView) | Google Cast SDK |
| PiP (AVPlayerViewController) | PictureInPictureParams on Activity |
| @StateObject / @ObservedObject | ViewModel + StateFlow/LiveData |
| async/await (Swift) | Kotlin coroutines |
| URLSession | OkHttp + Retrofit |
| Codable | Kotlin Serialization or Moshi/Gson |
| ISO8601DateFormatter | java.time.OffsetDateTime / Instant |

### Key Implementation Details for ExoPlayer
- HLS streams: use `HlsMediaSource` with the proxy URL including token as query param
- TS streams (fallback): use `ProgressiveMediaSource` or VLC Android
- Recording playback: same HLS path as live, just different URL
- Token in query string (not header) for media URLs
- Channel surfing: swap `MediaItem` on existing ExoPlayer instance
