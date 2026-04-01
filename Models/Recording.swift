import Foundation

struct Recording: Codable, Identifiable {
    let id: Int
    let channel: Int
    let startTime: String
    let endTime: String
    let taskId: String?
    let customProperties: RecordingProperties?

    enum CodingKeys: String, CodingKey {
        case id, channel
        case startTime = "start_time"
        case endTime = "end_time"
        case taskId = "task_id"
        case customProperties = "custom_properties"
    }

    var startDate: Date? {
        DateFormatters.parseISO8601(startTime)
    }

    var endDate: Date? {
        DateFormatters.parseISO8601(endTime)
    }

    var status: String {
        customProperties?.status ?? "unknown"
    }

    var programTitle: String {
        customProperties?.program?.title ?? "Recording"
    }

    var programDescription: String? {
        customProperties?.program?.description
    }

    var isInProgress: Bool {
        // If status says recording but end time is past, treat as completed (stale task)
        if status == "recording", let end = endDate, end < Date() {
            return false
        }
        return status == "recording"
    }

    var isCompleted: Bool {
        if status == "completed" || status == "interrupted" { return true }
        // Stale recording: says "recording" but end time passed
        if status == "recording", let end = endDate, end < Date() { return true }
        return false
    }

    var isScheduled: Bool {
        status == "scheduled"
    }
}

struct RecordingProperties: Codable {
    let filePath: String?
    let fileName: String?
    let status: String?
    let program: RecordingProgram?
    let posterUrl: String?
    let fileUrl: String?

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case fileName = "file_name"
        case status
        case program
        case posterUrl = "poster_url"
        case fileUrl = "file_url"
    }
}

struct RecordingProgram: Codable {
    let title: String?
    let description: String?
    let season: Int?
    let episode: Int?
}

struct CreateRecordingRequest: Codable {
    let channel: Int
    let startTime: String
    let endTime: String
    let customProperties: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case channel
        case startTime = "start_time"
        case endTime = "end_time"
        case customProperties = "custom_properties"
    }
}

struct RecurringRule: Codable, Identifiable {
    let id: Int
    let channel: Int
    let name: String?
    let daysOfWeek: [Int]?
    let startTime: String
    let endTime: String
    let enabled: Bool
    let startDate: String?
    let endDate: String?

    enum CodingKeys: String, CodingKey {
        case id, channel, name, enabled
        case daysOfWeek = "days_of_week"
        case startTime = "start_time"
        case endTime = "end_time"
        case startDate = "start_date"
        case endDate = "end_date"
    }
}

struct CreateRecurringRuleRequest: Codable {
    let channel: Int
    let name: String
    let daysOfWeek: [Int]
    let startTime: String
    let endTime: String
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case channel, name, enabled
        case daysOfWeek = "days_of_week"
        case startTime = "start_time"
        case endTime = "end_time"
    }
}

// Generic codable wrapper for mixed-type JSON
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let string as String: try container.encode(string)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let bool as Bool: try container.encode(bool)
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
