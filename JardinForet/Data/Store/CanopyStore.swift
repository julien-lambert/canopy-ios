//
//  Untitled.swift
//  JardinForet
//
//  Created by Julien Lambert on 16/11/2025.
//

import Foundation
import MapKit

final class CanopyStore: ObservableObject {
    enum DeleteCultivarResult {
        case success
        case linkedToPlants
        case failure
    }

    @Published var plants: [GardenPlant] = []
    @Published var species: [GardenTaxon] = []
    @Published private(set) var siteIlots: [GardenSiteIlot] = []
    @Published private(set) var mapTerrainPolygons: [[CLLocationCoordinate2D]] = []
    @Published private(set) var mapIlotPolygons: [[CLLocationCoordinate2D]] = []
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var lastSyncMessage: String?
    private let localDB: CanopyLocalDatabase?
    private let syncEngine: CanopySyncEngine?
    private var syncTask: Task<Void, Never>?
    private var deferredMapVisibilitySyncTask: Task<Void, Never>?
    private var didStartSyncSession = false
    private var isRepairingMapVisibilityDefaults = false

    /// Species/individuals mutations are available on the local Canopy projection.
    var canMutateSpeciesAndIndividuals: Bool { localDB != nil }

    /// Cultivar mutations are available on the local Canopy projection.
    var canMutateCultivars: Bool { localDB != nil }

    var preferredTerrainCoordinate: CLLocationCoordinate2D {
        terrainDefaultCoordinate()
    }

    init() {
        self.localDB = try? CanopyLocalDatabase()
        if self.localDB == nil {
            AppLog.warning("Base locale Canopy indisponible: lecture locale vide tant que la base n'est pas initialisable.", category: .database)
        }
        if let localDB {
            self.syncEngine = CanopySyncEngine(localDB: localDB)
        } else {
            self.syncEngine = nil
        }
        AppLog.info("CanopyStore init", category: .sync)
        loadLocalData()
        loadLocalSpecies()
    }

    func startSyncSession(force: Bool = false, refreshImages: Bool = false) {
        if !force, didStartSyncSession {
            return
        }
        didStartSyncSession = true
        syncWithSupabase(force: force, refreshImages: refreshImages)
    }

    @discardableResult
    private func loadLocalSnapshot() -> Bool {
        guard let localDB else {
            return false
        }

        do {
            let siteID = try localDB.currentSiteID()
            let speciesRecords = try localDB.fetchSpeciesPrivateActive(siteID: siteID)
            let cultivarRecords = try localDB.fetchCultivarsActive(siteID: siteID)
            let individualRecords = try localDB.fetchIndividualsActive(siteID: siteID)
            let siteRecord: CanopyLocalSiteRecord?
            if let siteID, !siteID.isEmpty {
                siteRecord = try localDB.fetchSiteRecord(remoteID: siteID)
            } else {
                siteRecord = nil
            }
            let siteIlotRecords = try localDB.fetchSiteIlotsActive(siteID: siteID)
            let localSpecies = CanopyUIAdapters.toGardenTaxa(
                speciesRecords: speciesRecords,
                cultivarRecords: cultivarRecords,
                individuals: individualRecords
            )
            let localPlants = CanopyUIAdapters.toGardenPlants(
                individuals: individualRecords,
                speciesRecords: speciesRecords,
                cultivarRecords: cultivarRecords
            )
            let localSiteIlots = siteIlotRecords.map(Self.makeGardenSiteIlot)
            let terrainPolygons = Self.geometryPolygons(from: siteRecord?.geomJSON)
            let ilotPolygons = localSiteIlots.flatMap { ilot in
                ilot.polygons.map { polygon in
                    polygon.map(\.clLocationCoordinate)
                }
            }

            species = localSpecies
            plants = localPlants
            siteIlots = localSiteIlots
            mapTerrainPolygons = terrainPolygons
            mapIlotPolygons = ilotPolygons
            return true
        } catch {
            AppLog.error("loadLocalSnapshot: \(error)", category: .database)
            return false
        }
    }

    private func roundedCoordinate(_ value: Double, decimals: Int = 6) -> Double {
        let scale = pow(10.0, Double(decimals))
        return (value * scale).rounded() / scale
    }

    func loadLocalData() {
        let loaded = loadLocalSnapshot()
        if loaded {
            AppLog.info("loadLocalData via Canopy local (\(plants.count) individus)", category: .sync)
            repairMapVisibilityDefaultsIfNeeded()
        } else {
            AppLog.warning("loadLocalData: snapshot local indisponible", category: .sync)
            plants = []
            siteIlots = []
            mapTerrainPolygons = []
            mapIlotPolygons = []
        }
    }

    func loadLocalSpecies() {
        let loaded = loadLocalSnapshot()
        if loaded {
            AppLog.info("loadLocalSpecies via Canopy local (\(species.count) espèces)", category: .sync)
        } else {
            AppLog.warning("loadLocalSpecies: snapshot local indisponible", category: .sync)
            species = []
        }
    }

    private func repairMapVisibilityDefaultsIfNeeded() {
        guard !isRepairingMapVisibilityDefaults, localDB != nil else {
            return
        }

        let terrainFallback = terrainDefaultCoordinate()
        var repairs: [(plant: GardenPlant, input: PlantWriteInput, reasons: [String])] = []
        repairs.reserveCapacity(plants.count)

        for plant in plants {
            guard shouldEnsureMapVisibility(for: plant) else { continue }

            let needsSpread = needsDefaultSpread(for: plant)
            let needsCoordinate = needsTerrainCoordinateRepair(for: plant)
            guard needsSpread || needsCoordinate else { continue }

            let latitude = needsCoordinate ? roundedCoordinate(terrainFallback.latitude) : plant.lat
            let longitude = needsCoordinate ? roundedCoordinate(terrainFallback.longitude) : plant.lon
            let spread = needsSpread ? MapVisibilityDefaults.defaultCanopyDiameterMeters : plant.spreadCurrent

            var reasons: [String] = []
            if needsSpread {
                reasons.append("spread_default_2m")
            }
            if needsCoordinate {
                reasons.append("terrain_centroid")
            }

            repairs.append((
                plant: plant,
                input: PlantWriteInput(
                    speciesId: plant.speciesID,
                    varietyId: nil,
                    zone: plant.zone,
                    notes: plant.notes,
                    status: plant.status,
                    microSite: plant.microSite,
                    exposureLocal: plant.exposureLocal,
                    soilLocal: plant.soilLocal,
                    acquisitionType: plant.acquisitionType,
                    acquisitionSource: plant.acquisitionSource,
                    careNotes: plant.careNotes,
                    heightCurrent: plant.heightCurrent,
                    envergureCurrent: spread,
                    latitude: latitude,
                    longitude: longitude
                ),
                reasons: reasons
            ))
        }

        guard !repairs.isEmpty else {
            return
        }

        isRepairingMapVisibilityDefaults = true
        defer { isRepairingMapVisibilityDefaults = false }

        do {
            var spreadBackfills = 0
            var coordinateBackfills = 0

            for repair in repairs {
                if repair.reasons.contains("spread_default_2m") {
                    spreadBackfills += 1
                }
                if repair.reasons.contains("terrain_centroid") {
                    coordinateBackfills += 1
                }
                try updatePlantRecord(repair.plant, input: repair.input)
            }

            _ = loadLocalSnapshot()
            AppLog.info(
                "Map visibility defaults repaired for \(repairs.count) individus (spread=\(spreadBackfills), coords=\(coordinateBackfills))",
                category: .database
            )
            if didStartSyncSession {
                scheduleMapVisibilityRepairSync()
            }
        } catch {
            AppLog.error("Erreur repairMapVisibilityDefaultsIfNeeded: \(error)", category: .database)
        }
    }

    private func shouldEnsureMapVisibility(for plant: GardenPlant) -> Bool {
        shouldAssignTerrainCoordinate(for: plant) || plant.lat != nil || plant.lon != nil
    }

    private func shouldAssignTerrainCoordinate(for plant: GardenPlant) -> Bool {
        switch normalizedVisibilityStatus(plant.status) {
        case "plante", "malade", "a placer", "a deplacer", "mort", "":
            return true
        default:
            return false
        }
    }

    private func needsDefaultSpread(for plant: GardenPlant) -> Bool {
        guard shouldEnsureMapVisibility(for: plant) else { return false }
        guard let spread = plant.spreadCurrent else { return true }
        return spread <= 0
    }

    private func needsTerrainCoordinateRepair(for plant: GardenPlant) -> Bool {
        guard shouldAssignTerrainCoordinate(for: plant) else { return false }
        guard let lat = plant.lat, let lon = plant.lon else {
            return true
        }
        return MapVisibilityDefaults.shouldSnapToTerrain(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            terrainPolygons: mapTerrainPolygons,
            ilotPolygons: mapIlotPolygons
        )
    }

    private func normalizedVisibilityStatus(_ status: String?) -> String {
        (status ?? "")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func terrainDefaultCoordinate() -> CLLocationCoordinate2D {
        if let coordinate = MapVisibilityDefaults.centroid(of: mapTerrainPolygons) {
            return coordinate
        }

        if let coordinate = MapVisibilityDefaults.centroid(of: mapIlotPolygons) {
            return coordinate
        }

        if let plant = plants.first(where: { $0.lat != nil && $0.lon != nil }),
           let lat = plant.lat,
           let lon = plant.lon {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        return MapVisibilityDefaults.fallbackCoordinate
    }

    private func scheduleMapVisibilityRepairSync() {
        guard didStartSyncSession else { return }
        deferredMapVisibilitySyncTask?.cancel()
        deferredMapVisibilitySyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self else { return }
            self.syncWithSupabase()
            self.deferredMapVisibilitySyncTask = nil
        }
    }

    // MARK: - Read access for UI (Database stays private to Store)

    func fetchStats() -> JardinStats {
        let zoneCount = Set(plants.compactMap { $0.zone?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }).count
        return JardinStats(
            plantCount: plants.count,
            speciesCount: species.count,
            zoneCount: zoneCount,
            hiveCount: 0,
            colonyCount: 0
        )
    }

    func fetchSpeciesBase() -> [GardenTaxon] {
        species
    }

    func fetchSpeciesDetail(speciesId: Int32) -> GardenTaxonDetailData? {
        if let base = species.first(where: { $0.id == Int(speciesId) }) {
            do {
                let siteID = try localDB?.currentSiteID()
                let cultivars = try localDB?.fetchCultivarsActive(siteID: siteID) ?? []
                let individualRecords = try localDB?.fetchIndividualsActive(siteID: siteID) ?? []
                let equivalentSpecies = equivalentSpeciesSet(for: base)
                let equivalentSpeciesUUIDs = Set(equivalentSpecies.map(\.uuid))
                let equivalentSpeciesIDs = Set(equivalentSpecies.map(\.id))
                let plantCountByCultivar = Dictionary(
                    grouping: individualRecords.compactMap(\.cultivarID),
                    by: { $0 }
                ).mapValues(\.count)
                let relatedCultivars = cultivars.filter { cultivar in
                    guard let speciesPrivateID = cultivar.speciesPrivateID else { return false }
                    return equivalentSpeciesUUIDs.contains(speciesPrivateID)
                }
                let cultivarModels = CanopyUIAdapters.toGardenCultivars(
                    cultivars: relatedCultivars,
                    speciesID: base.id,
                    plantCountByCultivar: plantCountByCultivar
                )
                let relatedPlants = plants.filter { equivalentSpeciesIDs.contains($0.speciesID) }
                return GardenTaxonDetailData(base: base, cultivars: cultivarModels, plants: relatedPlants)
            } catch {
                AppLog.error("fetchSpeciesDetail(speciesId): \(error)", category: .database)
            }
        }
        return nil
    }

    func fetchSpeciesDetail(latinName: String) -> GardenTaxonDetailData? {
        if let base = species.first(where: { $0.latinName.caseInsensitiveCompare(latinName) == .orderedSame }) {
            return fetchSpeciesDetail(speciesId: Int32(base.id))
        }
        return nil
    }

    private func canonicalSpeciesKey(for species: GardenTaxon) -> String {
        let latin = species.latinName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !latin.isEmpty {
            return "latin:\(latin)"
        }
        let common = species.commonName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "common:\(common)"
    }

    private func equivalentSpeciesSet(for base: GardenTaxon) -> [GardenTaxon] {
        let key = canonicalSpeciesKey(for: base)
        return species.filter { canonicalSpeciesKey(for: $0) == key }
    }

    func generateAutomaticPlantLabel(
        speciesId: Int,
        varietyId: Int?,
        existingPlantID: Int?
    ) throws -> String {
        if let existingPlantID,
           let existing = plants.first(where: { $0.id == existingPlantID }),
           let label = existing.label,
           !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return label
        }

        let prefix: String = {
            guard let species = species.first(where: { $0.id == speciesId }) else {
                return "IND"
            }
            let base = species.commonName.trimmingCharacters(in: .whitespacesAndNewlines)
            if base.isEmpty { return "IND" }
            let folded = base.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            let letters = folded
                .unicodeScalars
                .filter { CharacterSet.letters.contains($0) }
                .map(String.init)
                .joined()
            let token = String(letters.prefix(3)).uppercased()
            return token.isEmpty ? "IND" : token
        }()
        let sequence = plants.filter { $0.speciesID == speciesId }.count + 1
        return "\(prefix)-\(String(format: "%03d", sequence))"
    }

    func createPlant(_ input: PlantWriteInput) {
        do {
            try createPlantRecord(input)
            loadLocalData()
            syncWithSupabase()
        } catch {
            AppLog.error("Erreur createPlant: \(error)", category: .database)
        }
    }

    func updatePlant(_ plant: GardenPlant, with input: PlantWriteInput) {
        do {
            try updatePlantRecord(plant, input: input)
            loadLocalData()
            syncWithSupabase()
        } catch {
            AppLog.error("Erreur updatePlant: \(error)", category: .database)
        }
    }

    func updatePlantGeometry(
        plantID: Int,
        latitude: Double,
        longitude: Double,
        canopyDiameterMeters: Double?
    ) {
        let latRounded = roundedCoordinate(latitude, decimals: 6)
        let lonRounded = roundedCoordinate(longitude, decimals: 6)
        do {
            guard let plant = plants.first(where: { $0.id == plantID }) else { return }
            let input = PlantWriteInput(
                speciesId: plant.speciesID,
                varietyId: nil,
                zone: plant.zone,
                notes: plant.notes,
                status: plant.status,
                microSite: plant.microSite,
                exposureLocal: plant.exposureLocal,
                soilLocal: plant.soilLocal,
                acquisitionType: plant.acquisitionType,
                acquisitionSource: plant.acquisitionSource,
                careNotes: plant.careNotes,
                heightCurrent: plant.heightCurrent,
                envergureCurrent: canopyDiameterMeters,
                latitude: latRounded,
                longitude: lonRounded
            )
            try updatePlantRecord(plant, input: input)
            loadLocalData()
            syncWithSupabase()
        } catch {
            AppLog.error("Erreur updatePlantGeometry: \(error)", category: .database)
        }
    }

    @discardableResult
    func createSpecies(_ input: SpeciesWriteInput) -> Int? {
        do {
            let newId = try createSpeciesRecord(input)
            loadLocalSpecies()
            syncWithSupabase()
            return newId
        } catch {
            AppLog.error("Erreur createSpecies(input): \(error)", category: .database)
            return nil
        }
    }

    func updateSpecies(_ species: GardenTaxon, with input: SpeciesWriteInput) {
        do {
            try updateSpeciesRecord(species: species, input: input)
            loadLocalSpecies()
            syncWithSupabase()
        } catch {
            AppLog.error("Erreur updateSpecies(input): \(error)", category: .database)
        }
    }

    // MARK: - Taxon updates

    /// Met à jour le tronc commun d'un taxon pour un même latinName.
    func updateSpeciesCommonFields(
        latinName: String,
        speciesId: Int? = nil,
        with input: SpeciesCommonWriteInput
    ) {
        do {
            try updateSpeciesCommonFieldsRecord(latinName: latinName, speciesId: speciesId, input: input)
            loadLocalSpecies()
            syncWithSupabase()
        } catch {
            AppLog.error("Erreur updateSpeciesCommonFields(input): \(error)", category: .database)
        }
    }

    @discardableResult
    func updateCultivar(id: Int, with input: CultivarWriteInput) -> Bool {
        do {
            try updateCultivarRecord(id: id, input: input)
            loadLocalSpecies()
            loadLocalData()
            syncWithSupabase()
            return true
        } catch {
            AppLog.error("Erreur updateCultivar(input): \(error)", category: .database)
            return false
        }
    }

    @discardableResult
    func createCultivar(speciesId: Int, input: CultivarWriteInput) -> String? {
        do {
            let remoteID = try createCultivarRecord(speciesId: speciesId, input: input)
            loadLocalSpecies()
            loadLocalData()
            syncWithSupabase()
            return remoteID
        } catch {
            AppLog.error("Erreur createCultivar(input): \(error)", category: .database)
            return nil
        }
    }

    func deleteCultivar(id: Int32) -> DeleteCultivarResult {
        do {
            let result = try deleteCultivarRecord(id: Int(id))
            if result == .success {
                loadLocalSpecies()
                loadLocalData()
                syncWithSupabase()
            }
            return result
        } catch {
            AppLog.error("Erreur deleteCultivar: \(error)", category: .database)
            return .failure
        }
    }

    func deleteCultivar(id: Int) -> DeleteCultivarResult {
        deleteCultivar(id: Int32(id))
    }

    func deleteSpecies(id: Int32) -> GardenDeleteSpeciesResult {
        do {
            let result = try deleteSpeciesRecord(id: Int(id))
            if result == .success {
                loadLocalSpecies()
                loadLocalData()
                syncWithSupabase()
            }
            return result
        } catch {
            AppLog.error("Erreur deleteSpecies: \(error)", category: .database)
            return .failure
        }
    }

    func deleteSpecies(id: Int) -> GardenDeleteSpeciesResult {
        deleteSpecies(id: Int32(id))
    }

    // MARK: - Local mutations

    private enum LocalMutationError: Error {
        case localDatabaseUnavailable
        case noCurrentSite
        case speciesNotFound
        case cultivarNotFound
        case individualNotFound
        case missingRemoteID
        case payloadEncodingFailed
    }

    private func requireLocalContext() throws -> (CanopyLocalDatabase, String) {
        guard let localDB else { throw LocalMutationError.localDatabaseUnavailable }
        guard let siteID = try localDB.currentSiteID(), !siteID.isEmpty else {
            throw LocalMutationError.noCurrentSite
        }
        return (localDB, siteID)
    }

    private func nilIfEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func stableIntID(from raw: String) -> Int {
        var hash: UInt32 = 2_166_136_261
        for byte in raw.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return Int(hash & 0x7FFF_FFFF)
    }

    private func splitTags(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("["),
           let data = trimmed.data(using: .utf8),
           let jsonTags = try? JSONDecoder().decode([String].self, from: data) {
            return jsonTags
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return raw
            .split(whereSeparator: { ",;|".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func jsonValue(_ value: String?) -> CanopyJSONValue {
        guard let value = nilIfEmpty(value) else { return .null }
        return .string(value)
    }

    private func jsonValue(_ value: Int?) -> CanopyJSONValue {
        guard let value else { return .null }
        return .int(value)
    }

    private func jsonValue(_ value: Double?) -> CanopyJSONValue {
        guard let value else { return .null }
        return .double(value)
    }

    private func tagsJSONValue(_ raw: String?) -> CanopyJSONValue {
        let tags = splitTags(raw)
        guard !tags.isEmpty else { return .null }
        return .array(tags.map(CanopyJSONValue.string))
    }

    private func payloadJSONString(from row: CanopyDynamicRow) throws -> String {
        let data = try JSONEncoder().encode(row)
        guard let raw = String(data: data, encoding: .utf8) else {
            throw LocalMutationError.payloadEncodingFailed
        }
        return raw
    }

    private func normalizedCanopyStatus(_ raw: String?) -> String {
        let value = nilIfEmpty(raw)?
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        switch value {
        case nil, "":
            return "plante"
        case "plante", "plantee", "plantee ":
            return "plante"
        case "planifie", "planifiee", "a_deplacer", "a deplacer", "a_placer", "a placer":
            return "a_placer"
        case "mort":
            return "mort"
        case "retire", "retiree":
            return "retire"
        default:
            return "plante"
        }
    }

    private func speciesByID(_ id: Int) -> GardenTaxon? {
        species.first(where: { $0.id == id })
    }

    private func cultivarByStableID(
        _ stableID: Int,
        siteID: String,
        localDB: CanopyLocalDatabase
    ) throws -> CanopyLocalCultivarRecord? {
        let cultivars = try localDB.fetchCultivarsActive(siteID: siteID)
        return cultivars.first { stableIntID(from: $0.remoteID) == stableID }
    }

    private func resolveCultivarRemoteID(
        stableID: Int?,
        siteID: String,
        localDB: CanopyLocalDatabase,
        existing: CanopyLocalIndividualRecord?
    ) throws -> String? {
        if let stableID {
            guard let cultivar = try cultivarByStableID(stableID, siteID: siteID, localDB: localDB) else {
                throw LocalMutationError.cultivarNotFound
            }
            return cultivar.remoteID
        }
        return existing?.cultivarID
    }

    private func makeSpeciesRow(
        remoteID: String,
        siteID: String,
        createdAt: String,
        updatedAt: String,
        deletedAt: String?,
        input: SpeciesWriteInput
    ) -> CanopyDynamicRow {
        var values: [String: CanopyJSONValue] = [
            CanopySchema.SpeciesPrivateFields.id: .string(remoteID),
            CanopySchema.SpeciesPrivateFields.siteId: .string(siteID),
            CanopySchema.SpeciesPrivateFields.speciesGlobalId: .null,
            CanopySchema.SpeciesPrivateFields.latinName: jsonValue(input.latinName),
            CanopySchema.SpeciesPrivateFields.commonName: jsonValue(input.commonName),
            CanopySchema.SpeciesPrivateFields.family: jsonValue(input.family),
            CanopySchema.SpeciesPrivateFields.genus: jsonValue(input.genus),
            CanopySchema.SpeciesPrivateFields.strata: jsonValue(input.strata),
            CanopySchema.SpeciesPrivateFields.origin: jsonValue(input.origin),
            CanopySchema.SpeciesPrivateFields.plantType: jsonValue(input.plantType),
            CanopySchema.SpeciesPrivateFields.morphology: jsonValue(input.morphology),
            CanopySchema.SpeciesPrivateFields.culture: jsonValue(input.culture),
            CanopySchema.SpeciesPrivateFields.uses: jsonValue(input.uses),
            CanopySchema.SpeciesPrivateFields.melliferousLevel: jsonValue(input.melliferousLevel),
            CanopySchema.SpeciesPrivateFields.ornamentalInterest: jsonValue(input.ornamentalInterest),
            CanopySchema.SpeciesPrivateFields.lifespanMin: jsonValue(input.lifespanMin),
            CanopySchema.SpeciesPrivateFields.lifespanMax: jsonValue(input.lifespanMax),
            CanopySchema.SpeciesPrivateFields.heightMin: jsonValue(input.heightMin),
            CanopySchema.SpeciesPrivateFields.heightMax: jsonValue(input.heightMax),
            CanopySchema.SpeciesPrivateFields.floweringPeriod: jsonValue(input.floweringPeriod),
            CanopySchema.SpeciesPrivateFields.fruitingPeriod: jsonValue(input.fruitingPeriod),
            CanopySchema.SpeciesPrivateFields.envergureMin: jsonValue(input.envergureMin),
            CanopySchema.SpeciesPrivateFields.envergureMax: jsonValue(input.envergureMax),
            CanopySchema.SpeciesPrivateFields.imageUrl: jsonValue(input.imageURL),
            CanopySchema.SpeciesPrivateFields.tags: tagsJSONValue(input.tags),
            CanopySchema.SpeciesPrivateFields.notes: jsonValue(input.notes),
            CanopySchema.SpeciesPrivateFields.metadata: .null,
            CanopySchema.SpeciesPrivateFields.createdAt: .string(createdAt),
            CanopySchema.SpeciesPrivateFields.updatedAt: .string(updatedAt),
        ]
        values[CanopySchema.SpeciesPrivateFields.deletedAt] = deletedAt.map(CanopyJSONValue.string) ?? .null
        return CanopyDynamicRow(values: values)
    }

    private func createSpeciesRecord(_ input: SpeciesWriteInput) throws -> Int {
        let (localDB, siteID) = try requireLocalContext()
        let remoteID = UUID().uuidString.lowercased()
        let now = currentTimestampString()
        let row = makeSpeciesRow(
            remoteID: remoteID,
            siteID: siteID,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            input: input
        )

        try localDB.upsertSpeciesPrivateRows(siteID: siteID, rows: [row])
        try localDB.enqueueOutboxOperation(
            siteID: siteID,
            entityType: CanopySchema.Tables.speciesPrivate,
            entityRemoteID: remoteID,
            opType: "upsert",
            payloadJSON: try payloadJSONString(from: row)
        )
        return stableIntID(from: remoteID)
    }

    private func updateSpeciesRecord(species: GardenTaxon, input: SpeciesWriteInput) throws {
        let (localDB, siteID) = try requireLocalContext()
        let remoteID = species.uuid ?? speciesByID(species.id)?.uuid
        guard let remoteID, !remoteID.isEmpty else { throw LocalMutationError.missingRemoteID }

        let now = currentTimestampString()
        let createdAt = try localDB.fetchSpeciesPrivateRecord(remoteID: remoteID)?.createdAt ?? now
        let row = makeSpeciesRow(
            remoteID: remoteID,
            siteID: siteID,
            createdAt: createdAt,
            updatedAt: now,
            deletedAt: nil,
            input: input
        )

        try localDB.upsertSpeciesPrivateRows(siteID: siteID, rows: [row])
        try localDB.enqueueOutboxOperation(
            siteID: siteID,
            entityType: CanopySchema.Tables.speciesPrivate,
            entityRemoteID: remoteID,
            opType: "upsert",
            payloadJSON: try payloadJSONString(from: row)
        )
    }

    private func updateSpeciesCommonFieldsRecord(
        latinName: String,
        speciesId: Int?,
        input: SpeciesCommonWriteInput
    ) throws {
        let target = speciesId.flatMap { speciesByID($0) }
            ?? species.first(where: { $0.latinName.caseInsensitiveCompare(latinName) == .orderedSame })
        guard let target else { throw LocalMutationError.speciesNotFound }

        let writeInput = SpeciesWriteInput(
            commonName: input.commonName,
            varietyName: nil,
            latinName: target.latinName,
            family: input.family,
            genus: input.genus,
            strata: input.strata,
            tags: input.tags,
            notes: input.notes,
            imageURL: input.imageURL,
            origin: input.origin,
            plantType: input.plantType,
            morphology: input.morphology,
            culture: input.culture,
            uses: input.uses,
            melliferousLevel: input.melliferousLevel,
            ornamentalInterest: input.ornamentalInterest,
            lifespanMin: input.lifespanMin,
            lifespanMax: input.lifespanMax,
            heightMin: input.heightMin,
            heightMax: input.heightMax,
            envergureMin: input.envergureMin,
            envergureMax: input.envergureMax,
            floweringPeriod: input.floweringPeriod,
            fruitingPeriod: input.fruitingPeriod,
            varietyNotes: nil
        )
        try updateSpeciesRecord(species: target, input: writeInput)
    }

    private func makeIndividualMetadata(
        input: PlantWriteInput,
        existing: CanopyLocalIndividualRecord?
    ) -> CanopyJSONValue {
        var object = decodeMetadataObject(from: existing?.metadataJSON)

        func assignString(_ key: String, _ value: String?) {
            if let value = nilIfEmpty(value) {
                object[key] = .string(value)
            } else {
                object.removeValue(forKey: key)
            }
        }

        assignString("micro_site", input.microSite)
        assignString("exposure_local", input.exposureLocal)
        assignString("soil_local", input.soilLocal)
        assignString("acquisition_type", input.acquisitionType)
        assignString("acquisition_source", input.acquisitionSource)
        assignString("care_notes", input.careNotes)

        if let value = input.varietyId {
            object["legacy_variety_id"] = .int(value)
        } else {
            object.removeValue(forKey: "legacy_variety_id")
        }

        object.removeValue(forKey: "height_current")
        object.removeValue(forKey: "envergure_current")

        return object.isEmpty ? .null : .object(object)
    }

    private func decodeMetadataObject(from raw: String?) -> [String: CanopyJSONValue] {
        guard
            let raw,
            let data = raw.data(using: .utf8),
            let object = try? JSONDecoder().decode([String: CanopyJSONValue].self, from: data)
        else {
            return [:]
        }
        return object
    }

    private func resolveLocalSiteIlotID(
        siteID: String,
        latitude: Double?,
        longitude: Double?,
        zone: String?,
        localDB: CanopyLocalDatabase,
        existing: CanopyLocalIndividualRecord?
    ) throws -> String? {
        let ilots = try localDB.fetchSiteIlotsActive(siteID: siteID)
        guard !ilots.isEmpty else { return existing?.siteIlotID }

        if let latitude, let longitude {
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)

            if let containing = ilots.first(where: { record in
                let polygons = Self.geometryPolygons(from: record.geomJSON)
                return polygons.contains { polygon in
                    MapVisibilityDefaults.polygonContains(coordinate, polygon: polygon)
                }
            }) {
                return containing.remoteID
            }

            let nearest = ilots.compactMap { record -> (String, Double)? in
                guard let centroid = Self.centroidCoordinate(for: record) else { return nil }
                let distance = MKMapPoint(coordinate).distance(to: MKMapPoint(centroid))
                return (record.remoteID, distance)
            }
            .min(by: { $0.1 < $1.1 })

            if let nearest {
                return nearest.0
            }
        }

        if let zone = nilIfEmpty(zone) {
            let normalizedZone = zone
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()

            if let matched = ilots.first(where: {
                let code = $0.code.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
                let name = ($0.name ?? "").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
                return code == normalizedZone || name == normalizedZone
            }) {
                return matched.remoteID
            }
        }

        if let existingID = existing?.siteIlotID,
           ilots.contains(where: { $0.remoteID == existingID }) {
            return existingID
        }

        return ilots.first?.remoteID
    }

    private func makeIndividualRow(
        remoteID: String,
        siteID: String,
        speciesPrivateID: String?,
        cultivarID: String?,
        siteIlotID: String?,
        createdAt: String,
        updatedAt: String,
        deletedAt: String?,
        input: PlantWriteInput,
        existing: CanopyLocalIndividualRecord?,
        label: String
    ) -> CanopyDynamicRow {
        var values: [String: CanopyJSONValue] = [
            CanopySchema.IndividualsFields.id: .string(remoteID),
            CanopySchema.IndividualsFields.siteId: .string(siteID),
            CanopySchema.IndividualsFields.speciesGlobalId: .null,
            CanopySchema.IndividualsFields.speciesPrivateId: speciesPrivateID.map(CanopyJSONValue.string) ?? .null,
            CanopySchema.IndividualsFields.cultivarId: cultivarID.map(CanopyJSONValue.string) ?? .null,
            CanopySchema.IndividualsFields.code: existing?.code.map(CanopyJSONValue.string) ?? .null,
            CanopySchema.IndividualsFields.label: .string(label),
            CanopySchema.IndividualsFields.imageUrl: existing?.imageURL.map(CanopyJSONValue.string) ?? .null,
            CanopySchema.IndividualsFields.status: .string(normalizedCanopyStatus(input.status)),
            CanopySchema.IndividualsFields.plantedAt: existing?.plantedAt.map(CanopyJSONValue.string) ?? .null,
            CanopySchema.IndividualsFields.locationLat: jsonValue(input.latitude),
            CanopySchema.IndividualsFields.locationLng: jsonValue(input.longitude),
            CanopySchema.IndividualsFields.locationAlt: existing?.locationAlt.map(CanopyJSONValue.double) ?? .null,
            CanopySchema.IndividualsFields.siteIlotId: siteIlotID.map(CanopyJSONValue.string) ?? .null,
            CanopySchema.IndividualsFields.heightCurrent: jsonValue(input.heightCurrent),
            CanopySchema.IndividualsFields.envergureCurrent: jsonValue(input.envergureCurrent),
            CanopySchema.IndividualsFields.zone: jsonValue(input.zone),
            CanopySchema.IndividualsFields.notes: jsonValue(input.notes),
            CanopySchema.IndividualsFields.tags: existing?.tagsJSON.flatMap { raw in
                guard let data = raw.data(using: .utf8),
                      let tags = try? JSONDecoder().decode([String].self, from: data),
                      !tags.isEmpty else { return nil }
                return .array(tags.map(CanopyJSONValue.string))
            } ?? .null,
            CanopySchema.IndividualsFields.metadata: makeIndividualMetadata(input: input, existing: existing),
            CanopySchema.IndividualsFields.createdAt: .string(createdAt),
            CanopySchema.IndividualsFields.updatedAt: .string(updatedAt),
        ]
        values[CanopySchema.IndividualsFields.deletedAt] = deletedAt.map(CanopyJSONValue.string) ?? .null
        return CanopyDynamicRow(values: values)
    }

    private func createPlantRecord(_ input: PlantWriteInput) throws {
        let (localDB, siteID) = try requireLocalContext()
        guard let species = speciesByID(input.speciesId) else { throw LocalMutationError.speciesNotFound }
        guard let speciesRemoteID = species.uuid, !speciesRemoteID.isEmpty else { throw LocalMutationError.missingRemoteID }

        let remoteID = UUID().uuidString.lowercased()
        let now = currentTimestampString()
        let label = try generateAutomaticPlantLabel(speciesId: input.speciesId, varietyId: input.varietyId, existingPlantID: nil)
        let cultivarRemoteID = try resolveCultivarRemoteID(
            stableID: input.varietyId,
            siteID: siteID,
            localDB: localDB,
            existing: nil
        )
        let siteIlotID = try resolveLocalSiteIlotID(
            siteID: siteID,
            latitude: input.latitude,
            longitude: input.longitude,
            zone: input.zone,
            localDB: localDB,
            existing: nil
        )
        let row = makeIndividualRow(
            remoteID: remoteID,
            siteID: siteID,
            speciesPrivateID: speciesRemoteID,
            cultivarID: cultivarRemoteID,
            siteIlotID: siteIlotID,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            input: input,
            existing: nil,
            label: label
        )

        try localDB.upsertIndividualsRows(siteID: siteID, rows: [row])
        try localDB.enqueueOutboxOperation(
            siteID: siteID,
            entityType: CanopySchema.Tables.individuals,
            entityRemoteID: remoteID,
            opType: "upsert",
            payloadJSON: try payloadJSONString(from: row)
        )
    }

    private func updatePlantRecord(_ plant: GardenPlant, input: PlantWriteInput) throws {
        let (localDB, siteID) = try requireLocalContext()
        guard let remoteID = plant.uuid, !remoteID.isEmpty else { throw LocalMutationError.missingRemoteID }
        guard let species = speciesByID(input.speciesId), let speciesRemoteID = species.uuid, !speciesRemoteID.isEmpty else {
            throw LocalMutationError.speciesNotFound
        }

        let existing = try localDB.fetchIndividualRecord(remoteID: remoteID)
        let now = currentTimestampString()
        let cultivarRemoteID = try resolveCultivarRemoteID(
            stableID: input.varietyId,
            siteID: siteID,
            localDB: localDB,
            existing: existing
        )
        let siteIlotID = try resolveLocalSiteIlotID(
            siteID: siteID,
            latitude: input.latitude,
            longitude: input.longitude,
            zone: input.zone,
            localDB: localDB,
            existing: existing
        )
        let label = try generateAutomaticPlantLabel(
            speciesId: input.speciesId,
            varietyId: input.varietyId,
            existingPlantID: plant.id
        )
        let row = makeIndividualRow(
            remoteID: remoteID,
            siteID: siteID,
            speciesPrivateID: speciesRemoteID,
            cultivarID: cultivarRemoteID,
            siteIlotID: siteIlotID,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            deletedAt: nil,
            input: input,
            existing: existing,
            label: label
        )

        try localDB.upsertIndividualsRows(siteID: siteID, rows: [row])
        try localDB.enqueueOutboxOperation(
            siteID: siteID,
            entityType: CanopySchema.Tables.individuals,
            entityRemoteID: remoteID,
            opType: "upsert",
            payloadJSON: try payloadJSONString(from: row)
        )
    }

    private func deletePlantRecord(_ plant: GardenPlant) throws {
        let (localDB, siteID) = try requireLocalContext()
        guard let remoteID = plant.uuid, !remoteID.isEmpty else { throw LocalMutationError.missingRemoteID }
        guard let existing = try localDB.fetchIndividualRecord(remoteID: remoteID) else {
            throw LocalMutationError.individualNotFound
        }

        let now = currentTimestampString()
        let surrogateInput = PlantWriteInput(
            speciesId: speciesByID(plant.speciesID)?.id ?? plant.speciesID,
            varietyId: nil,
            zone: existing.zone,
            notes: existing.notes,
            status: existing.status,
            microSite: nil,
            exposureLocal: nil,
            soilLocal: nil,
            acquisitionType: nil,
            acquisitionSource: nil,
            careNotes: nil,
            heightCurrent: existing.heightCurrent,
            envergureCurrent: existing.envergureCurrent,
            latitude: existing.locationLat,
            longitude: existing.locationLng
        )
        let row = makeIndividualRow(
            remoteID: remoteID,
            siteID: siteID,
            speciesPrivateID: existing.speciesPrivateID,
            cultivarID: existing.cultivarID,
            siteIlotID: existing.siteIlotID,
            createdAt: existing.createdAt,
            updatedAt: now,
            deletedAt: now,
            input: surrogateInput,
            existing: existing,
            label: existing.label ?? existing.code ?? plant.label ?? "#\(plant.id)"
        )

        try localDB.upsertIndividualsRows(siteID: siteID, rows: [row])
        try localDB.enqueueOutboxOperation(
            siteID: siteID,
            entityType: CanopySchema.Tables.individuals,
            entityRemoteID: remoteID,
            opType: "delete",
            payloadJSON: "{}"
        )
    }

    private func deleteSpeciesRecord(id: Int) throws -> GardenDeleteSpeciesResult {
        guard let target = speciesByID(id) else { return .failure }
        if plants.contains(where: { $0.speciesID == id }) {
            return .linkedToPlants
        }

        let (localDB, siteID) = try requireLocalContext()
        guard let remoteID = target.uuid, !remoteID.isEmpty else { throw LocalMutationError.missingRemoteID }
        guard let existing = try localDB.fetchSpeciesPrivateRecord(remoteID: remoteID) else {
            throw LocalMutationError.speciesNotFound
        }

        let now = currentTimestampString()
        let writeInput = SpeciesWriteInput(
            commonName: existing.commonName ?? target.commonName,
            varietyName: nil,
            latinName: existing.latinName ?? target.latinName,
            family: existing.family,
            genus: existing.genus,
            strata: existing.strata,
            tags: splitTags(existing.tagsJSON).joined(separator: ", "),
            notes: existing.notes,
            imageURL: existing.imageURL,
            origin: existing.origin,
            plantType: existing.plantType,
            morphology: existing.morphology,
            culture: existing.culture,
            uses: existing.uses,
            melliferousLevel: existing.melliferousLevel,
            ornamentalInterest: existing.ornamentalInterest,
            lifespanMin: existing.lifespanMin,
            lifespanMax: existing.lifespanMax,
            heightMin: existing.heightMin,
            heightMax: existing.heightMax,
            envergureMin: existing.envergureMin,
            envergureMax: existing.envergureMax,
            floweringPeriod: existing.floweringPeriod,
            fruitingPeriod: existing.fruitingPeriod,
            varietyNotes: nil
        )
        let row = makeSpeciesRow(
            remoteID: remoteID,
            siteID: siteID,
            createdAt: existing.createdAt,
            updatedAt: now,
            deletedAt: now,
            input: writeInput
        )

        try localDB.upsertSpeciesPrivateRows(siteID: siteID, rows: [row])
        try localDB.enqueueOutboxOperation(
            siteID: siteID,
            entityType: CanopySchema.Tables.speciesPrivate,
            entityRemoteID: remoteID,
            opType: "delete",
            payloadJSON: "{}"
        )
        return .success
    }

    private func makeCultivarRow(
        remoteID: String,
        siteID: String,
        speciesPrivateID: String?,
        createdAt: String,
        updatedAt: String,
        deletedAt: String?,
        input: CultivarWriteInput,
        existing: CanopyLocalCultivarRecord?
    ) -> CanopyDynamicRow {
        var values: [String: CanopyJSONValue] = [
            CanopySchema.CultivarsFields.id: .string(remoteID),
            CanopySchema.CultivarsFields.siteId: .string(siteID),
            CanopySchema.CultivarsFields.speciesGlobalId: .null,
            CanopySchema.CultivarsFields.speciesPrivateId: speciesPrivateID.map(CanopyJSONValue.string) ?? .null,
            CanopySchema.CultivarsFields.name: .string(input.name.trimmingCharacters(in: .whitespacesAndNewlines)),
            CanopySchema.CultivarsFields.imageUrl: existing?.imageURL.map(CanopyJSONValue.string) ?? .null,
            CanopySchema.CultivarsFields.notes: jsonValue(input.notes),
            CanopySchema.CultivarsFields.tags: tagsJSONValue(input.tags),
            CanopySchema.CultivarsFields.origin: jsonValue(input.origin),
            CanopySchema.CultivarsFields.createdAt: .string(createdAt),
            CanopySchema.CultivarsFields.updatedAt: .string(updatedAt),
        ]
        values[CanopySchema.CultivarsFields.deletedAt] = deletedAt.map(CanopyJSONValue.string) ?? .null
        return CanopyDynamicRow(values: values)
    }

    private func createCultivarRecord(speciesId: Int, input: CultivarWriteInput) throws -> String {
        let (localDB, siteID) = try requireLocalContext()
        guard let species = speciesByID(speciesId),
              let speciesRemoteID = species.uuid,
              !speciesRemoteID.isEmpty else {
            throw LocalMutationError.speciesNotFound
        }

        let remoteID = UUID().uuidString.lowercased()
        let now = currentTimestampString()
        let row = makeCultivarRow(
            remoteID: remoteID,
            siteID: siteID,
            speciesPrivateID: speciesRemoteID,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            input: input,
            existing: nil
        )

        try localDB.upsertCultivarsRows(siteID: siteID, rows: [row])
        try localDB.enqueueOutboxOperation(
            siteID: siteID,
            entityType: CanopySchema.Tables.cultivars,
            entityRemoteID: remoteID,
            opType: "upsert",
            payloadJSON: try payloadJSONString(from: row)
        )
        return remoteID
    }

    private func updateCultivarRecord(id: Int, input: CultivarWriteInput) throws {
        let (localDB, siteID) = try requireLocalContext()
        guard let existing = try cultivarByStableID(id, siteID: siteID, localDB: localDB) else {
            throw LocalMutationError.cultivarNotFound
        }

        let now = currentTimestampString()
        let row = makeCultivarRow(
            remoteID: existing.remoteID,
            siteID: siteID,
            speciesPrivateID: existing.speciesPrivateID,
            createdAt: existing.createdAt,
            updatedAt: now,
            deletedAt: nil,
            input: input,
            existing: existing
        )

        try localDB.upsertCultivarsRows(siteID: siteID, rows: [row])
        try localDB.enqueueOutboxOperation(
            siteID: siteID,
            entityType: CanopySchema.Tables.cultivars,
            entityRemoteID: existing.remoteID,
            opType: "upsert",
            payloadJSON: try payloadJSONString(from: row)
        )
    }

    private func deleteCultivarRecord(id: Int) throws -> DeleteCultivarResult {
        let (localDB, siteID) = try requireLocalContext()
        guard let existing = try cultivarByStableID(id, siteID: siteID, localDB: localDB) else {
            return .failure
        }

        let individuals = try localDB.fetchIndividualsActive(siteID: siteID)
        if individuals.contains(where: { $0.cultivarID == existing.remoteID }) {
            return .linkedToPlants
        }

        let now = currentTimestampString()
        let row = makeCultivarRow(
            remoteID: existing.remoteID,
            siteID: siteID,
            speciesPrivateID: existing.speciesPrivateID,
            createdAt: existing.createdAt,
            updatedAt: now,
            deletedAt: now,
            input: CultivarWriteInput(
                name: existing.name,
                notes: existing.notes,
                tags: splitTags(existing.tagsJSON).joined(separator: ", "),
                origin: existing.origin
            ),
            existing: existing
        )

        try localDB.upsertCultivarsRows(siteID: siteID, rows: [row])
        try localDB.enqueueOutboxOperation(
            siteID: siteID,
            entityType: CanopySchema.Tables.cultivars,
            entityRemoteID: existing.remoteID,
            opType: "delete",
            payloadJSON: "{}"
        )
        return .success
    }
}

private struct CanopyGeoJSONGeometry: Decodable {
    let type: String
    let coordinates: CanopyJSONValue
}

private extension CanopyStore {
    static func makeGardenSiteIlot(from record: CanopyLocalSiteIlotRecord) -> GardenSiteIlot {
        GardenSiteIlot(
            id: record.remoteID,
            siteID: record.siteID,
            code: record.code,
            name: record.name,
            polygons: geometryPolygons(from: record.geomJSON).map { polygon in
                polygon.map { coordinate in
                    GardenCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
                }
            },
            centroid: centroidCoordinate(for: record).map {
                GardenCoordinate(latitude: $0.latitude, longitude: $0.longitude)
            },
            areaM2: record.areaM2,
            sunExposure: record.sunExposure,
            humidityProfile: record.humidityProfile,
            pedology: record.pedology,
            slopePct: record.slopePct,
            aspect: record.aspect,
            windExposure: record.windExposure,
            notes: record.notes
        )
    }

    static func centroidCoordinate(for record: CanopyLocalSiteIlotRecord) -> CLLocationCoordinate2D? {
        if let lat = record.centroidLat, let lng = record.centroidLng {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }

        guard
            let raw = record.centroidJSON,
            let data = raw.data(using: .utf8),
            let geometry = try? JSONDecoder().decode(CanopyGeoJSONGeometry.self, from: data),
            geometry.type.caseInsensitiveCompare("Point") == .orderedSame,
            let coords = geometry.coordinates.arrayValue,
            coords.count >= 2,
            let lng = coords[0].doubleValue,
            let lat = coords[1].doubleValue
        else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    static func geometryPolygons(from raw: String?) -> [[CLLocationCoordinate2D]] {
        guard
            let raw,
            let data = raw.data(using: .utf8),
            let geometry = try? JSONDecoder().decode(CanopyGeoJSONGeometry.self, from: data)
        else {
            return []
        }

        switch geometry.type.lowercased() {
        case "polygon":
            guard let polygonRings = geometry.coordinates.arrayValue else { return [] }
            guard let outerRing = polygonRings.first?.arrayValue else { return [] }
            let polygon = coordinates(from: outerRing)
            return polygon.count >= 3 ? [polygon] : []

        case "multipolygon":
            guard let polygons = geometry.coordinates.arrayValue else { return [] }
            return polygons.compactMap { polygonValue in
                guard let polygonRings = polygonValue.arrayValue else { return nil }
                guard let outerRing = polygonRings.first?.arrayValue else { return nil }
                let polygon = coordinates(from: outerRing)
                return polygon.count >= 3 ? polygon : nil
            }

        default:
            return []
        }
    }

    private static func coordinates(from values: [CanopyJSONValue]) -> [CLLocationCoordinate2D] {
        values.compactMap { value in
            guard let pair = value.arrayValue, pair.count >= 2 else { return nil }
            guard let lng = pair[0].doubleValue, let lat = pair[1].doubleValue else { return nil }
            let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
        }
    }
}

private enum MapVisibilityDefaults {
    static let defaultCanopyDiameterMeters: Double = 2.0
    static let fallbackCoordinate = CLLocationCoordinate2D(
        latitude: 45.348828976987036,
        longitude: 4.0740432545957255
    )

    static func shouldSnapToTerrain(
        coordinate: CLLocationCoordinate2D,
        terrainPolygons: [[CLLocationCoordinate2D]],
        ilotPolygons: [[CLLocationCoordinate2D]]
    ) -> Bool {
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            return true
        }

        let referencePolygons = !terrainPolygons.isEmpty ? terrainPolygons : ilotPolygons
        guard !referencePolygons.isEmpty else {
            return false
        }

        return !referencePolygons.contains { polygonContains(coordinate, polygon: $0) }
    }

    static func centroid(of polygons: [[CLLocationCoordinate2D]]) -> CLLocationCoordinate2D? {
        let coordinates = polygons.flatMap { $0 }.filter { CLLocationCoordinate2DIsValid($0) }
        guard !coordinates.isEmpty else { return nil }

        let latitude = coordinates.map(\.latitude).reduce(0, +) / Double(coordinates.count)
        let longitude = coordinates.map(\.longitude).reduce(0, +) / Double(coordinates.count)
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func polygonContains(_ coordinate: CLLocationCoordinate2D, polygon: [CLLocationCoordinate2D]) -> Bool {
        guard polygon.count >= 3 else { return false }

        var contains = false
        var previous = polygon.last!

        for current in polygon {
            let denominator = previous.longitude - current.longitude
            let safeDenominator = abs(denominator) < 0.000_000_001
                ? (denominator < 0 ? -0.000_000_001 : 0.000_000_001)
                : denominator
            let intersects = ((current.longitude > coordinate.longitude) != (previous.longitude > coordinate.longitude))
                && (coordinate.latitude < (previous.latitude - current.latitude)
                    * (coordinate.longitude - current.longitude)
                    / safeDenominator
                    + current.latitude)
            if intersects {
                contains.toggle()
            }
            previous = current
        }

        return contains
    }
}

extension CanopyStore {
    private func currentTimestampString() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private func elapsedMilliseconds(since start: Date) -> Int {
        Int((Date().timeIntervalSince(start) * 1000).rounded())
    }

    private func syncLog(_ message: String, runID: String? = nil) {
        let prefix = runID.map { "[GardenSync run=\($0)]" } ?? "[GardenSync]"
        let line = "\(prefix) \(message)"
        if AppLog.isVerboseEnabled {
            AppLog.info(line, category: .sync)
        } else {
            print(line)
        }
    }

    func forceSyncNow() {
        syncWithSupabase(force: true, refreshImages: true)
    }

    func syncWithSupabase(force: Bool = false, refreshImages: Bool = false) {
        if !force, let syncTask, !syncTask.isCancelled {
            return
        }
        if force {
            syncTask?.cancel()
        }
        AppLog.info("syncWithSupabase start", category: .sync)
        syncTask = Task { [weak self] in
            guard let self else { return }
            let runID = String(UUID().uuidString.prefix(8))
            let syncStartedAt = Date()
            let syncStartedAtISO = currentTimestampString()
            syncLog(
                "START force=\(force) refreshImages=\(refreshImages) started_at=\(syncStartedAtISO)",
                runID: runID
            )
            await MainActor.run {
                self.isSyncing = true
                self.lastSyncMessage = "Synchro en cours..."
            }

            if refreshImages {
                await PersistentImageCache.shared.removeAll()
                await MainActor.run {
                    self.lastSyncMessage = "Synchro en cours... cache images purgé"
                }
            }

            defer {
                Task { @MainActor in
                    self.isSyncing = false
                    self.syncTask = nil
                }
            }

            do {
                if let syncEngine = self.syncEngine {
                    let pullStartedAt = Date()
                    let summary = try await syncEngine.pullLatest()
                    let duration = elapsedMilliseconds(since: pullStartedAt)

                    if let summary {
                        syncLog(
                            """
                            PULL done in \(duration) ms \
                            site=\(summary.siteID) \
                            sites=\(summary.sitesCount) species=\(summary.speciesCount) cultivars=\(summary.cultivarsCount) individuals=\(summary.individualsCount) site_ilots=\(summary.siteIlotsCount) \
                            max_sites=\(summary.sitesMaxUpdatedAt ?? "nil") \
                            max_species=\(summary.speciesMaxUpdatedAt ?? "nil") \
                            max_cultivars=\(summary.cultivarsMaxUpdatedAt ?? "nil") \
                            max_individuals=\(summary.individualsMaxUpdatedAt ?? "nil") \
                            max_site_ilots=\(summary.siteIlotsMaxUpdatedAt ?? "nil")
                            """,
                            runID: runID
                        )
                    } else {
                        syncLog("PULL done in \(duration) ms no_membership", runID: runID)
                    }

                    await MainActor.run {
                        self.loadLocalData()
                        self.loadLocalSpecies()
                        self.lastSyncDate = Date()
                        self.lastSyncMessage = summary == nil
                            ? "Synchro: aucun site membre actif"
                            : "Synchro terminée"
                    }

                    syncLog(
                        "END success in \(elapsedMilliseconds(since: syncStartedAt)) ms",
                        runID: runID
                    )
                    return
                }
                syncLog("Sync skipped: local Canopy sync engine unavailable.", runID: runID)
                await MainActor.run {
                    self.lastSyncMessage = "Base locale Canopy indisponible"
                }
            } catch {
                AppLog.error("Erreur syncWithSupabase: \(error)", category: .sync)
                syncLog(
                    "END failed in \(elapsedMilliseconds(since: syncStartedAt)) ms error=\(error)",
                    runID: runID
                )
                await MainActor.run {
                    self.lastSyncMessage = "Erreur de synchro: \(error.localizedDescription)"
                }
            }
        }
    }
    /// Supprime (logiquement) une plante : deleted = 1 + synchro
    func deletePlant(_ plant: GardenPlant) {
        do {
            try deletePlantRecord(plant)
            loadLocalData()
            syncWithSupabase()
        } catch {
            AppLog.error("Erreur deletePlant: \(error)", category: .database)
        }
    }
}
