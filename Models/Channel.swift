import Foundation

struct Channel: Codable, Identifiable, Hashable {
    let id: Int
    let uuid: String
    let name: String
    let channelNumber: Double?
    let logoId: Int?
    let channelGroupId: Int?
    let epgDataId: Int?
    let tvgId: String?
    let isAdult: Bool?
    let streams: [Int]?

    enum CodingKeys: String, CodingKey {
        case id, uuid, name, streams
        case channelNumber = "channel_number"
        case logoId = "logo_id"
        case channelGroupId = "channel_group_id"
        case epgDataId = "epg_data_id"
        case tvgId = "tvg_id"
        case isAdult = "is_adult"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Channel, rhs: Channel) -> Bool {
        lhs.id == rhs.id
    }
}

struct ChannelGroup: Codable, Identifiable {
    let id: Int
    let name: String
}

struct ChannelProfile: Codable, Identifiable {
    let id: Int
    let name: String
}

struct Logo: Codable, Identifiable {
    let id: Int
    let url: String?
    let file: String?

    var resolvedURL: String? {
        url ?? file
    }
}

struct EPGData: Codable, Identifiable {
    let id: Int
    let tvgId: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case id
        case tvgId = "tvg_id"
        case name
    }
}

struct PaginatedResponse<T: Codable>: Codable {
    let count: Int?
    let next: String?
    let previous: String?
    let results: [T]
}
