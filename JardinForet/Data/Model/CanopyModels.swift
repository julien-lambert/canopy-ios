import Foundation
import CoreLocation
import GRDB

// MARK: - Supabase DTO (remote table truth)

/// Accepts either an Int or a String representing an Int, or null.
struct FlexibleInt: Codable {
    let value: Int?

    init(value: Int?) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let stringVal = try? container.decode(String.self),
                  let intVal = Int(stringVal.trimmingCharacters(in: .whitespacesAndNewlines)) {
            value = intVal
        } else {
            value = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

/// Accepts either a Double or a String representing a Double, or null.
struct FlexibleDouble: Codable {
    let value: Double?

    init(value: Double?) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
        } else if let stringVal = try? container.decode(String.self),
                  let doubleVal = Double(stringVal.trimmingCharacters(in: .whitespacesAndNewlines)) {
            value = doubleVal
        } else {
            value = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

struct SpeciesDTO: Codable {
    let id: Int
    let commonName: String?
    let varietyName: String?
    let latinName: String?
    let family: String?
    let genus: String?
    let strata: String?
    let tags: String?
    let notes: String?
    let imageURL: String?
    let origin: String?
    let plantType: String?
    let morphology: String?
    let culture: String?
    let uses: String?
    let melliferousLevel: String?
    let ornamentalInterest: String?
    let lifespanMin: FlexibleInt?
    let lifespanMax: FlexibleInt?
    let heightMin: FlexibleDouble?
    let heightMax: FlexibleDouble?
    let envergureMin: FlexibleDouble?
    let envergureMax: FlexibleDouble?
    let floweringPeriod: String?
    let fruitingPeriod: String?
    let varietyNotes: String?
    let uuid: String?
    let updatedAt: String?
    let deleted: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case commonName = "common_name"
        case varietyName = "variety_name"
        case latinName = "latin_name"
        case family
        case genus
        case strata
        case tags
        case notes
        case imageURL = "image_url"
        case origin
        case plantType = "plant_type"
        case morphology
        case culture
        case uses
        case melliferousLevel = "melliferous_level"
        case ornamentalInterest = "ornamental_interest"
        case lifespanMin = "lifespan_min"
        case lifespanMax = "lifespan_max"
        case heightMin = "height_min"
        case heightMax = "height_max"
        case envergureMin = "envergure_min"
        case envergureMax = "envergure_max"
        case floweringPeriod = "flowering_period"
        case fruitingPeriod = "fruiting_period"
        case varietyNotes = "variety_notes"
        case uuid
        case updatedAt = "updated_at"
        case deleted
    }
}

struct PlantDTO: Codable {
    let id: Int
    let speciesId: Int
    let label: String?
    let lat: Double?
    let lon: Double?
    let zone: String?
    let plantedAt: String?
    let notes: String?
    let imageLocal: String?
    let altitude: Double?
    let tags: String?
    let microSite: String?
    let exposureLocal: String?
    let soilLocal: String?
    let heightCurrent: Double?
    let envergureCurrent: Double?
    let acquisitionType: String?
    let acquisitionSource: String?
    let plantnetObsId: String?
    let status: String?
    let careNotes: String?
    let rootstock: String?
    let uuid: String?
    let updatedAt: String?
    let deleted: Bool
    let varietyId: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case speciesId = "species_id"
        case label
        case lat
        case lon
        case zone
        case plantedAt = "planted_at"
        case notes
        case imageLocal = "image_local"
        case altitude
        case tags
        case microSite = "micro_site"
        case exposureLocal = "exposure_local"
        case soilLocal = "soil_local"
        case heightCurrent = "height_current"
        case envergureCurrent = "envergure_current"
        case acquisitionType = "acquisition_type"
        case acquisitionSource = "acquisition_source"
        case plantnetObsId = "plantnet_obs_id"
        case status
        case careNotes = "care_notes"
        case rootstock
        case uuid
        case updatedAt = "updated_at"
        case deleted
        case varietyId = "variety_id"
    }
}

struct CultivarDTO: Codable {
    let id: Int
    let speciesId: Int
    let name: String
    let notes: String?
    let tags: String?
    let origin: String?
    let plantType: String?
    let morphology: String?
    let culture: String?
    let uses: String?
    let melliferousLevel: String?
    let ornamentalInterest: String?
    let lifespanMin: FlexibleInt?
    let lifespanMax: FlexibleInt?
    let heightMin: FlexibleDouble?
    let heightMax: FlexibleDouble?
    let floweringPeriod: String?
    let fruitingPeriod: String?
    let uuid: String?
    let updatedAt: String?
    let deleted: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case speciesId = "species_id"
        case name
        case notes
        case tags
        case origin
        case plantType = "plant_type"
        case morphology
        case culture
        case uses
        case melliferousLevel = "melliferous_level"
        case ornamentalInterest = "ornamental_interest"
        case lifespanMin = "lifespan_min"
        case lifespanMax = "lifespan_max"
        case heightMin = "height_min"
        case heightMax = "height_max"
        case floweringPeriod = "flowering_period"
        case fruitingPeriod = "fruiting_period"
        case uuid
        case updatedAt = "updated_at"
        case deleted
    }
}

struct PlantWriteInput {
    var speciesId: Int
    var varietyId: Int? = nil
    var zone: String?
    var notes: String?
    var status: String? = nil
    var microSite: String? = nil
    var exposureLocal: String? = nil
    var soilLocal: String? = nil
    var acquisitionType: String? = nil
    var acquisitionSource: String? = nil
    var careNotes: String? = nil
    var heightCurrent: Double? = nil
    var envergureCurrent: Double? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
}

struct SpeciesWriteInput {
    var commonName: String
    var varietyName: String? = nil
    var latinName: String
    var family: String?
    var genus: String?
    var strata: String?
    var tags: String?
    var notes: String?
    var imageURL: String?
    var origin: String?
    var plantType: String?
    var morphology: String?
    var culture: String?
    var uses: String?
    var melliferousLevel: String?
    var ornamentalInterest: String?
    var lifespanMin: Int?
    var lifespanMax: Int?
    var heightMin: Double?
    var heightMax: Double?
    var envergureMin: Double?
    var envergureMax: Double?
    var floweringPeriod: String?
    var fruitingPeriod: String?
    var varietyNotes: String?
}

struct SpeciesCommonWriteInput {
    var commonName: String
    var family: String?
    var genus: String?
    var strata: String?
    var tags: String?
    var notes: String?
    var imageURL: String?
    var origin: String?
    var plantType: String?
    var morphology: String?
    var culture: String?
    var uses: String?
    var melliferousLevel: String?
    var ornamentalInterest: String?
    var lifespanMin: Int?
    var lifespanMax: Int?
    var heightMin: Double?
    var heightMax: Double?
    var envergureMin: Double?
    var envergureMax: Double?
    var floweringPeriod: String?
    var fruitingPeriod: String?
}

struct CultivarWriteInput {
    var name: String
    var notes: String?
    var tags: String? = nil
    var origin: String? = nil
    var plantType: String? = nil
    var morphology: String? = nil
    var culture: String? = nil
    var uses: String? = nil
    var melliferousLevel: String? = nil
    var ornamentalInterest: String? = nil
    var lifespanMin: Int? = nil
    var lifespanMax: Int? = nil
    var heightMin: Double? = nil
    var heightMax: Double? = nil
    var floweringPeriod: String? = nil
    var fruitingPeriod: String? = nil
}

struct GardenBotanicalProfile: Hashable {
    var family: String?
    var genus: String?
    var strata: String?
    var tags: String?
    var notes: String?
    var imageURL: String?
    var origin: String?
    var plantType: String?
    var morphology: String?
    var culture: String?
    var uses: String?
    var melliferousLevel: String?
    var ornamentalInterest: String?
    var lifespanMin: Int?
    var lifespanMax: Int?
    var heightMin: Double?
    var heightMax: Double?
    var floweringPeriod: String?
    var fruitingPeriod: String?

    static let empty = GardenBotanicalProfile(
        family: nil,
        genus: nil,
        strata: nil,
        tags: nil,
        notes: nil,
        imageURL: nil,
        origin: nil,
        plantType: nil,
        morphology: nil,
        culture: nil,
        uses: nil,
        melliferousLevel: nil,
        ornamentalInterest: nil,
        lifespanMin: nil,
        lifespanMax: nil,
        heightMin: nil,
        heightMax: nil,
        floweringPeriod: nil,
        fruitingPeriod: nil
    )
}

extension SpeciesWriteInput {
    var profile: GardenBotanicalProfile {
        GardenBotanicalProfile(
            family: family,
            genus: genus,
            strata: strata,
            tags: tags,
            notes: notes,
            imageURL: imageURL,
            origin: origin,
            plantType: plantType,
            morphology: morphology,
            culture: culture,
            uses: uses,
            melliferousLevel: melliferousLevel,
            ornamentalInterest: ornamentalInterest,
            lifespanMin: lifespanMin,
            lifespanMax: lifespanMax,
            heightMin: heightMin,
            heightMax: heightMax,
            floweringPeriod: floweringPeriod,
            fruitingPeriod: fruitingPeriod
        )
    }
}

extension SpeciesCommonWriteInput {
    var profile: GardenBotanicalProfile {
        GardenBotanicalProfile(
            family: family,
            genus: genus,
            strata: strata,
            tags: tags,
            notes: notes,
            imageURL: imageURL,
            origin: origin,
            plantType: plantType,
            morphology: morphology,
            culture: culture,
            uses: uses,
            melliferousLevel: melliferousLevel,
            ornamentalInterest: ornamentalInterest,
            lifespanMin: lifespanMin,
            lifespanMax: lifespanMax,
            heightMin: heightMin,
            heightMax: heightMax,
            floweringPeriod: floweringPeriod,
            fruitingPeriod: fruitingPeriod
        )
    }
}

extension CultivarWriteInput {
    var profile: GardenBotanicalProfile {
        GardenBotanicalProfile(
            family: nil,
            genus: nil,
            strata: nil,
            tags: tags,
            notes: notes,
            imageURL: nil,
            origin: origin,
            plantType: plantType,
            morphology: morphology,
            culture: culture,
            uses: uses,
            melliferousLevel: melliferousLevel,
            ornamentalInterest: ornamentalInterest,
            lifespanMin: lifespanMin,
            lifespanMax: lifespanMax,
            heightMin: heightMin,
            heightMax: heightMax,
            floweringPeriod: floweringPeriod,
            fruitingPeriod: fruitingPeriod
        )
    }
}

@dynamicMemberLookup
struct DBColumnNamespace {
    subscript(dynamicMember member: String) -> Column {
        Column(camelCaseToSnakeCase(member))
    }

    private func camelCaseToSnakeCase(_ stringKey: String) -> String {
        guard !stringKey.isEmpty else { return stringKey }

        var words: [Range<String.Index>] = []
        var wordStart = stringKey.startIndex
        var searchRange = stringKey.index(after: wordStart)..<stringKey.endIndex

        while let upperCaseRange = stringKey.rangeOfCharacter(
            from: CharacterSet.uppercaseLetters,
            options: [],
            range: searchRange
        ) {
            let untilUpperCase = wordStart..<upperCaseRange.lowerBound
            words.append(untilUpperCase)

            searchRange = upperCaseRange.lowerBound..<searchRange.upperBound
            guard let lowerCaseRange = stringKey.rangeOfCharacter(
                from: CharacterSet.lowercaseLetters,
                options: [],
                range: searchRange
            ) else {
                wordStart = searchRange.lowerBound
                break
            }

            let nextCharacterAfterCapital = stringKey.index(after: upperCaseRange.lowerBound)
            if lowerCaseRange.lowerBound == nextCharacterAfterCapital {
                wordStart = upperCaseRange.lowerBound
            } else {
                let beforeLowerIndex = stringKey.index(before: lowerCaseRange.lowerBound)
                words.append(upperCaseRange.lowerBound..<beforeLowerIndex)
                wordStart = beforeLowerIndex
            }
            searchRange = lowerCaseRange.upperBound..<searchRange.upperBound
        }

        words.append(wordStart..<searchRange.upperBound)
        return words
            .map { stringKey[$0].lowercased() }
            .joined(separator: "_")
    }
}

protocol SnakeCaseReadableRecord: FetchableRecord, TableRecord {}

extension SnakeCaseReadableRecord {
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy {
        .custom { column in
            ColumnCodingKey(stringValue: snakeCaseToCamelPreservingURL(column))
        }
    }

    static var columns: DBColumnNamespace { DBColumnNamespace() }
}

protocol SnakeCaseMutableRecord: SnakeCaseReadableRecord, MutablePersistableRecord {}

extension SnakeCaseMutableRecord {
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy {
        .convertToSnakeCase
    }
}

private func snakeCaseToCamelPreservingURL(_ column: String) -> String {
    let parts = column.split(separator: "_")
    guard let first = parts.first else { return column }
    let head = String(first).lowercased()
    if parts.count == 1 { return head }
    let tail = parts.dropFirst().map { part -> String in
        let lower = part.lowercased()
        if lower == "url" { return "URL" }
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }
    return ([head] + tail).joined()
}

private struct ColumnCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) { nil }
}

private enum DTOBridge {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { keys in
            let raw = keys.last?.stringValue ?? ""
            return ColumnCodingKey(stringValue: snakeCaseToCamelPreservingURL(raw))
        }
        return decoder
    }

    static func convert<Source: Encodable, Target: Decodable>(
        _ source: Source,
        to type: Target.Type
    ) throws -> Target {
        let data = try makeEncoder().encode(source)
        return try makeDecoder().decode(type, from: data)
    }
}

struct DBSpecies: Codable, SnakeCaseMutableRecord {
    static let databaseTableName = "species"

    var id: Int64?
    var commonName: String?
    var varietyName: String?
    var latinName: String?
    var family: String?
    var genus: String?
    var strata: String?
    var tags: String?
    var notes: String?
    var imageURL: String?
    var origin: String?
    var plantType: String?
    var morphology: String?
    var culture: String?
    var uses: String?
    var melliferousLevel: String?
    var ornamentalInterest: String?
    var lifespanMin: Int?
    var lifespanMax: Int?
    var heightMin: Double?
    var heightMax: Double?
    var envergureMin: Double?
    var envergureMax: Double?
    var floweringPeriod: String?
    var fruitingPeriod: String?
    var varietyNotes: String?
    var uuid: String?
    var updatedAt: String?
    var deleted: Bool

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct DBCultivar: Codable, SnakeCaseMutableRecord {
    static let databaseTableName = "cultivars"

    var id: Int64?
    var speciesId: Int64
    var name: String
    var notes: String?
    var tags: String?
    var origin: String?
    var plantType: String?
    var morphology: String?
    var culture: String?
    var uses: String?
    var melliferousLevel: String?
    var ornamentalInterest: String?
    var lifespanMin: Int?
    var lifespanMax: Int?
    var heightMin: Double?
    var heightMax: Double?
    var floweringPeriod: String?
    var fruitingPeriod: String?
    var uuid: String?
    var updatedAt: String?
    var deleted: Bool

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct DBPlant: Codable, SnakeCaseMutableRecord {
    static let databaseTableName = "plants"

    var id: Int64?
    var speciesId: Int64
    var label: String?
    var lat: Double?
    var lon: Double?
    var zone: String?
    var plantedAt: String?
    var notes: String?
    var imageLocal: String?
    var altitude: Double?
    var tags: String?
    var microSite: String?
    var exposureLocal: String?
    var soilLocal: String?
    var heightCurrent: Double?
    var envergureCurrent: Double?
    var acquisitionType: String?
    var acquisitionSource: String?
    var plantnetObsId: String?
    var status: String?
    var careNotes: String?
    var rootstock: String?
    var uuid: String?
    var updatedAt: String?
    var deleted: Bool
    var varietyId: Int64?

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct DBSyncState: Codable, SnakeCaseMutableRecord {
    static let databaseTableName = "sync_state"

    var tableName: String
    var lastSyncedAt: String?
}

struct DBHive: Codable, SnakeCaseReadableRecord {
    static let databaseTableName = "hives"

    var id: Int64
    var code: String?
    var name: String
    var hiveType: String?
    var locationLabel: String?
    var status: String?
    var beeBreed: String?
    var queenYear: Int?
    var origin: String?
}

struct DBHiveColony: TableRecord {
    static let databaseTableName = "hive_colonies"
}

extension DBSpecies {
    var botanicalProfile: GardenBotanicalProfile {
        get {
            GardenBotanicalProfile(
                family: family,
                genus: genus,
                strata: strata,
                tags: tags,
                notes: notes,
                imageURL: imageURL,
                origin: origin,
                plantType: plantType,
                morphology: morphology,
                culture: culture,
                uses: uses,
                melliferousLevel: melliferousLevel,
                ornamentalInterest: ornamentalInterest,
                lifespanMin: lifespanMin,
                lifespanMax: lifespanMax,
                heightMin: heightMin,
                heightMax: heightMax,
                floweringPeriod: floweringPeriod,
                fruitingPeriod: fruitingPeriod
            )
        }
        set {
            family = newValue.family
            genus = newValue.genus
            strata = newValue.strata
            tags = newValue.tags
            notes = newValue.notes
            imageURL = newValue.imageURL
            origin = newValue.origin
            plantType = newValue.plantType
            morphology = newValue.morphology
            culture = newValue.culture
            uses = newValue.uses
            melliferousLevel = newValue.melliferousLevel
            ornamentalInterest = newValue.ornamentalInterest
            lifespanMin = newValue.lifespanMin
            lifespanMax = newValue.lifespanMax
            heightMin = newValue.heightMin
            heightMax = newValue.heightMax
            floweringPeriod = newValue.floweringPeriod
            fruitingPeriod = newValue.fruitingPeriod
        }
    }
}

extension DBCultivar {
    var botanicalProfile: GardenBotanicalProfile {
        get {
            GardenBotanicalProfile(
                family: nil,
                genus: nil,
                strata: nil,
                tags: tags,
                notes: notes,
                imageURL: nil,
                origin: origin,
                plantType: plantType,
                morphology: morphology,
                culture: culture,
                uses: uses,
                melliferousLevel: melliferousLevel,
                ornamentalInterest: ornamentalInterest,
                lifespanMin: lifespanMin,
                lifespanMax: lifespanMax,
                heightMin: heightMin,
                heightMax: heightMax,
                floweringPeriod: floweringPeriod,
                fruitingPeriod: fruitingPeriod
            )
        }
        set {
            tags = newValue.tags
            notes = newValue.notes
            origin = newValue.origin
            plantType = newValue.plantType
            morphology = newValue.morphology
            culture = newValue.culture
            uses = newValue.uses
            melliferousLevel = newValue.melliferousLevel
            ornamentalInterest = newValue.ornamentalInterest
            lifespanMin = newValue.lifespanMin
            lifespanMax = newValue.lifespanMax
            heightMin = newValue.heightMin
            heightMax = newValue.heightMax
            floweringPeriod = newValue.floweringPeriod
            fruitingPeriod = newValue.fruitingPeriod
        }
    }
}

extension DBPlant {
    static func makeNew(
        from input: PlantWriteInput,
        label: String?,
        updatedAt: String,
        uuid: String = UUID().uuidString
    ) -> DBPlant {
        var record = DBPlant(
            id: nil,
            speciesId: 0,
            label: nil,
            lat: nil,
            lon: nil,
            zone: nil,
            plantedAt: nil,
            notes: nil,
            imageLocal: nil,
            altitude: nil,
            tags: nil,
            microSite: nil,
            exposureLocal: nil,
            soilLocal: nil,
            heightCurrent: nil,
            envergureCurrent: nil,
            acquisitionType: nil,
            acquisitionSource: nil,
            plantnetObsId: nil,
            status: nil,
            careNotes: nil,
            rootstock: nil,
            uuid: uuid,
            updatedAt: updatedAt,
            deleted: false,
            varietyId: nil
        )
        record.applyWriteInput(input, label: label, updatedAt: updatedAt)
        return record
    }

    mutating func applyWriteInput(
        _ input: PlantWriteInput,
        label: String?,
        updatedAt: String
    ) {
        speciesId = Int64(input.speciesId)
        varietyId = input.varietyId.map(Int64.init)
        self.label = label
        zone = input.zone
        notes = input.notes
        status = input.status
        microSite = input.microSite
        exposureLocal = input.exposureLocal
        soilLocal = input.soilLocal
        acquisitionType = input.acquisitionType
        acquisitionSource = input.acquisitionSource
        careNotes = input.careNotes
        heightCurrent = input.heightCurrent
        envergureCurrent = input.envergureCurrent
        lat = input.latitude
        lon = input.longitude
        self.updatedAt = updatedAt
    }
}

extension DBSpecies {
    static func makeNew(
        from input: SpeciesWriteInput,
        updatedAt: String,
        uuid: String = UUID().uuidString
    ) -> DBSpecies {
        var record = DBSpecies(
            id: nil,
            commonName: nil,
            varietyName: nil,
            latinName: nil,
            family: nil,
            genus: nil,
            strata: nil,
            tags: nil,
            notes: nil,
            imageURL: nil,
            origin: nil,
            plantType: nil,
            morphology: nil,
            culture: nil,
            uses: nil,
            melliferousLevel: nil,
            ornamentalInterest: nil,
            lifespanMin: nil,
            lifespanMax: nil,
            heightMin: nil,
            heightMax: nil,
            envergureMin: nil,
            envergureMax: nil,
            floweringPeriod: nil,
            fruitingPeriod: nil,
            varietyNotes: nil,
            uuid: uuid,
            updatedAt: updatedAt,
            deleted: false
        )
        record.applyWriteInput(input, updatedAt: updatedAt)
        return record
    }

    mutating func applyWriteInput(_ input: SpeciesWriteInput, updatedAt: String) {
        commonName = input.commonName
        varietyName = input.varietyName
        latinName = input.latinName
        botanicalProfile = input.profile
        envergureMin = input.envergureMin
        envergureMax = input.envergureMax
        varietyNotes = input.varietyNotes
        self.updatedAt = updatedAt
    }

    mutating func applyCommonWriteInput(_ input: SpeciesCommonWriteInput, updatedAt: String) {
        commonName = input.commonName
        botanicalProfile = input.profile
        envergureMin = input.envergureMin
        envergureMax = input.envergureMax
        self.updatedAt = updatedAt
    }
}

extension DBCultivar {
    static func makeNew(
        speciesId: Int,
        name: String,
        input: CultivarWriteInput,
        updatedAt: String,
        uuid: String = UUID().uuidString
    ) -> DBCultivar {
        var record = DBCultivar(
            id: nil,
            speciesId: Int64(speciesId),
            name: name,
            notes: nil,
            tags: nil,
            origin: nil,
            plantType: nil,
            morphology: nil,
            culture: nil,
            uses: nil,
            melliferousLevel: nil,
            ornamentalInterest: nil,
            lifespanMin: nil,
            lifespanMax: nil,
            heightMin: nil,
            heightMax: nil,
            floweringPeriod: nil,
            fruitingPeriod: nil,
            uuid: uuid,
            updatedAt: updatedAt,
            deleted: false
        )
        record.applyWriteInput(name: name, input: input, updatedAt: updatedAt)
        return record
    }

    mutating func applyWriteInput(
        name: String,
        input: CultivarWriteInput,
        updatedAt: String
    ) {
        self.name = name
        botanicalProfile = input.profile
        self.updatedAt = updatedAt
    }
}

extension DBSpecies {
    init(dto: SpeciesDTO) {
        do {
            self = try DTOBridge.convert(dto, to: DBSpecies.self)
        } catch {
            preconditionFailure("SpeciesDTO -> DBSpecies conversion failed: \(error)")
        }
    }

    func asDTO() -> SpeciesDTO {
        SpeciesDTO(
            id: Int(id ?? 0),
            commonName: commonName,
            varietyName: varietyName,
            latinName: latinName,
            family: family,
            genus: genus,
            strata: strata,
            tags: tags,
            notes: notes,
            imageURL: imageURL,
            origin: origin,
            plantType: plantType,
            morphology: morphology,
            culture: culture,
            uses: uses,
            melliferousLevel: melliferousLevel,
            ornamentalInterest: ornamentalInterest,
            lifespanMin: FlexibleInt(value: lifespanMin),
            lifespanMax: FlexibleInt(value: lifespanMax),
            heightMin: FlexibleDouble(value: heightMin),
            heightMax: FlexibleDouble(value: heightMax),
            envergureMin: FlexibleDouble(value: envergureMin),
            envergureMax: FlexibleDouble(value: envergureMax),
            floweringPeriod: floweringPeriod,
            fruitingPeriod: fruitingPeriod,
            varietyNotes: varietyNotes,
            uuid: uuid,
            updatedAt: updatedAt,
            deleted: deleted
        )
    }

    func asTaxon(kind: GardenTaxonKind = .species) -> GardenTaxon {
        GardenTaxon(
            id: Int(id ?? 0),
            kind: kind,
            speciesId: Int(id ?? 0),
            commonName: commonName ?? (kind == .speciesDetail ? "—" : ""),
            varietyName: varietyName ?? "",
            latinName: latinName ?? (kind == .speciesDetail ? "—" : ""),
            profile: botanicalProfile,
            spreadMin: envergureMin,
            spreadMax: envergureMax,
            varietyNotes: varietyNotes,
            uuid: uuid,
            updatedAt: updatedAt,
            deleted: deleted,
            cultivarCount: 0,
            plantCount: 0
        )
    }

    static func asBaseTaxon(
        latinName: String,
        records: [DBSpecies],
        plantCountBySpeciesID: [Int64: Int],
        cultivarCountBySpeciesID: [Int64: Int]
    ) -> GardenTaxon {
        let ids = records.compactMap(\.id)
        let speciesId = ids.min().map(Int.init) ?? 0
        let plantCount = ids.reduce(0) { partial, id in
            partial + (plantCountBySpeciesID[id] ?? 0)
        }
        let cultivarCount = ids.reduce(0) { partial, id in
            partial + (cultivarCountBySpeciesID[id] ?? 0)
        }

        let profile = GardenBotanicalProfile(
            family: firstNonEmpty(records.map(\.family)),
            genus: firstNonEmpty(records.map(\.genus)),
            strata: firstNonEmpty(records.map(\.strata)),
            tags: firstNonEmpty(records.map(\.tags)),
            notes: firstNonEmpty(records.map(\.notes)),
            imageURL: firstNonEmpty(records.map(\.imageURL)),
            origin: firstNonEmpty(records.map(\.origin)),
            plantType: firstNonEmpty(records.map(\.plantType)),
            morphology: firstNonEmpty(records.map(\.morphology)),
            culture: firstNonEmpty(records.map(\.culture)),
            uses: firstNonEmpty(records.map(\.uses)),
            melliferousLevel: firstNonEmpty(records.map(\.melliferousLevel)),
            ornamentalInterest: firstNonEmpty(records.map(\.ornamentalInterest)),
            lifespanMin: records.compactMap(\.lifespanMin).min(),
            lifespanMax: records.compactMap(\.lifespanMax).max(),
            heightMin: records.compactMap(\.heightMin).min(),
            heightMax: records.compactMap(\.heightMax).max(),
            floweringPeriod: firstNonEmpty(records.map(\.floweringPeriod)),
            fruitingPeriod: firstNonEmpty(records.map(\.fruitingPeriod))
        )

        return GardenTaxon(
            id: speciesId,
            kind: .speciesBase,
            speciesId: speciesId,
            commonName: firstNonEmpty(records.map(\.commonName), fallback: "—"),
            varietyName: "",
            latinName: latinName.isEmpty ? "—" : latinName,
            profile: profile,
            spreadMin: records.compactMap(\.envergureMin).min(),
            spreadMax: records.compactMap(\.envergureMax).max(),
            varietyNotes: firstNonEmpty(records.map(\.varietyNotes)),
            uuid: firstNonEmpty(records.map(\.uuid)),
            updatedAt: firstNonEmpty(records.map(\.updatedAt)),
            deleted: false,
            cultivarCount: cultivarCount,
            plantCount: plantCount
        )
    }

    private static func firstNonEmpty(_ values: [String?], fallback: String) -> String {
        for value in values {
            guard let value else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return value
            }
        }
        return fallback
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        for value in values {
            guard let value else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return value
            }
        }
        return nil
    }
}

extension DBCultivar {
    init(dto: CultivarDTO) {
        do {
            self = try DTOBridge.convert(dto, to: DBCultivar.self)
        } catch {
            preconditionFailure("CultivarDTO -> DBCultivar conversion failed: \(error)")
        }
    }

    func asDTO() -> CultivarDTO {
        CultivarDTO(
            id: Int(id ?? 0),
            speciesId: Int(speciesId),
            name: name,
            notes: notes,
            tags: tags,
            origin: origin,
            plantType: plantType,
            morphology: morphology,
            culture: culture,
            uses: uses,
            melliferousLevel: melliferousLevel,
            ornamentalInterest: ornamentalInterest,
            lifespanMin: FlexibleInt(value: lifespanMin),
            lifespanMax: FlexibleInt(value: lifespanMax),
            heightMin: FlexibleDouble(value: heightMin),
            heightMax: FlexibleDouble(value: heightMax),
            floweringPeriod: floweringPeriod,
            fruitingPeriod: fruitingPeriod,
            uuid: uuid,
            updatedAt: updatedAt,
            deleted: deleted
        )
    }

    func asTaxon(plantCount: Int) -> GardenTaxon {
        GardenTaxon(
            id: Int(id ?? 0),
            kind: .cultivar,
            speciesId: Int(speciesId),
            commonName: "",
            varietyName: name,
            latinName: "",
            profile: botanicalProfile,
            spreadMin: nil,
            spreadMax: nil,
            varietyNotes: nil,
            uuid: uuid,
            updatedAt: updatedAt,
            deleted: deleted,
            cultivarCount: 0,
            plantCount: plantCount
        )
    }
}

extension DBPlant {
    init(dto: PlantDTO) {
        do {
            self = try DTOBridge.convert(dto, to: DBPlant.self)
        } catch {
            preconditionFailure("PlantDTO -> DBPlant conversion failed: \(error)")
        }
    }

    func asDTO() -> PlantDTO {
        PlantDTO(
            id: Int(id ?? 0),
            speciesId: Int(speciesId),
            label: label,
            lat: lat,
            lon: lon,
            zone: zone,
            plantedAt: plantedAt,
            notes: notes,
            imageLocal: imageLocal,
            altitude: altitude,
            tags: tags,
            microSite: microSite,
            exposureLocal: exposureLocal,
            soilLocal: soilLocal,
            heightCurrent: heightCurrent,
            envergureCurrent: envergureCurrent,
            acquisitionType: acquisitionType,
            acquisitionSource: acquisitionSource,
            plantnetObsId: plantnetObsId,
            status: status,
            careNotes: careNotes,
            rootstock: rootstock,
            uuid: uuid,
            updatedAt: updatedAt,
            deleted: deleted,
            varietyId: varietyId.map(Int.init)
        )
    }

    func asGardenPlant(species: DBSpecies, cultivar: DBCultivar?) -> GardenPlant {
        GardenPlant(
            id: Int(id ?? 0),
            uuid: uuid,
            speciesID: Int(speciesId),
            siteIlotID: nil,
            siteIlotCode: nil,
            siteIlotName: nil,
            label: label,
            lat: lat,
            lon: lon,
            zone: zone,
            plantedAt: plantedAt,
            notes: notes,
            imageLocal: imageLocal,
            altitude: altitude,
            tags: tags,
            microSite: microSite,
            exposureLocal: exposureLocal,
            soilLocal: soilLocal,
            heightCurrent: heightCurrent,
            spreadCurrent: envergureCurrent,
            acquisitionType: acquisitionType,
            acquisitionSource: acquisitionSource,
            plantnetObsID: plantnetObsId,
            status: status,
            careNotes: careNotes,
            rootstock: rootstock,
            commonName: species.commonName ?? "—",
            varietyName: cultivar?.name ?? species.varietyName,
            latinName: species.latinName ?? "—",
            family: species.family,
            genus: species.genus,
            strata: species.strata,
            speciesTags: species.tags,
            speciesNotes: species.notes,
            varietyNotes: cultivar?.notes ?? species.varietyNotes,
            cultivarTags: cultivar?.tags,
            cultivarOrigin: cultivar?.origin,
            cultivarPlantType: cultivar?.plantType,
            cultivarMorphology: cultivar?.morphology,
            cultivarCulture: cultivar?.culture,
            cultivarUses: cultivar?.uses,
            cultivarMelliferousLevel: cultivar?.melliferousLevel,
            cultivarOrnamentalInterest: cultivar?.ornamentalInterest,
            cultivarLifespanMin: cultivar?.lifespanMin,
            cultivarLifespanMax: cultivar?.lifespanMax,
            cultivarHeightMin: cultivar?.heightMin,
            cultivarHeightMax: cultivar?.heightMax,
            cultivarFloweringPeriod: cultivar?.floweringPeriod,
            cultivarFruitingPeriod: cultivar?.fruitingPeriod,
            speciesImageURL: species.imageURL,
            origin: species.origin,
            plantType: species.plantType,
            morphology: species.morphology,
            culture: species.culture,
            uses: species.uses,
            melliferousLevel: species.melliferousLevel,
            ornamentalInterest: species.ornamentalInterest,
            lifespanMin: species.lifespanMin,
            lifespanMax: species.lifespanMax,
            speciesHeightMin: species.heightMin,
            speciesHeightMax: species.heightMax,
            speciesSpreadMin: species.envergureMin,
            speciesSpreadMax: species.envergureMax,
            speciesFloweringPeriod: species.floweringPeriod,
            speciesFruitingPeriod: species.fruitingPeriod
        )
    }
}

extension DBHive {
    func asGardenHive() -> GardenHive {
        GardenHive(
            id: Int(id),
            code: code,
            name: name,
            hiveType: hiveType,
            locationLabel: locationLabel,
            status: status,
            beeBreed: beeBreed,
            queenYear: queenYear,
            origin: origin
        )
    }
}

struct GardenPlant: Identifiable, Hashable {
    let id: Int
    let uuid: String?
    let speciesID: Int
    let siteIlotID: String?
    let siteIlotCode: String?
    let siteIlotName: String?
    let label: String?
    let lat: Double?
    let lon: Double?
    let zone: String?
    let plantedAt: String?
    let notes: String?
    let imageLocal: String?
    let altitude: Double?
    let tags: String?
    let microSite: String?
    let exposureLocal: String?
    let soilLocal: String?
    let heightCurrent: Double?
    let spreadCurrent: Double?
    let acquisitionType: String?
    let acquisitionSource: String?
    let plantnetObsID: String?
    let status: String?
    let careNotes: String?
    let rootstock: String?

    let commonName: String
    let varietyName: String?
    let latinName: String
    let family: String?
    let genus: String?
    let strata: String?
    let speciesTags: String?
    let speciesNotes: String?
    let varietyNotes: String?
    let cultivarTags: String?
    let cultivarOrigin: String?
    let cultivarPlantType: String?
    let cultivarMorphology: String?
    let cultivarCulture: String?
    let cultivarUses: String?
    let cultivarMelliferousLevel: String?
    let cultivarOrnamentalInterest: String?
    let cultivarLifespanMin: Int?
    let cultivarLifespanMax: Int?
    let cultivarHeightMin: Double?
    let cultivarHeightMax: Double?
    let cultivarFloweringPeriod: String?
    let cultivarFruitingPeriod: String?
    let speciesImageURL: String?
    let origin: String?
    let plantType: String?
    let morphology: String?
    let culture: String?
    let uses: String?
    let melliferousLevel: String?
    let ornamentalInterest: String?
    let lifespanMin: Int?
    let lifespanMax: Int?
    let speciesHeightMin: Double?
    let speciesHeightMax: Double?
    let speciesSpreadMin: Double?
    let speciesSpreadMax: Double?
    let speciesFloweringPeriod: String?
    let speciesFruitingPeriod: String?

    var tagsArray: [String] {
        guard let tags, !tags.isEmpty else { return [] }
        return tags
            .split(whereSeparator: { ",;|".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct GardenCoordinate: Hashable, Codable {
    let latitude: Double
    let longitude: Double

    var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct GardenSiteIlot: Identifiable, Hashable {
    let id: String
    let siteID: String
    let code: String
    let name: String?
    let polygons: [[GardenCoordinate]]
    let centroid: GardenCoordinate?
    let areaM2: Double?
    let sunExposure: String?
    let humidityProfile: String?
    let pedology: String?
    let drainageProfile: String?
    let frostExposure: String?
    let managementIntensity: String?
    let slopePct: Double?
    let aspect: String?
    let windExposure: String?
    let notes: String?
}

enum GardenTaxonKind: String, Hashable {
    case species
    case speciesBase
    case speciesDetail
    case cultivar
}

struct GardenTaxon: Identifiable, Hashable {
    let id: Int
    var kind: GardenTaxonKind
    var speciesId: Int?
    var commonName: String
    var varietyName: String
    var latinName: String
    var profile: GardenBotanicalProfile
    var spreadMin: Double?
    var spreadMax: Double?
    var varietyNotes: String?
    var uuid: String?
    var updatedAt: String?
    var deleted: Bool
    var cultivarCount: Int
    var plantCount: Int

    var family: String? {
        get { profile.family }
        set { profile.family = newValue }
    }
    var genus: String? {
        get { profile.genus }
        set { profile.genus = newValue }
    }
    var strata: String? {
        get { profile.strata }
        set { profile.strata = newValue }
    }
    var tags: String? {
        get { profile.tags }
        set { profile.tags = newValue }
    }
    var notes: String? {
        get { profile.notes }
        set { profile.notes = newValue }
    }
    var imageURL: String? {
        get { profile.imageURL }
        set { profile.imageURL = newValue }
    }
    var origin: String? {
        get { profile.origin }
        set { profile.origin = newValue }
    }
    var plantType: String? {
        get { profile.plantType }
        set { profile.plantType = newValue }
    }
    var morphology: String? {
        get { profile.morphology }
        set { profile.morphology = newValue }
    }
    var culture: String? {
        get { profile.culture }
        set { profile.culture = newValue }
    }
    var uses: String? {
        get { profile.uses }
        set { profile.uses = newValue }
    }
    var melliferousLevel: String? {
        get { profile.melliferousLevel }
        set { profile.melliferousLevel = newValue }
    }
    var ornamentalInterest: String? {
        get { profile.ornamentalInterest }
        set { profile.ornamentalInterest = newValue }
    }
    var lifespanMin: Int? {
        get { profile.lifespanMin }
        set { profile.lifespanMin = newValue }
    }
    var lifespanMax: Int? {
        get { profile.lifespanMax }
        set { profile.lifespanMax = newValue }
    }
    var heightMin: Double? {
        get { profile.heightMin }
        set { profile.heightMin = newValue }
    }
    var heightMax: Double? {
        get { profile.heightMax }
        set { profile.heightMax = newValue }
    }
    var floweringPeriod: String? {
        get { profile.floweringPeriod }
        set { profile.floweringPeriod = newValue }
    }
    var fruitingPeriod: String? {
        get { profile.fruitingPeriod }
        set { profile.fruitingPeriod = newValue }
    }
}

struct GardenTaxonDetailData {
    let base: GardenTaxon
    let cultivars: [GardenTaxon]
    let plants: [GardenPlant]
}


struct GardenHive: Identifiable {
    let id: Int
    let code: String?
    let name: String
    let hiveType: String?
    let locationLabel: String?
    let status: String?
    let beeBreed: String?
    let queenYear: Int?
    let origin: String?
}

enum GardenDeleteSpeciesResult {
    case success
    case linkedToCultivars
    case linkedToPlants
    case failure
}

struct JardinStats {
    var plantCount: Int
    var speciesCount: Int
    var zoneCount: Int
    var hiveCount: Int
    var colonyCount: Int

    static let empty = JardinStats(
        plantCount: 0,
        speciesCount: 0,
        zoneCount: 0,
        hiveCount: 0,
        colonyCount: 0
    )
}
