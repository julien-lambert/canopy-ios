import Foundation

enum CanopyUIAdapters {
    static func toGardenTaxa(
        speciesRecords: [CanopyLocalSpeciesRecord],
        cultivarRecords: [CanopyLocalCultivarRecord],
        individuals: [CanopyLocalIndividualRecord]
    ) -> [GardenTaxon] {
        let activeCultivars = cultivarRecords.filter { $0.deletedAt == nil }
        let plantCountBySpecies: [String: Int] = Dictionary(
            grouping: individuals.compactMap { record in
                guard record.deletedAt == nil, let speciesID = record.speciesPrivateID else { return nil }
                return speciesID
            },
            by: { $0 }
        ).mapValues(\.count)
        let cultivarCountBySpecies: [String: Int] = Dictionary(
            grouping: activeCultivars.compactMap(\.speciesPrivateID),
            by: { $0 }
        ).mapValues(\.count)

        return speciesRecords
            .filter { $0.deletedAt == nil }
            .map { species in
                GardenTaxon(
                    id: stableIntID(from: species.remoteID),
                    kind: .speciesBase,
                    speciesId: nil,
                    commonName: fallbackCommonName(for: species),
                    varietyName: "",
                    latinName: fallbackLatinName(for: species),
                    profile: GardenBotanicalProfile(
                        family: species.family,
                        genus: species.genus,
                        strata: species.strata,
                        tags: joinTags(from: species.tagsJSON),
                        notes: species.notes,
                        imageURL: species.imageURL,
                        origin: species.origin,
                        plantType: species.plantType,
                        morphology: species.morphology,
                        culture: species.culture,
                        uses: species.uses,
                        melliferousLevel: species.melliferousLevel,
                        ornamentalInterest: species.ornamentalInterest,
                        lifespanMin: species.lifespanMin,
                        lifespanMax: species.lifespanMax,
                        heightMin: species.heightMin,
                        heightMax: species.heightMax,
                        floweringPeriod: species.floweringPeriod,
                        fruitingPeriod: species.fruitingPeriod
                    ),
                    spreadMin: species.envergureMin,
                    spreadMax: species.envergureMax,
                    varietyNotes: nil,
                    uuid: species.remoteID,
                    updatedAt: species.updatedAt,
                    deleted: false,
                    cultivarCount: cultivarCountBySpecies[species.remoteID] ?? 0,
                    plantCount: plantCountBySpecies[species.remoteID] ?? 0
                )
            }
            .sorted { lhs, rhs in
                lhs.commonName.localizedCaseInsensitiveCompare(rhs.commonName) == .orderedAscending
            }
    }

    static func toGardenPlants(
        individuals: [CanopyLocalIndividualRecord],
        speciesRecords: [CanopyLocalSpeciesRecord],
        cultivarRecords: [CanopyLocalCultivarRecord]
    ) -> [GardenPlant] {
        let speciesByRemoteID = Dictionary(uniqueKeysWithValues: speciesRecords.map { ($0.remoteID, $0) })
        let cultivarByRemoteID = Dictionary(uniqueKeysWithValues: cultivarRecords.map { ($0.remoteID, $0) })

        return individuals
            .filter { $0.deletedAt == nil }
            .map { plant in
                let species = plant.speciesPrivateID.flatMap { speciesByRemoteID[$0] }
                let cultivar = plant.cultivarID.flatMap { cultivarByRemoteID[$0] }
                let metadata = decodeMetadata(from: plant.metadataJSON)
                let commonName = species.flatMap { fallbackCommonName(for: $0) } ?? "Espèce"
                let latinName = species.flatMap { fallbackLatinName(for: $0) } ?? commonName
                let tags = species.flatMap { joinTags(from: $0.tagsJSON) }

                return GardenPlant(
                    id: stableIntID(from: plant.remoteID),
                    uuid: plant.remoteID,
                    speciesID: species.map { stableIntID(from: $0.remoteID) } ?? 0,
                    siteIlotID: plant.siteIlotID,
                    label: plant.label ?? plant.code,
                    lat: plant.locationLat,
                    lon: plant.locationLng,
                    zone: plant.zone,
                    plantedAt: plant.plantedAt,
                    notes: plant.notes,
                    imageLocal: nil,
                    altitude: plant.locationAlt,
                    tags: tags,
                    microSite: metadata["micro_site"]?.stringValue,
                    exposureLocal: metadata["exposure_local"]?.stringValue,
                    soilLocal: metadata["soil_local"]?.stringValue,
                    heightCurrent: plant.heightCurrent ?? metadata["height_current"]?.doubleValue,
                    spreadCurrent: plant.envergureCurrent ?? metadata["envergure_current"]?.doubleValue,
                    acquisitionType: metadata["acquisition_type"]?.stringValue,
                    acquisitionSource: metadata["acquisition_source"]?.stringValue,
                    plantnetObsID: nil,
                    status: normalizeStatus(plant.status),
                    careNotes: metadata["care_notes"]?.stringValue,
                    rootstock: nil,
                    commonName: commonName,
                    varietyName: cultivar?.name,
                    latinName: latinName,
                    family: species?.family,
                    genus: species?.genus,
                    strata: species?.strata,
                    speciesTags: tags,
                    speciesNotes: species?.notes,
                    varietyNotes: cultivar?.notes,
                    cultivarTags: joinTags(from: cultivar?.tagsJSON),
                    cultivarOrigin: cultivar?.origin,
                    cultivarPlantType: nil,
                    cultivarMorphology: nil,
                    cultivarCulture: nil,
                    cultivarUses: nil,
                    cultivarMelliferousLevel: nil,
                    cultivarOrnamentalInterest: nil,
                    cultivarLifespanMin: nil,
                    cultivarLifespanMax: nil,
                    cultivarHeightMin: nil,
                    cultivarHeightMax: nil,
                    cultivarFloweringPeriod: nil,
                    cultivarFruitingPeriod: nil,
                    speciesImageURL: plant.imageURL ?? cultivar?.imageURL ?? species?.imageURL,
                    origin: species?.origin,
                    plantType: species?.plantType,
                    morphology: species?.morphology,
                    culture: species?.culture,
                    uses: species?.uses,
                    melliferousLevel: species?.melliferousLevel,
                    ornamentalInterest: species?.ornamentalInterest,
                    lifespanMin: species?.lifespanMin,
                    lifespanMax: species?.lifespanMax,
                    speciesHeightMin: species?.heightMin,
                    speciesHeightMax: species?.heightMax,
                    speciesSpreadMin: species?.envergureMin,
                    speciesSpreadMax: species?.envergureMax,
                    speciesFloweringPeriod: species?.floweringPeriod,
                    speciesFruitingPeriod: species?.fruitingPeriod
                )
            }
            .sorted { lhs, rhs in
                (lhs.label ?? lhs.commonName).localizedCaseInsensitiveCompare(rhs.label ?? rhs.commonName) == .orderedAscending
            }
    }

    static func toGardenCultivars(
        cultivars: [CanopyLocalCultivarRecord],
        speciesID: Int,
        plantCountByCultivar: [String: Int] = [:]
    ) -> [GardenTaxon] {
        cultivars
            .filter { $0.deletedAt == nil }
            .map { cultivar in
                GardenTaxon(
                    id: stableIntID(from: cultivar.remoteID),
                    kind: .cultivar,
                    speciesId: speciesID,
                    commonName: "",
                    varietyName: cultivar.name,
                    latinName: "",
                    profile: GardenBotanicalProfile(
                        family: nil,
                        genus: nil,
                        strata: nil,
                        tags: joinTags(from: cultivar.tagsJSON),
                        notes: cultivar.notes,
                        imageURL: cultivar.imageURL,
                        origin: cultivar.origin,
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
                    ),
                    spreadMin: nil,
                    spreadMax: nil,
                    varietyNotes: cultivar.notes,
                    uuid: cultivar.remoteID,
                    updatedAt: cultivar.updatedAt,
                    deleted: false,
                    cultivarCount: 0,
                    plantCount: plantCountByCultivar[cultivar.remoteID] ?? 0
                )
            }
            .sorted { lhs, rhs in
                lhs.varietyName.localizedCaseInsensitiveCompare(rhs.varietyName) == .orderedAscending
            }
    }

    private static func fallbackCommonName(for species: CanopyLocalSpeciesRecord) -> String {
        let value = species.commonName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value, !value.isEmpty { return value }
        return fallbackLatinName(for: species)
    }

    private static func fallbackLatinName(for species: CanopyLocalSpeciesRecord) -> String {
        let value = species.latinName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value, !value.isEmpty { return value }
        return "Espèce"
    }

    private static func joinTags(from rawJSON: String?) -> String? {
        guard
            let rawJSON,
            let data = rawJSON.data(using: .utf8),
            let list = try? JSONDecoder().decode([String].self, from: data)
        else {
            return nil
        }
        let cleaned = list
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return cleaned.isEmpty ? nil : cleaned.joined(separator: ", ")
    }

    private static func normalizeStatus(_ raw: String) -> String {
        switch raw {
        case "plante":
            return "planté"
        case "a_placer":
            return "à_placer"
        case "mort":
            return "mort"
        case "retire":
            return "retiré"
        default:
            return raw
        }
    }

    private static func decodeMetadata(from raw: String?) -> [String: CanopyJSONValue] {
        guard
            let raw,
            let data = raw.data(using: .utf8),
            let object = try? JSONDecoder().decode([String: CanopyJSONValue].self, from: data)
        else {
            return [:]
        }
        return object
    }

    private static func stableIntID(from raw: String) -> Int {
        var hash: UInt32 = 2_166_136_261
        for byte in raw.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return Int(hash & 0x7FFF_FFFF)
    }
}
