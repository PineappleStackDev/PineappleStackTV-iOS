import Foundation
import os

private let logger = Logger(subsystem: "com.dispatcharr.DispatcharrTV", category: "GuideVM")

@MainActor
final class GuideViewModel: ObservableObject {
    @Published var programs: [Program] = []
    @Published var programsByChannel: [String: [Program]] = [:] // keyed by tvg_id
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedProgram: Program?

    // Maps epg_data_id -> tvg_id from the epgdata endpoint
    private var epgDataMap: [Int: String] = [:]
    private var cacheTimestamp: Date?

    var timeSlots: [Date] {
        let calendar = Calendar.current
        let now = Date()
        let startHour = calendar.date(byAdding: .hour, value: -Constants.guideHoursBehind, to: now)!
        let rounded = calendar.date(
            bySetting: .minute,
            value: (calendar.component(.minute, from: startHour) / 30) * 30,
            of: startHour
        )!

        let totalSlots = (Constants.guideHoursAhead + Constants.guideHoursBehind) * 2
        return (0..<totalSlots).compactMap { i in
            calendar.date(byAdding: .minute, value: i * Constants.guideSlotMinutes, to: rounded)
        }
    }

    func loadGuide(forceRefresh: Bool = false) async {
        // Check cache validity
        if !forceRefresh, let ts = cacheTimestamp,
           Date().timeIntervalSince(ts) < Constants.cacheTTL,
           !programs.isEmpty {
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            // Fetch EPG data mappings and grid in parallel
            async let epgDataTask = DispatcharrAPI.getEPGDataMappings()
            async let gridTask = DispatcharrAPI.getEPGGrid()

            let (epgDataEntries, response) = try await (epgDataTask, gridTask)

            // Build epg_data_id -> tvg_id map
            // Use last-wins for duplicate IDs
            var tempMap: [Int: String] = [:]
            for entry in epgDataEntries {
                if let tvgId = entry.tvgId {
                    tempMap[entry.id] = tvgId
                }
            }
            epgDataMap = tempMap

            logger.info("Loaded \(epgDataEntries.count) EPG data mappings, \(response.data.count) programs")

            programs = response.data

            var grouped: [String: [Program]] = [:]
            for program in response.data {
                let key = program.tvgId ?? "unknown"
                grouped[key, default: []].append(program)
            }
            // Sort each channel's programs by start time
            for (key, progs) in grouped {
                grouped[key] = progs.sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            }
            programsByChannel = grouped
            cacheTimestamp = Date()
        } catch {
            logger.error("loadGuide error: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func programs(for channel: Channel) -> [Program] {
        // First try the channel's own tvg_id
        if let tvgId = channel.tvgId, !tvgId.isEmpty, let progs = programsByChannel[tvgId], !progs.isEmpty {
            return progs
        }

        // Then try looking up via epg_data_id -> epgdata tvg_id (remapped EPG)
        if let epgDataId = channel.epgDataId, let mappedTvgId = epgDataMap[epgDataId], let progs = programsByChannel[mappedTvgId], !progs.isEmpty {
            return progs
        }

        // Fallback: try channel UUID
        return programsByChannel[channel.uuid] ?? []
    }
}
