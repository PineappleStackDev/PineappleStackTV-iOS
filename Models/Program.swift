import Foundation

struct Program: Codable, Identifiable {
    let id: String
    let startTime: String
    let endTime: String
    let title: String
    let subTitle: String?
    let description: String?
    let tvgId: String?
    let season: Int?
    let episode: Int?
    let isNew: Bool?
    let isLive: Bool?
    let isPremiere: Bool?
    let isFinale: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case startTime = "start_time"
        case endTime = "end_time"
        case title
        case subTitle = "sub_title"
        case description
        case tvgId = "tvg_id"
        case season, episode
        case isNew = "is_new"
        case isLive = "is_live"
        case isPremiere = "is_premiere"
        case isFinale = "is_finale"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // id can be String or Int from the API
        if let stringId = try? container.decode(String.self, forKey: .id) {
            id = stringId
        } else if let intId = try? container.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = UUID().uuidString
        }
        startTime = try container.decode(String.self, forKey: .startTime)
        endTime = try container.decode(String.self, forKey: .endTime)
        title = try container.decode(String.self, forKey: .title)
        subTitle = try container.decodeIfPresent(String.self, forKey: .subTitle)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        tvgId = try container.decodeIfPresent(String.self, forKey: .tvgId)
        season = try container.decodeIfPresent(Int.self, forKey: .season)
        episode = try container.decodeIfPresent(Int.self, forKey: .episode)
        isNew = try container.decodeIfPresent(Bool.self, forKey: .isNew)
        isLive = try container.decodeIfPresent(Bool.self, forKey: .isLive)
        isPremiere = try container.decodeIfPresent(Bool.self, forKey: .isPremiere)
        isFinale = try container.decodeIfPresent(Bool.self, forKey: .isFinale)
    }

    var startDate: Date? {
        DateFormatters.parseISO8601(startTime)
    }

    var endDate: Date? {
        DateFormatters.parseISO8601(endTime)
    }

    var isCurrentlyAiring: Bool {
        guard let start = startDate, let end = endDate else { return false }
        let now = Date()
        return start <= now && end > now
    }

    var seasonEpisodeString: String? {
        guard let s = season, let e = episode else { return nil }
        return "S\(String(format: "%02d", s))E\(String(format: "%02d", e))"
    }
}

struct EPGGridResponse: Codable {
    let data: [Program]
}

struct CurrentProgramsRequest: Codable {
    let channelUuids: [String]?

    enum CodingKeys: String, CodingKey {
        case channelUuids = "channel_uuids"
    }
}
