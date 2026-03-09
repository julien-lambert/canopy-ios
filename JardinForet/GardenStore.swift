//
//  Untitled.swift
//  JardinForet
//
//  Created by Julien Lambert on 16/11/2025.
//

import Foundation

final class GardenStore: ObservableObject {
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
    private let dbLock = NSLock()
    private var syncTask: Task<Void, Never>?
    private var didAuditImages = false

    init(database: GardenDatabase = GardenDatabase()) {
        self.db = database
        AppLog.info("GardenStore init", category: .sync)
        // 1) Charger immédiatement les données locales depuis SQLite via GardenDatabase
        loadLocalData()
        loadLocalSpecies()
        
        // 2) Lancer une synchro Supabase → SQLite en arrière-plan
        syncWithSupabase()
    }

    private func withDatabaseLock<T>(_ operation: () throws -> T) rethrows -> T {
        dbLock.lock()
        defer { dbLock.unlock() }
        return try operation()
    }

    private func roundedCoordinate(_ value: Double, decimals: Int = 6) -> Double {
        let scale = pow(10.0, Double(decimals))
        return (value * scale).rounded() / scale
    }

    func loadLocalData() {
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
        do {
            return try withDatabaseLock { try db.fetchStats() }
        } catch {
            AppLog.error("fetchStats: \(error)", category: .database)
            return .empty
        }
    }

    func fetchSpeciesBase() -> [GardenTaxon] {
        do {
            return try withDatabaseLock { try db.fetchSpeciesBase() }
        } catch {
            AppLog.error("fetchSpeciesBase: \(error)", category: .database)
            return []
        }
    }

    func fetchSpeciesDetail(speciesId: Int32) -> GardenTaxonDetailData? {
        do {
            return try withDatabaseLock { try db.fetchSpeciesDetail(speciesId: speciesId) }
        } catch {
            AppLog.error("fetchSpeciesDetail(speciesId): \(error)", category: .database)
            return nil
        }
    }

    func fetchSpeciesDetail(latinName: String) -> GardenTaxonDetailData? {
        do {
            return try withDatabaseLock { try db.fetchSpeciesDetail(latinName: latinName) }
        } catch {
            AppLog.error("fetchSpeciesDetail(latinName): \(error)", category: .database)
            return nil
        }
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
        try withDatabaseLock {
            try db.generateAutomaticPlantLabel(
                speciesId: speciesId,
                varietyId: varietyId,
                existingPlantID: existingPlantID
            )
        }
    }

    func createPlant(_ input: PlantWriteInput) {
        do {
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
        do {
            try withDatabaseLock { try db.softDeletePlant(id: plant.id) }
            loadLocalData()
            syncWithSupabase()
        } catch {
            AppLog.error("Erreur deletePlant: \(error)", category: .database)
        }
    }
}
