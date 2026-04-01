import Foundation

/// Typed wrapper around APIClient for all PineappleStack endpoints
enum PineappleStackAPI {

    // MARK: - Channels

    static func getChannels() async throws -> [Channel] {
        try await APIClient.shared.get(path: "/api/channels/channels/")
    }

    static func getChannelsSummary() async throws -> [Channel] {
        try await APIClient.shared.get(path: "/api/channels/channels/summary/")
    }

    static func getChannelGroups() async throws -> [ChannelGroup] {
        try await APIClient.shared.get(path: "/api/channels/groups/")
    }

    static func getChannelProfiles() async throws -> [ChannelProfile] {
        try await APIClient.shared.get(path: "/api/channels/profiles/")
    }

    static func getLogos() async throws -> [Logo] {
        // Logos endpoint is paginated, fetch all pages
        var allLogos: [Logo] = []
        var page = 1
        while true {
            let response: PaginatedResponse<Logo> = try await APIClient.shared.get(
                path: "/api/channels/logos/",
                queryItems: [URLQueryItem(name: "page", value: String(page))]
            )
            allLogos.append(contentsOf: response.results)
            if response.next == nil { break }
            page += 1
        }
        return allLogos
    }

    // MARK: - EPG Data Mappings

    static func getEPGDataMappings() async throws -> [EPGData] {
        try await APIClient.shared.get(path: "/api/epg/epgdata/")
    }

    // MARK: - EPG

    static func getEPGGrid() async throws -> EPGGridResponse {
        try await APIClient.shared.get(path: "/api/epg/grid/")
    }

    static func getCurrentPrograms(channelUUIDs: [String]? = nil) async throws -> [Program] {
        let body = CurrentProgramsRequest(channelUuids: channelUUIDs)
        return try await APIClient.shared.post(path: "/api/epg/current-programs/", body: body)
    }

    // MARK: - Recordings

    static func getRecordings() async throws -> [Recording] {
        try await APIClient.shared.get(path: "/api/channels/recordings/")
    }

    static func createRecording(
        channelId: Int,
        startTime: Date,
        endTime: Date,
        program: RecordingProgram? = nil
    ) async throws -> Recording {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var customProps: [String: AnyCodable] = [:]
        if let program {
            var progDict: [String: AnyCodable] = [:]
            if let title = program.title { progDict["title"] = AnyCodable(title) }
            if let desc = program.description { progDict["description"] = AnyCodable(desc) }
            if let season = program.season { progDict["season"] = AnyCodable(season) }
            if let episode = program.episode { progDict["episode"] = AnyCodable(episode) }
            customProps["program"] = AnyCodable(progDict.mapValues { $0.value })
        }

        let body = CreateRecordingRequest(
            channel: channelId,
            startTime: formatter.string(from: startTime),
            endTime: formatter.string(from: endTime),
            customProperties: customProps.isEmpty ? nil : customProps
        )
        return try await APIClient.shared.post(path: "/api/channels/recordings/", body: body)
    }

    static func stopRecording(id: Int) async throws {
        struct Empty: Codable {}
        try await APIClient.shared.postNoResponse(path: "/api/channels/recordings/\(id)/stop/", body: Empty())
    }

    static func extendRecording(id: Int, minutes: Int) async throws {
        struct ExtendBody: Codable { let minutes: Int }
        try await APIClient.shared.postNoResponse(
            path: "/api/channels/recordings/\(id)/extend/",
            body: ExtendBody(minutes: minutes)
        )
    }

    static func deleteRecording(id: Int) async throws {
        try await APIClient.shared.delete(path: "/api/channels/recordings/\(id)/")
    }

    // MARK: - Recurring Rules

    static func getRecurringRules() async throws -> [RecurringRule] {
        try await APIClient.shared.get(path: "/api/channels/recurring-rules/")
    }

    static func createRecurringRule(
        channelId: Int,
        name: String,
        daysOfWeek: [Int],
        startTime: String,
        endTime: String
    ) async throws -> RecurringRule {
        let body = CreateRecurringRuleRequest(
            channel: channelId,
            name: name,
            daysOfWeek: daysOfWeek,
            startTime: startTime,
            endTime: endTime,
            enabled: true
        )
        return try await APIClient.shared.post(path: "/api/channels/recurring-rules/", body: body)
    }

    static func deleteRecurringRule(id: Int) async throws {
        try await APIClient.shared.delete(path: "/api/channels/recurring-rules/\(id)/")
    }

    // MARK: - Stream Details

    static func getStreamURL(streamId: Int) async throws -> String {
        struct StreamDetail: Codable {
            let url: String
        }
        let detail: StreamDetail = try await APIClient.shared.get(path: "/api/channels/streams/\(streamId)/")
        return detail.url
    }

    // MARK: - HLS Stream

    static func initializeHLSStream(channelId: Int, streamURL: String) async throws {
        struct InitBody: Codable { let url: String }
        try await APIClient.shared.postNoResponse(
            path: "/proxy/hls/initialize/\(channelId)",
            body: InitBody(url: streamURL)
        )
    }
}
