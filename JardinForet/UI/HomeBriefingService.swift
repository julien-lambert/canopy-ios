import Foundation

struct HomeBriefBundle: Decodable {
    let context: HomeBriefContextSnapshot
    let briefing: HomeBriefingSnapshot
    let llm: HomeBriefLLMSnapshot
}

struct HomeBriefContextSnapshot: Decodable {
    struct Site: Decodable {
        let id: String
        let name: String
        let latitude: Double?
        let longitude: Double?
    }

    struct WeatherToday: Decodable {
        let date: String
        let weatherCode: Int?
        let weatherLabel: String
        let tMinC: Double?
        let tMaxC: Double?
        let precipMM: Double?
        let windKMH: Double?
        let cloudCoverPct: Double?

        enum CodingKeys: String, CodingKey {
            case date
            case weatherCode = "weather_code"
            case weatherLabel = "weather_label"
            case tMinC = "t_min_c"
            case tMaxC = "t_max_c"
            case precipMM = "precip_mm"
            case windKMH = "wind_kmh"
            case cloudCoverPct = "cloud_cover_pct"
        }
    }

    struct WeatherHistory: Decodable {
        let startDate: String
        let endDate: String
        let rainMM7D: Double
        let frostNights7D: Int
        let tMinMin7D: Double?
        let tMaxMax7D: Double?

        enum CodingKeys: String, CodingKey {
            case startDate = "start_date"
            case endDate = "end_date"
            case rainMM7D = "rain_mm_7d"
            case frostNights7D = "frost_nights_7d"
            case tMinMin7D = "t_min_min_7d"
            case tMaxMax7D = "t_max_max_7d"
        }
    }

    struct FrostRisk: Decodable {
        let level: String
        let label: String
        let nextFrostAt: String?
        let forecastMinC48H: Double?
        let hoursBelow0C48H: Int
        let siteThresholdC: Double
        let sensitiveIndividualsCount: Int

        enum CodingKeys: String, CodingKey {
            case level
            case label
            case nextFrostAt = "next_frost_at"
            case forecastMinC48H = "forecast_min_c_48h"
            case hoursBelow0C48H = "hours_below_0c_48h"
            case siteThresholdC = "site_threshold_c"
            case sensitiveIndividualsCount = "sensitive_individuals_count"
        }
    }

    struct DataQuality: Decodable {
        let individualsTotal: Int
        let missingPosition: Int
        let missingSpread: Int
        let missingHeight: Int
        let toPlace: Int
        let speciesIncomplete: Int
        let speciesMissingImage: Int
        let speciesMissingSpreadRange: Int

        enum CodingKeys: String, CodingKey {
            case individualsTotal = "individuals_total"
            case missingPosition = "missing_position"
            case missingSpread = "missing_spread"
            case missingHeight = "missing_height"
            case toPlace = "to_place"
            case speciesIncomplete = "species_incomplete"
            case speciesMissingImage = "species_missing_image"
            case speciesMissingSpreadRange = "species_missing_spread_range"
        }
    }

    struct PriorityItem: Decodable, Identifiable {
        let kind: String
        let id: String
        let label: String
        let issues: [String]
    }

    let site: Site
    let generatedAt: String
    let weatherToday: WeatherToday
    let weatherHistory7D: WeatherHistory
    let frostRisk: FrostRisk
    let dataQuality: DataQuality
    let priorityItems: [PriorityItem]

    enum CodingKeys: String, CodingKey {
        case site
        case generatedAt = "generated_at"
        case weatherToday = "weather_today"
        case weatherHistory7D = "weather_history_7d"
        case frostRisk = "frost_risk"
        case dataQuality = "data_quality"
        case priorityItems = "priority_items"
    }
}

struct HomeBriefingSnapshot: Decodable {
    struct WeatherToday: Decodable {
        let label: String
        let tMinC: Double?
        let tMaxC: Double?
        let precipMM: Double?
        let windKMH: Double?

        enum CodingKeys: String, CodingKey {
            case label
            case tMinC = "t_min_c"
            case tMaxC = "t_max_c"
            case precipMM = "precip_mm"
            case windKMH = "wind_kmh"
        }
    }

    struct FrostRisk: Decodable {
        let level: String
        let label: String
        let forecastMinC48H: Double?
        let nextFrostAt: String?

        enum CodingKeys: String, CodingKey {
            case level
            case label
            case forecastMinC48H = "forecast_min_c_48h"
            case nextFrostAt = "next_frost_at"
        }
    }

    struct Alert: Decodable, Identifiable {
        let id = UUID()
        let kind: String
        let severity: String
        let label: String
        let reason: String

        enum CodingKeys: String, CodingKey {
            case kind
            case severity
            case label
            case reason
        }
    }

    struct Task: Decodable, Identifiable {
        let id = UUID()
        let kind: String
        let priority: String
        let label: String
        let targetCount: Int?

        enum CodingKeys: String, CodingKey {
            case kind
            case priority
            case label
            case targetCount = "target_count"
        }
    }

    let briefingDate: String
    let weatherToday: WeatherToday
    let frostRisk: FrostRisk
    let alerts: [Alert]
    let tasks: [Task]
    let fieldChecks: [String]
    let summary: String
    let confidence: String

    enum CodingKeys: String, CodingKey {
        case briefingDate = "briefing_date"
        case weatherToday = "weather_today"
        case frostRisk = "frost_risk"
        case alerts
        case tasks
        case fieldChecks = "field_checks"
        case summary
        case confidence
    }
}

struct HomeBriefLLMSnapshot: Decodable {
    let generated: Bool
    let provider: String?
    let model: String?
    let finishReason: String?
    let promptTokenCount: Int?
    let candidatesTokenCount: Int?
    let totalTokenCount: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case generated
        case provider
        case model
        case finishReason = "finish_reason"
        case promptTokenCount = "prompt_token_count"
        case candidatesTokenCount = "candidates_token_count"
        case totalTokenCount = "total_token_count"
        case error
    }
}

enum HomeBriefingServiceError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Le brief du jour renvoie une reponse invalide."
        }
    }
}

final class HomeBriefingService {
    static let shared = HomeBriefingService()

    private struct Envelope: Decodable {
        let ok: Bool
        let data: HomeBriefBundle?
    }

    private init() {}

    func fetch(siteID: String) async throws -> HomeBriefBundle {
        let envelope: Envelope = try await CanopyEdgeFunctionsClient.invoke(
            "fn-home-brief-v0",
            body: ["site_id": .string(siteID)],
            responseType: Envelope.self
        )

        guard envelope.ok, let data = envelope.data else {
            throw HomeBriefingServiceError.invalidResponse
        }
        return data
    }
}
