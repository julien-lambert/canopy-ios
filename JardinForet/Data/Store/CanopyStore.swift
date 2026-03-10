//
//  Untitled.swift
//  JardinForet
//
//  Created by Julien Lambert on 16/11/2025.
//

import Foundation

final class GardenStore: ObservableObject {
    private enum ReadBackend {
        case legacy
        case v2
    }

    enum DeleteCultivarResult {
        case success
        case linkedToPlants
        case failure
    }

    @Published var plants: [GardenPlant] = []
    @Published var species: [GardenTaxon] = []
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var lastSyncMessage: String?
    private let db: GardenDatabase
    private let localV2DB: LocalV2Database?
    private let canopyV2Sync: CanopyV2ProjectionSync?
    private let readBackend: ReadBackend
    private let dbLock = NSLock()
    private var syncTask: Task<Void, Never>?
    private var didStartSyncSession = false
    private var didAuditImages = false

    /// True when read path is Canopy v2 (LocalV2 projection).
    var isCanopyV2ReadEnabled: Bool { readBackend == .v2 }

    /// Legacy write paths are still bound to old tables. Disable UI mutations in v2 mode.
    var canUseLegacyMutations: Bool { readBackend == .legacy }

    /// Species/individuals mutations are available on legacy and v2.
    var canMutateSpeciesAndIndividuals: Bool {
        readBackend == .legacy || (readBackend == .v2 && localV2DB != nil)
    }

    /// Cultivar mutations are still legacy-only until dedicated v2 support is added.
    var canMutateCultivars: Bool { readBackend == .legacy }

    init(database: GardenDatabase? = nil) {
        self.readBackend = Self.resolveReadBackend()
        self.db = database ?? GardenDatabase(useBundledSeed: readBackend != .v2)
        if readBackend == .v2 {
            self.localV2DB = try? LocalV2Database()
            if self.localV2DB == nil {
                AppLog.warning("LocalV2 indisponible: lecture v2 vide tant que la base locale n'est pas initialisable.", category: .database)
            }
            if let localV2DB {
                self.canopyV2Sync = CanopyV2ProjectionSync(localDB: localV2DB)
            } else {
                self.canopyV2Sync = nil
            }
        } else {
            self.localV2DB = nil
            self.canopyV2Sync = nil
        }
        AppLog.info("GardenStore init", category: .sync)
        // 1) Charger immédiatement les données locales depuis SQLite via GardenDatabase
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

    private func withDatabaseLock<T>(_ operation: () throws -> T) rethrows -> T {
        dbLock.lock()
        defer { dbLock.unlock() }
        return try operation()
    }

    private static func resolveReadBackend() -> ReadBackend {
        let envValue = ProcessInfo.processInfo.environment["GARDEN_READ_BACKEND"]
        let plistValue = Bundle.main.object(forInfoDictionaryKey: "GARDEN_READ_BACKEND") as? String
        let raw = (envValue ?? plistValue ?? "legacy")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if raw != "v2" {
            AppLog.warning(
                "Legacy backend is disabled by migration policy. Forcing GARDEN_READ_BACKEND=v2.",
                category: .sync
            )
        }
        return .v2
    }

    @discardableResult
    private func loadReadSnapshotFromV2() -> Bool {
        guard readBackend == .v2, let localV2DB else {
            return false
        }

        do {
            let siteID = try localV2DB.currentSiteID()
            let speciesRecords = try localV2DB.fetchSpeciesPrivateActive(siteID: siteID)
            let cultivarRecords = try localV2DB.fetchCultivarsActive(siteID: siteID)
            let individualRecords = try localV2DB.fetchIndividualsActive(siteID: siteID)
            let v2Species = CanopyUIAdapters.toGardenTaxa(
                speciesRecords: speciesRecords,
                cultivarRecords: cultivarRecords,
                individuals: individualRecords
            )
            let v2Plants = CanopyUIAdapters.toGardenPlants(
                individuals: individualRecords,
                speciesRecords: speciesRecords,
                cultivarRecords: cultivarRecords
            )

            species = v2Species
            plants = v2Plants
            return true
        } catch {
            AppLog.error("loadReadSnapshotFromV2: \(error)", category: .database)
            return false
        }
    }

    private func roundedCoordinate(_ value: Double, decimals: Int = 6) -> Double {
        let scale = pow(10.0, Double(decimals))
        return (value * scale).rounded() / scale
    }

    func loadLocalData() {
        if readBackend == .v2 {
            let loaded = loadReadSnapshotFromV2()
            if loaded {
                AppLog.info("loadLocalData via LocalV2 (\(plants.count) individus)", category: .sync)
            } else {
                AppLog.warning("loadLocalData v2: snapshot indisponible", category: .sync)
                plants = []
            }
            return
        }

        do {
            let loaded = try withDatabaseLock { try db.fetchPlants() }
            AppLog.debug("loadLocalData plants=\(loaded.count)", category: .sync)
            plants = loaded
        } catch {
            AppLog.error("loadLocalData: \(error)", category: .database)
            plants = []
        }
    }

    func loadLocalSpecies() {
        if readBackend == .v2 {
            let loaded = loadReadSnapshotFromV2()
            if loaded {
                AppLog.info("loadLocalSpecies via LocalV2 (\(species.count) espèces)", category: .sync)
            } else {
                AppLog.warning("loadLocalSpecies v2: snapshot indisponible", category: .sync)
                species = []
            }
            return
        }

        do {
            let loaded = try withDatabaseLock { try db.fetchSpecies() }
            species = loaded
            auditImagePipeline(reason: "loadLocalSpecies")
        } catch {
            AppLog.error("loadLocalSpecies: \(error)", category: .database)
            species = []
        }
    }

    private func auditImagePipeline(reason: String, force: Bool = false) {
        if didAuditImages && !force {
            return
        }
        didAuditImages = true
        do {
            let diag = try withDatabaseLock { try db.fetchImageDiagnostics(sampleLimit: 5) }
            print("[ImageAudit] reason=\(reason) species=\(diag.speciesCount) species_with_image=\(diag.speciesWithImage) active_with_image=\(diag.speciesWithImageActive) plants=\(diag.plantCount) plants_with_local_image=\(diag.plantsWithLocalImage)")
            if !diag.sampleSpeciesImageURLs.isEmpty {
                print("[ImageAudit] sample_urls=\(diag.sampleSpeciesImageURLs.joined(separator: " | "))")
            } else {
                print("[ImageAudit] sample_urls=empty")
            }

            let baseSpecies = try withDatabaseLock { try db.fetchSpeciesBase() }
            let resolvedCount = baseSpecies.filter { resolvedImageURL(from: $0.imageURL) != nil }.count
            print("[ImageAudit] fetchSpeciesBase count=\(baseSpecies.count) resolved_url_count=\(resolvedCount)")

            if let firstURL = diag.sampleSpeciesImageURLs.first, let url = resolvedImageURL(from: firstURL) {
                Task.detached {
                    do {
                        _ = try await PersistentImageCache.shared.loadImage(for: url)
                        print("[ImageAudit] load OK url=\(url.absoluteString)")
                    } catch {
                        let nsError = error as NSError
                        print("[ImageAudit] load FAIL url=\(url.absoluteString) error=\(nsError.domain)#\(nsError.code) \(nsError.localizedDescription)")
                    }
                }
            } else {
                print("[ImageAudit] no resolvable sample url")
            }
        } catch {
            print("[ImageAudit] error=\(error)")
        }
    }

    // MARK: - Read access for UI (Database stays private to Store)

    func fetchStats() -> JardinStats {
        if readBackend == .v2 {
            let zoneCount = Set(plants.compactMap { $0.zone?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }).count
            return JardinStats(
                plantCount: plants.count,
                speciesCount: species.count,
                zoneCount: zoneCount,
                hiveCount: 0,
                colonyCount: 0
            )
        }

        do {
            return try withDatabaseLock { try db.fetchStats() }
        } catch {
            AppLog.error("fetchStats: \(error)", category: .database)
            return .empty
        }
    }

    func fetchSpeciesBase() -> [GardenTaxon] {
        if readBackend == .v2 {
            return species
        }

        do {
            return try withDatabaseLock { try db.fetchSpeciesBase() }
        } catch {
            AppLog.error("fetchSpeciesBase: \(error)", category: .database)
            return []
        }
    }

    func fetchSpeciesDetail(speciesId: Int32) -> GardenTaxonDetailData? {
        if readBackend == .v2,
           let base = species.first(where: { $0.id == Int(speciesId) }) {
            do {
                let siteID = try localV2DB?.currentSiteID()
                let cultivars = try localV2DB?.fetchCultivarsActive(siteID: siteID) ?? []
                let individualRecords = try localV2DB?.fetchIndividualsActive(siteID: siteID) ?? []
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
                AppLog.error("fetchSpeciesDetail(speciesId) v2: \(error)", category: .database)
            }
        }

        do {
            return try withDatabaseLock { try db.fetchSpeciesDetail(speciesId: speciesId) }
        } catch {
            AppLog.error("fetchSpeciesDetail(speciesId): \(error)", category: .database)
            return nil
        }
    }

    func fetchSpeciesDetail(latinName: String) -> GardenTaxonDetailData? {
        if readBackend == .v2,
           let base = species.first(where: { $0.latinName.caseInsensitiveCompare(latinName) == .orderedSame }) {
            return fetchSpeciesDetail(speciesId: Int32(base.id))
        }

        do {
            return try withDatabaseLock { try db.fetchSpeciesDetail(latinName: latinName) }
        } catch {
            AppLog.error("fetchSpeciesDetail(latinName): \(error)", category: .database)
            return nil
        }
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

    func fetchHives() -> [GardenHive] {
        do {
            return try withDatabaseLock { try db.fetchHives() }
        } catch {
            AppLog.error("fetchHives: \(error)", category: .database)
            return []
        }
    }

    func fetchHive(id: Int) -> GardenHive? {
        do {
            return try withDatabaseLock { try db.fetchHive(id: id) }
        } catch {
            AppLog.error("fetchHive: \(error)", category: .database)
            return nil
        }
    }

    func generateAutomaticPlantLabel(
        speciesId: Int,
        varietyId: Int?,
        existingPlantID: Int?
    ) throws -> String {
        if readBackend == .v2 {
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

        return try withDatabaseLock {
            try db.generateAutomaticPlantLabel(
                speciesId: speciesId,
                varietyId: varietyId,
                existingPlantID: existingPlantID
            )
        }
    }

    func createPlant(_ input: PlantWriteInput) {
        do {
            if readBackend == .v2 {
                try createPlantV2(input)
                loadLocalData()
                syncWithSupabase()
                return
            }

            _ = try withDatabaseLock {
                let autoLabel = try db.generateAutomaticPlantLabel(
                    speciesId: input.speciesId,
                    varietyId: input.varietyId,
                    existingPlantID: nil
                )
                return try db.savePlant(id: nil, input: input, label: autoLabel)
            }
            loadLocalData()
            syncWithSupabase()
        } catch {
            AppLog.error("Erreur createPlant: \(error)", category: .database)
        }
    }

    func updatePlant(_ plant: GardenPlant, with input: PlantWriteInput) {
        do {
            if readBackend == .v2 {
                try updatePlantV2(plant, input: input)
                loadLocalData()
                syncWithSupabase()
                return
            }

            try withDatabaseLock {
                let autoLabel = try db.generateAutomaticPlantLabel(
                    speciesId: input.speciesId,
                    varietyId: input.varietyId,
                    existingPlantID: plant.id
                )
                _ = try db.savePlant(id: plant.id, input: input, label: autoLabel)
            }
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
            if readBackend == .v2 {
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
                    heightCurrent: canopyDiameterMeters,
                    latitude: latRounded,
                    longitude: lonRounded
                )
                try updatePlantV2(plant, input: input)
                loadLocalData()
                syncWithSupabase()
                return
            }

            try withDatabaseLock {
                try db.updatePlantGeometry(
                    id: plantID,
                    latitude: latRounded,
                    longitude: lonRounded,
                    envergureCurrent: canopyDiameterMeters
                )
            }
            loadLocalData()
            syncWithSupabase()
        } catch {
            AppLog.error("Erreur updatePlantGeometry: \(error)", category: .database)
        }
    }

    @discardableResult
    func createSpecies(_ input: SpeciesWriteInput) -> Int? {
        do {
            if readBackend == .v2 {
                let newID = try createSpeciesV2(input)
                loadLocalSpecies()
                syncWithSupabase()
                return newID
            }

            let newId = try withDatabaseLock { try db.saveSpecies(id: nil, input: input) }
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
            if readBackend == .v2 {
                try updateSpeciesV2(species: species, input: input)
                loadLocalSpecies()
                syncWithSupabase()
                return
            }

            try withDatabaseLock {
                _ = try db.saveSpecies(id: species.id, input: input)
            }
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
            if readBackend == .v2 {
                try updateSpeciesCommonFieldsV2(latinName: latinName, speciesId: speciesId, input: input)
                loadLocalSpecies()
                syncWithSupabase()
                return
            }

            try withDatabaseLock {
                try db.updateSpeciesCommonFields(
                    forLatinName: latinName,
                    fallbackSpeciesId: speciesId,
                    with: input
                )
            }
            loadLocalSpecies()
            syncWithSupabase()
        } catch {
            AppLog.error("Erreur updateSpeciesCommonFields(input): \(error)", category: .database)
        }
    }

    @discardableResult
    func updateCultivar(id: Int, with input: CultivarWriteInput) -> Bool {
        do {
            if readBackend == .v2 {
                try updateCultivarV2(id: id, input: input)
                loadLocalSpecies()
                loadLocalData()
                syncWithSupabase()
                return true
            }

            try withDatabaseLock { _ = try db.saveCultivar(id: id, speciesId: nil, input: input) }
            loadLocalSpecies()
            syncWithSupabase()
            return true
        } catch {
            AppLog.error("Erreur updateCultivar(input): \(error)", category: .database)
            return false
        }
    }

    @discardableResult
    func createCultivar(speciesId: Int, input: CultivarWriteInput) -> Bool {
        do {
            if readBackend == .v2 {
                try createCultivarV2(speciesId: speciesId, input: input)
                loadLocalSpecies()
                loadLocalData()
                syncWithSupabase()
                return true
            }

            _ = try withDatabaseLock { try db.saveCultivar(id: nil, speciesId: speciesId, input: input) }
            loadLocalSpecies()
            loadLocalData()
            syncWithSupabase()
            return true
        } catch {
            AppLog.error("Erreur createCultivar(input): \(error)", category: .database)
            return false
        }
    }

    func deleteCultivar(id: Int32) -> DeleteCultivarResult {
        do {
            if readBackend == .v2 {
                let result = try deleteCultivarV2(id: Int(id))
                if result == .success {
                    loadLocalSpecies()
                    loadLocalData()
                    syncWithSupabase()
                }
                return result
            }

            let deleted = try withDatabaseLock { try db.deleteCultivarRecord(id: id) }
            guard deleted else {
                return .linkedToPlants
            }
            loadLocalSpecies()
            loadLocalData()
            syncWithSupabase()
            return .success
        } catch {
            AppLog.error("Erreur deleteCultivar: \(error)", category: .database)
            return .failure
        }
    }

    func deleteCultivar(id: Int) -> DeleteCultivarResult {
        deleteCultivar(id: Int32(id))
    }

    func deleteSpecies(id: Int32) -> GardenDeleteSpeciesResult {
        if readBackend == .v2 {
            do {
                let result = try deleteSpeciesV2(id: Int(id))
                if result == .success {
                    loadLocalSpecies()
                    loadLocalData()
                    syncWithSupabase()
                }
                return result
            } catch {
                AppLog.error("Erreur deleteSpecies v2: \(error)", category: .database)
                return .failure
            }
        }

        do {
            let result = try withDatabaseLock { try db.deleteSpeciesRecord(id: id) }
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

    // MARK: - V2 mutations

    private enum V2MutationError: Error {
        case localDatabaseUnavailable
        case noCurrentSite
        case speciesNotFound
        case cultivarNotFound
        case individualNotFound
        case missingRemoteID
        case payloadEncodingFailed
    }

    private func requireV2Context() throws -> (LocalV2Database, String) {
        guard let localV2DB else { throw V2MutationError.localDatabaseUnavailable }
        guard let siteID = try localV2DB.currentSiteID(), !siteID.isEmpty else {
            throw V2MutationError.noCurrentSite
        }
        return (localV2DB, siteID)
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
            throw V2MutationError.payloadEncodingFailed
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
        localV2DB: LocalV2Database
    ) throws -> LocalV2CultivarRecord? {
        let cultivars = try localV2DB.fetchCultivarsActive(siteID: siteID)
        return cultivars.first { stableIntID(from: $0.remoteID) == stableID }
    }

    private func resolveCultivarRemoteID(
        stableID: Int?,
        siteID: String,
        localV2DB: LocalV2Database,
        existing: LocalV2IndividualRecord?
    ) throws -> String? {
        if let stableID {
            guard let cultivar = try cultivarByStableID(stableID, siteID: siteID, localV2DB: localV2DB) else {
                throw V2MutationError.cultivarNotFound
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
            CanopySchema.SpeciesPrivateFields.envergureMin: .null,
            CanopySchema.SpeciesPrivateFields.envergureMax: .null,
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

    private func createSpeciesV2(_ input: SpeciesWriteInput) throws -> Int {
        let (localV2DB, siteID) = try requireV2Context()
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

        try localV2DB.upsertSpeciesPrivateRows(siteID: siteID, rows: [row])
        try localV2DB.enqueueOutboxOperation(
            siteID: siteID,
            entityType: CanopySchema.Tables.speciesPrivate,
            entityRemoteID: remoteID,
            opType: "upsert",
            payloadJSON: try payloadJSONString(from: row)
        )
        return stableIntID(from: remoteID)
    }

    private func updateSpeciesV2(species: GardenTaxon, input: SpeciesWriteInput) throws {
        let (localV2DB, siteID) = try requireV2Context()
        let remoteID = species.uuid ?? speciesByID(species.id)?.uuid
        guard let remoteID, !remoteID.isEmpty else { throw V2MutationError.missingRemoteID }

        let now = currentTimestampString()
        let createdAt = try localV2DB.fetchSpeciesPrivateRecord(remoteID: remoteID)?.createdAt ?? now
        let row = makeSpeciesRow(
            remoteID: remoteID,
            siteID: siteID,
            createdAt: createdAt,
            updatedAt: now,
            deletedAt: nil,
            input: input
        )

        try localV2DB.upsertSpeciesPrivateRows(siteID: siteID, rows: [row])
        try localV2DB.enqueueOutboxOperation(
            siteID: siteID,
            entityType: CanopySchema.Tables.speciesPrivate,
            entityRemoteID: remoteID,
            opType: "upsert",
            payloadJSON: try payloadJSONString(from: row)
        )
    }

    private func updateSpeciesCommonFieldsV2(
        latinName: String,
        speciesId: Int?,
        input: SpeciesCommonWriteInput
    ) throws {
        let target = speciesId.flatMap { speciesByID($0) }
            ?? species.first(where: { $0.latinName.caseInsensitiveCompare(latinName) == .orderedSame })
        guard let target else { throw V2MutationError.speciesNotFound }

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
            floweringPeriod: input.floweringPeriod,
            fruitingPeriod: input.fruitingPeriod,
            varietyNotes: nil
        )
        try updateSpeciesV2(species: target, input: writeInput)
    }

    private func makeIndividualMetadata(
        input: PlantWriteInput,
        existing: LocalV2IndividualRecord?
    ) -> CanopyJSONValue {
        var object: [String: CanopyJSONValue] = [:]
        if let value = nilIfEmpty(input.microSite) { object["micro_site"] = .string(value) }
        if let value = nilIfEmpty(input.exposureLocal) { object["exposure_local"] = .string(value) }
        if let value = nilIfEmpty(input.soilLocal) { object["soil_local"] = .string(value) }
        if let value = nilIfEmpty(input.acquisitionType) { object["acquisition_type"] = .string(value) }
        if let value = nilIfEmpty(input.acquisitionSource) { object["acquisition_source"] = .string(value) }
        if let value = nilIfEmpty(input.careNotes) { object["care_notes"] = .string(value) }
        if let value = input.heightCurrent { object["height_current"] = .double(value) }
        if let value = input.varietyId { object["legacy_variety_id"] = .int(value) }

        if object.isEmpty, let raw = existing?.metadataJSON, let data = raw.data(using: .utf8) {
            if let previous = try? JSONDecoder().decode([String: CanopyJSONValue].self, from: data) {
                return .object(previous)
            }
        }

        return object.isEmpty ? .null : .object(object)
    }

    private func makeIndividualRow(
        remoteID: String,
        siteID: String,
        speciesPrivateID: String?,
        cultivarID: String?,
        createdAt: String,
        updatedAt: String,
        deletedAt: String?,
        input: PlantWriteInput,
        existing: LocalV2IndividualRecord?,
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

    private func createPlantV2(_ input: PlantWriteInput) throws {
        let (localV2DB, siteID) = try requireV2Context()
        guard let species = speciesByID(input.speciesId) else { throw V2MutationError.speciesNotFound }
        guard let speciesRemoteID = species.uuid, !speciesRemoteID.isEmpty else { throw V2MutationError.missingRemoteID }

        let remoteID = UUID().uuidString.lowercased()
        let now = currentTimestampString()
        let label = try generateAutomaticPlantLabel(speciesId: input.speciesId, varietyId: input.varietyId, existingPlantID: nil)
        let cultivarRemoteID = try resolveCultivarRemoteID(
            stableID: input.varietyId,
            siteID: siteID,
            localV2DB: localV2DB,
            existing: nil
        )
        let row = makeIndividualRow(
            remoteID: remoteID,
            siteID: siteID,
            speciesPrivateID: speciesRemoteID,
            cultivarID: cultivarRemoteID,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            input: input,
            existing: nil,
            label: label
        )

        try localV2DB.upsertIndividualsRows(siteID: siteID, rows: [row])
        try localV2DB.enqueueOutboxOperation(
            siteID: siteID,
            entityType: CanopySchema.Tables.individuals,
            entityRemoteID: remoteID,
            opType: "upsert",
            payloadJSON: try payloadJSONString(from: row)
        )
    }

    private func updatePlantV2(_ plant: GardenPlant, input: PlantWriteInput) throws {
        let (localV2DB, siteID) = try requireV2Context()
        guard let remoteID = plant.uuid, !remoteID.isEmpty else { throw V2MutationError.missingRemoteID }
        guard let species = speciesByID(input.speciesId), let speciesRemoteID = species.uuid, !speciesRemoteID.isEmpty else {
            throw V2MutationError.speciesNotFound
        }

        let existing = try localV2DB.fetchIndividualRecord(remoteID: remoteID)
        let now = currentTimestampString()
        let cultivarRemoteID = try resolveCultivarRemoteID(
            stableID: input.varietyId,
            siteID: siteID,
            localV2DB: localV2DB,
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
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            deletedAt: nil,
            input: input,
            existing: existing,
            label: label
        )

        try localV2DB.upsertIndividualsRows(siteID: siteID, rows: [row])
        try localV2DB.enqueueOutboxOperation(
            siteID: siteID,
            entityType: CanopySchema.Tables.individuals,
            entityRemoteID: remoteID,
            opType: "upsert",
            payloadJSON: try payloadJSONString(from: row)
        )
    }

    private func deletePlantV2(_ plant: GardenPlant) throws {
        let (localV2DB, siteID) = try requireV2Context()
        guard let remoteID = plant.uuid, !remoteID.isEmpty else { throw V2MutationError.missingRemoteID }
        guard let existing = try localV2DB.fetchIndividualRecord(remoteID: remoteID) else {
            throw V2MutationError.individualNotFound
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
            heightCurrent: nil,
            latitude: existing.locationLat,
            longitude: existing.locationLng
        )
        let row = makeIndividualRow(
            remoteID: remoteID,
            siteID: siteID,
            speciesPrivateID: existing.speciesPrivateID,
            cultivarID: existing.cultivarID,
            createdAt: existing.createdAt,
            updatedAt: now,
            deletedAt: now,
            input: surrogateInput,
            existing: existing,
            label: existing.label ?? existing.code ?? plant.label ?? "#\(plant.id)"
        )

        try localV2DB.upsertIndividualsRows(siteID: siteID, rows: [row])
        try localV2DB.enqueueOutboxOperation(
            siteID: siteID,
            entityType: CanopySchema.Tables.individuals,
            entityRemoteID: remoteID,
            opType: "delete",
            payloadJSON: "{}"
        )
    }

    private func deleteSpeciesV2(id: Int) throws -> GardenDeleteSpeciesResult {
        guard let target = speciesByID(id) else { return .failure }
        if plants.contains(where: { $0.speciesID == id }) {
            return .linkedToPlants
        }

        let (localV2DB, siteID) = try requireV2Context()
        guard let remoteID = target.uuid, !remoteID.isEmpty else { throw V2MutationError.missingRemoteID }
        guard let existing = try localV2DB.fetchSpeciesPrivateRecord(remoteID: remoteID) else {
            throw V2MutationError.speciesNotFound
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

        try localV2DB.upsertSpeciesPrivateRows(siteID: siteID, rows: [row])
        try localV2DB.enqueueOutboxOperation(
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
        existing: LocalV2CultivarRecord?
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

    private func createCultivarV2(speciesId: Int, input: CultivarWriteInput) throws {
        let (localV2DB, siteID) = try requireV2Context()
        guard let species = speciesByID(speciesId),
              let speciesRemoteID = species.uuid,
              !speciesRemoteID.isEmpty else {
            throw V2MutationError.speciesNotFound
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

        try localV2DB.upsertCultivarsRows(siteID: siteID, rows: [row])
        try localV2DB.enqueueOutboxOperation(
            siteID: siteID,
            entityType: CanopySchema.Tables.cultivars,
            entityRemoteID: remoteID,
            opType: "upsert",
            payloadJSON: try payloadJSONString(from: row)
        )
    }

    private func updateCultivarV2(id: Int, input: CultivarWriteInput) throws {
        let (localV2DB, siteID) = try requireV2Context()
        guard let existing = try cultivarByStableID(id, siteID: siteID, localV2DB: localV2DB) else {
            throw V2MutationError.cultivarNotFound
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

        try localV2DB.upsertCultivarsRows(siteID: siteID, rows: [row])
        try localV2DB.enqueueOutboxOperation(
            siteID: siteID,
            entityType: CanopySchema.Tables.cultivars,
            entityRemoteID: existing.remoteID,
            opType: "upsert",
            payloadJSON: try payloadJSONString(from: row)
        )
    }

    private func deleteCultivarV2(id: Int) throws -> DeleteCultivarResult {
        let (localV2DB, siteID) = try requireV2Context()
        guard let existing = try cultivarByStableID(id, siteID: siteID, localV2DB: localV2DB) else {
            return .failure
        }

        let individuals = try localV2DB.fetchIndividualsActive(siteID: siteID)
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

        try localV2DB.upsertCultivarsRows(siteID: siteID, rows: [row])
        try localV2DB.enqueueOutboxOperation(
            siteID: siteID,
            entityType: CanopySchema.Tables.cultivars,
            entityRemoteID: existing.remoteID,
            opType: "delete",
            payloadJSON: "{}"
        )
        return .success
    }
}

extension GardenStore {
    private enum SyncTable: String {
        case species
        case cultivars
        case plants
    }

    private struct SyncMarkers {
        let species: String?
        let cultivars: String?
        let plants: String?

        var oldestForPull: String? {
            [species, cultivars, plants].compactMap { $0 }.min()
        }
    }

    private struct LocalSyncChanges {
        let species: [SpeciesDTO]
        let cultivars: [CultivarDTO]
        let plants: [PlantDTO]

        var hasChanges: Bool {
            !species.isEmpty || !cultivars.isEmpty || !plants.isEmpty
        }
    }

    private func currentTimestampString() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private func elapsedMilliseconds(since start: Date) -> Int {
        Int((Date().timeIntervalSince(start) * 1000).rounded())
    }

    private func maxUpdatedAt(_ values: [String?]) -> String? {
        values
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
            .max()
    }

    private func syncLog(_ message: String, runID: String? = nil) {
        let prefix = runID.map { "[GardenSync run=\($0)]" } ?? "[GardenSync]"
        let line = "\(prefix) \(message)"
        print(line)
        AppLog.info(line, category: .sync)
    }

    private func sanitizedSyncMarker(_ value: String?) -> String? {
        guard value?.contains("T") == true else { return nil }
        return value
    }

    private func loadSyncMarkers() -> SyncMarkers {
        let rawSpecies = try? withDatabaseLock { try db.getLastSyncedAt(for: SyncTable.species.rawValue) }
        let rawCultivars = try? withDatabaseLock { try db.getLastSyncedAt(for: SyncTable.cultivars.rawValue) }
        let rawPlants = try? withDatabaseLock { try db.getLastSyncedAt(for: SyncTable.plants.rawValue) }
        return SyncMarkers(
            species: sanitizedSyncMarker(rawSpecies),
            cultivars: sanitizedSyncMarker(rawCultivars),
            plants: sanitizedSyncMarker(rawPlants)
        )
    }

    private func applyRemoteChanges(
        _ remote: (species: [SpeciesDTO], cultivars: [CultivarDTO], plants: [PlantDTO])
    ) throws {
        try withDatabaseLock {
            try db.syncSpeciesFromSupabase(remoteSpecies: remote.species)
            try db.syncCultivarsFromSupabase(remoteCultivars: remote.cultivars)
            try db.syncPlantsFromSupabase(remotePlants: remote.plants)
            try db.repairLegacyUUIDs()
        }
    }

    private func collectLocalChanges(since markers: SyncMarkers) -> LocalSyncChanges {
        let localSpecies = (try? withDatabaseLock { try db.fetchLocalSpeciesChanges(since: markers.species) }) ?? []
        let localCultivars = (try? withDatabaseLock { try db.fetchLocalCultivarChanges(since: markers.cultivars) }) ?? []
        let localPlants = (try? withDatabaseLock { try db.fetchLocalPlantChanges(since: markers.plants) }) ?? []
        return LocalSyncChanges(species: localSpecies, cultivars: localCultivars, plants: localPlants)
    }

    private func pushLocalChanges(_ changes: LocalSyncChanges, runID: String) async -> Bool {
        guard changes.hasChanges else {
            syncLog("PUSH skip (aucun changement local)", runID: runID)
            return true
        }

        let startedAt = Date()
        do {
            syncLog(
                "PUSH start species=\(changes.species.count) cultivars=\(changes.cultivars.count) plants=\(changes.plants.count)",
                runID: runID
            )
            try await GardenSyncService.shared.pushLocalChanges(
                (species: changes.species, cultivars: changes.cultivars, plants: changes.plants)
            )
            syncLog(
                "PUSH done in \(elapsedMilliseconds(since: startedAt)) ms",
                runID: runID
            )
            return true
        } catch {
            syncLog(
                "PUSH failed in \(elapsedMilliseconds(since: startedAt)) ms error=\(error)",
                runID: runID
            )
            AppLog.warning("Erreur push vers Supabase: \(error)", category: .sync)
            return false
        }
    }

    private func updateSyncState(now: String) {
        do {
            try withDatabaseLock {
                try db.updateLastSyncedAt(for: SyncTable.species.rawValue, value: now)
                try db.updateLastSyncedAt(for: SyncTable.cultivars.rawValue, value: now)
                try db.updateLastSyncedAt(for: SyncTable.plants.rawValue, value: now)
            }
        } catch {
            AppLog.error("updateSyncState: \(error)", category: .database)
        }
    }

    private func uniqueImageURLs(
        plants: [GardenPlant],
        species: [GardenTaxon]
    ) -> [URL] {
        let plantURLs = plants.compactMap { resolvedPlantImageURL(local: $0.imageLocal, remote: $0.speciesImageURL) }
        let speciesURLs = species.compactMap { resolvedImageURL(from: $0.imageURL) }

        var seen = Set<String>()
        var unique: [URL] = []
        for url in (plantURLs + speciesURLs) {
            let key = url.absoluteString
            if seen.insert(key).inserted {
                unique.append(url)
            }
        }
        return unique
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
                if self.readBackend == .v2, let canopyV2Sync = self.canopyV2Sync {
                    let pullStartedAt = Date()
                    let summary = try await canopyV2Sync.pullLatest()
                    let duration = elapsedMilliseconds(since: pullStartedAt)

                    if let summary {
                        syncLog(
                            """
                            PULL v2 done in \(duration) ms \
                            site=\(summary.siteID) \
                            species=\(summary.speciesCount) cultivars=\(summary.cultivarsCount) individuals=\(summary.individualsCount) \
                            max_species=\(summary.speciesMaxUpdatedAt ?? "nil") \
                            max_cultivars=\(summary.cultivarsMaxUpdatedAt ?? "nil") \
                            max_individuals=\(summary.individualsMaxUpdatedAt ?? "nil")
                            """,
                            runID: runID
                        )
                    } else {
                        syncLog("PULL v2 done in \(duration) ms no_membership", runID: runID)
                    }

                    await MainActor.run {
                        self.loadLocalData()
                        self.loadLocalSpecies()
                        self.lastSyncDate = Date()
                        self.lastSyncMessage = summary == nil
                            ? "Synchro v2: aucun site membre actif"
                            : "Synchro v2 terminée"
                    }

                    syncLog(
                        "END success (v2) in \(elapsedMilliseconds(since: syncStartedAt)) ms",
                        runID: runID
                    )
                    return
                }

                if self.readBackend != .v2 {
                    syncLog("Legacy sync path is disabled by migration policy.", runID: runID)
                    await MainActor.run {
                        self.lastSyncMessage = "Legacy sync disabled (v2 required)"
                    }
                    return
                }

                let markers = loadSyncMarkers()
                syncLog(
                    "MARKERS species=\(markers.species ?? "nil") cultivars=\(markers.cultivars ?? "nil") plants=\(markers.plants ?? "nil")",
                    runID: runID
                )
                AppLog.debug(
                    "lastSpecies=\(markers.species ?? "nil") lastCultivars=\(markers.cultivars ?? "nil") lastPlants=\(markers.plants ?? "nil")",
                    category: .sync
                )

                AppLog.info("Fetch Supabase depuis \(markers.oldestForPull ?? "nil")", category: .sync)
                let pullStartedAt = Date()
                let remote = try await GardenSyncService.shared.fetchChangesSince(markers.oldestForPull)
                syncLog(
                    """
                    PULL done in \(elapsedMilliseconds(since: pullStartedAt)) ms \
                    species=\(remote.species.count) cultivars=\(remote.cultivars.count) plants=\(remote.plants.count) \
                    max_species=\(maxUpdatedAt(remote.species.map(\.updatedAt)) ?? "nil") \
                    max_cultivars=\(maxUpdatedAt(remote.cultivars.map(\.updatedAt)) ?? "nil") \
                    max_plants=\(maxUpdatedAt(remote.plants.map(\.updatedAt)) ?? "nil")
                    """,
                    runID: runID
                )
                AppLog.info("Pull recu species=\(remote.species.count) cultivars=\(remote.cultivars.count) plants=\(remote.plants.count)", category: .sync)

                do {
                    let applyStartedAt = Date()
                    try applyRemoteChanges(remote)
                    if force {
                        let forceStartedAt = Date()
                        try withDatabaseLock {
                            try self.db.forceUpdateSpeciesImagesFromSupabase(remoteSpecies: remote.species)
                        }
                        syncLog(
                            "FORCE image_url from Supabase in \(elapsedMilliseconds(since: forceStartedAt)) ms",
                            runID: runID
                        )
                    }
                    syncLog(
                        "APPLY sqlite done in \(elapsedMilliseconds(since: applyStartedAt)) ms",
                        runID: runID
                    )
                } catch {
                    AppLog.error("Erreur upsert SQLite pull: \(error)", category: .database)
                    syncLog("APPLY sqlite failed error=\(error)", runID: runID)
                    throw error
                }

                let collectStartedAt = Date()
                let changes = collectLocalChanges(since: markers)
                syncLog(
                    "COLLECT local in \(elapsedMilliseconds(since: collectStartedAt)) ms species=\(changes.species.count) cultivars=\(changes.cultivars.count) plants=\(changes.plants.count)",
                    runID: runID
                )
                AppLog.info(
                    "Changements locaux vers Supabase species=\(changes.species.count) cultivars=\(changes.cultivars.count) plants=\(changes.plants.count)",
                    category: .sync
                )
                let pushSucceeded = await pushLocalChanges(changes, runID: runID)

                if pushSucceeded {
                    let now = currentTimestampString()
                    let syncStateStartedAt = Date()
                    updateSyncState(now: now)
                    syncLog(
                        "SYNC_STATE updated_at=\(now) in \(elapsedMilliseconds(since: syncStateStartedAt)) ms",
                        runID: runID
                    )
                    AppLog.debug("sync_state maj \(now)", category: .sync)
                } else {
                    AppLog.warning("sync_state non mis a jour (push partiel/echoue): les changements locaux seront retentes.", category: .sync)
                    syncLog("SYNC_STATE skipped (push failed)", runID: runID)
                }

                await MainActor.run {
                    self.loadLocalData()
                    self.loadLocalSpecies()
                    self.lastSyncDate = Date()
                    self.lastSyncMessage = pushSucceeded
                        ? "Synchro terminée"
                        : "Synchro partielle: push à retenter"
                }

                if refreshImages {
                    await MainActor.run {
                        self.lastSyncMessage = "Synchro terminée, préchargement images..."
                    }
                    let preloadStartedAt = Date()
                    let latestPlants = (try? withDatabaseLock { try self.db.fetchPlants() }) ?? []
                    let latestSpecies = (try? withDatabaseLock { try self.db.fetchSpecies() }) ?? []
                    let urls = uniqueImageURLs(plants: latestPlants, species: latestSpecies)

                    let preload = await PersistentImageCache.shared.preloadImages(urls: urls)
                    syncLog(
                        "IMAGES preload done in \(elapsedMilliseconds(since: preloadStartedAt)) ms loaded=\(preload.loaded) not_found=\(preload.notFound) total=\(urls.count)",
                        runID: runID
                    )
                    await MainActor.run {
                        self.lastSyncMessage = "Synchro terminée, images: \(preload.loaded)/\(urls.count) (\(preload.notFound) introuvables)"
                    }
                }
                syncLog(
                    "END success in \(elapsedMilliseconds(since: syncStartedAt)) ms",
                    runID: runID
                )
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
        if readBackend == .v2 {
            do {
                try deletePlantV2(plant)
                loadLocalData()
                syncWithSupabase()
            } catch {
                AppLog.error("Erreur deletePlant v2: \(error)", category: .database)
            }
            return
        }

        do {
            try withDatabaseLock { try db.softDeletePlant(id: plant.id) }
            loadLocalData()
            syncWithSupabase()
        } catch {
            AppLog.error("Erreur deletePlant: \(error)", category: .database)
        }
    }
}
