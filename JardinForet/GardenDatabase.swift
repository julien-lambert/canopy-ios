import Foundation
import Combine
import GRDB
final class GardenDatabase: ObservableObject {
    private let dbPool: DatabasePool

    struct ImageDiagnostics {
        let speciesCount: Int
        let speciesWithImage: Int
        let speciesWithImageActive: Int
        let plantCount: Int
        let plantsWithLocalImage: Int
        let sampleSpeciesImageURLs: [String]
    }

    init() {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.busyMode = .timeout(5.0)

        do {
            let databaseURL = try Self.prepareLocalDatabaseURL()
            dbPool = try DatabasePool(path: databaseURL.path, configuration: configuration)
        } catch {
            AppLog.error("Initialisation base impossible: \(error)", category: .database)
            preconditionFailure("GardenDatabase init failed: \(error)")
        }
    }

    private static func prepareLocalDatabaseURL() throws -> URL {
        guard let bundledURL = Bundle.main.url(forResource: "jardin", withExtension: "db") else {
            throw NSError(
                domain: "GardenDatabase",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "jardin.db introuvable dans le bundle"]
            )
        }

        let fm = FileManager.default
        let docsURL = try fm.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let destURL = docsURL.appendingPathComponent("jardin.db")

        if !fm.fileExists(atPath: destURL.path) {
            try fm.copyItem(at: bundledURL, to: destURL)
            AppLog.info("Copie jardin.db vers \(destURL.path)", category: .database)
        }

        return destURL
    }

    private func nowISO8601() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private func labelCode3(from rawValue: String?, fallback: String) -> String {
        guard let rawValue else { return fallback }
        let folded = rawValue.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "fr_FR"))
        let lettersOnly = folded.unicodeScalars
            .filter { CharacterSet.letters.contains($0) }
            .map(String.init)
            .joined()
            .uppercased()
        guard !lettersOnly.isEmpty else { return fallback }
        let prefix = String(lettersOnly.prefix(3))
        if prefix.count >= 3 { return prefix }
        return prefix + String(repeating: "X", count: max(0, 3 - prefix.count))
    }

    private func parseLabelIndex(_ label: String, expectedPrefix: String) -> Int? {
        let normalizedPrefix = expectedPrefix + "-"
        guard label.hasPrefix(normalizedPrefix) else { return nil }
        let suffix = String(label.dropFirst(normalizedPrefix.count))
        return Int(suffix)
    }

    func generateAutomaticPlantLabel(speciesId: Int, varietyId: Int?, existingPlantID: Int?) throws -> String {
        try dbPool.read { db in
            let speciesName = try String.fetchOne(
                db,
                sql: "SELECT \(DBSpecies.columns.commonName.name) FROM \(DBSpecies.databaseTableName) WHERE \(DBSpecies.columns.id.name) = ? LIMIT 1",
                arguments: [speciesId]
            )
            let cultivarName: String?
            if let varietyId {
                cultivarName = try String.fetchOne(
                    db,
                    sql: "SELECT \(DBCultivar.columns.name.name) FROM \(DBCultivar.databaseTableName) WHERE \(DBCultivar.columns.id.name) = ? LIMIT 1",
                    arguments: [varietyId]
                )
            } else {
                cultivarName = nil
            }

            let speciesCode = labelCode3(from: speciesName, fallback: "PLT")
            let cultivarCode = labelCode3(from: cultivarName, fallback: "TYP")
            let prefix = "\(speciesCode)-\(cultivarCode)"

            if let existingPlantID {
                let existingLabel = try String.fetchOne(
                    db,
                    sql: "SELECT \(DBPlant.columns.label.name) FROM \(DBPlant.databaseTableName) WHERE \(DBPlant.columns.id.name) = ? LIMIT 1",
                    arguments: [existingPlantID]
                )
                if let existingLabel,
                   let existingIndex = parseLabelIndex(existingLabel, expectedPrefix: prefix) {
                    return String(format: "%@-%03d", prefix, existingIndex)
                }
            }

            var sql = "SELECT \(DBPlant.columns.label.name) FROM \(DBPlant.databaseTableName) WHERE COALESCE(\(DBPlant.columns.deleted.name), 0) = 0 AND \(DBPlant.columns.label.name) LIKE ?"
            var args: StatementArguments = ["\(prefix)-%"]
            if let existingPlantID {
                sql += " AND \(DBPlant.columns.id.name) != ?"
                args += [existingPlantID]
            }
            let labels = try String.fetchAll(db, sql: sql, arguments: args)
            let maxIndex = labels.compactMap { parseLabelIndex($0, expectedPrefix: prefix) }.max() ?? 0
            return String(format: "%@-%03d", prefix, maxIndex + 1)
        }
    }

    func savePlant(id: Int?, input: PlantWriteInput, label: String?) throws -> Int {
        let now = nowISO8601()
        return try dbPool.write { db in
            if let id {
                guard var plant = try DBPlant.fetchOne(db, key: id) else {
                    throw NSError(domain: "GardenDatabase", code: 110, userInfo: [NSLocalizedDescriptionKey: "Plante introuvable"])
                }
                plant.applyWriteInput(input, label: label, updatedAt: now)
                try plant.update(db)
                return id
            }

            var plant = DBPlant.makeNew(from: input, label: label, updatedAt: now)
            try plant.insert(db)
            return Int(plant.id ?? 0)
        }
    }

    func updatePlantGeometry(id: Int, latitude: Double, longitude: Double, envergureCurrent: Double?) throws {
        try dbPool.write { db in
            guard var plant = try DBPlant.fetchOne(db, key: id) else {
                throw NSError(domain: "GardenDatabase", code: 113, userInfo: [NSLocalizedDescriptionKey: "Plante introuvable"])
            }
            plant.lat = latitude
            plant.lon = longitude
            plant.envergureCurrent = envergureCurrent
            plant.updatedAt = nowISO8601()
            try plant.update(db)
        }
    }

    func repairLegacyUUIDs() throws {
        try dbPool.write { db in
            try repairMissingAndDuplicateUUIDs(db: db, table: DBSpecies.databaseTableName, idColumn: DBSpecies.columns.id.name, uuidColumn: DBSpecies.columns.uuid.name, updatedAtColumn: DBSpecies.columns.updatedAt.name)
            try repairMissingAndDuplicateUUIDs(db: db, table: DBCultivar.databaseTableName, idColumn: DBCultivar.columns.id.name, uuidColumn: DBCultivar.columns.uuid.name, updatedAtColumn: DBCultivar.columns.updatedAt.name)
            try repairMissingAndDuplicateUUIDs(db: db, table: DBPlant.databaseTableName, idColumn: DBPlant.columns.id.name, uuidColumn: DBPlant.columns.uuid.name, updatedAtColumn: DBPlant.columns.updatedAt.name)
        }
    }

    private func repairMissingAndDuplicateUUIDs(
        db: Database,
        table: String,
        idColumn: String,
        uuidColumn: String,
        updatedAtColumn: String
    ) throws {
        let now = nowISO8601()

        let missingIDs = try Int64.fetchAll(
            db,
            sql: "SELECT \(idColumn) FROM \(table) WHERE \(uuidColumn) IS NULL OR TRIM(\(uuidColumn)) = ''"
        )
        for id in missingIDs {
            try db.execute(
                sql: "UPDATE \(table) SET \(uuidColumn) = ?, \(updatedAtColumn) = ? WHERE \(idColumn) = ?",
                arguments: [UUID().uuidString, now, id]
            )
        }

        let duplicates = try String.fetchAll(
            db,
            sql: "SELECT \(uuidColumn) FROM \(table) WHERE \(uuidColumn) IS NOT NULL AND TRIM(\(uuidColumn)) != '' GROUP BY \(uuidColumn) HAVING COUNT(*) > 1"
        )

        for duplicate in duplicates {
            let ids = try Int64.fetchAll(
                db,
                sql: "SELECT \(idColumn) FROM \(table) WHERE \(uuidColumn) = ? ORDER BY \(idColumn) ASC",
                arguments: [duplicate]
            )
            for id in ids.dropFirst() {
                try db.execute(
                    sql: "UPDATE \(table) SET \(uuidColumn) = ?, \(updatedAtColumn) = ? WHERE \(idColumn) = ?",
                    arguments: [UUID().uuidString, now, id]
                )
            }
        }
    }

    func saveSpecies(id: Int?, input: SpeciesWriteInput) throws -> Int {
        let now = nowISO8601()
        return try dbPool.write { db in
            if let id {
                guard var record = try DBSpecies.fetchOne(db, key: id) else {
                    throw NSError(domain: "GardenDatabase", code: 211, userInfo: [NSLocalizedDescriptionKey: "Espèce introuvable"])
                }
                record.applyWriteInput(input, updatedAt: now)
                try record.update(db)
                return id
            }

            var record = DBSpecies.makeNew(from: input, updatedAt: now)
            try record.insert(db)
            return Int(record.id ?? 0)
        }
    }

    func saveCultivar(id: Int?, speciesId: Int?, input: CultivarWriteInput) throws -> Int {
        let now = nowISO8601()
        let trimmedName = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw NSError(domain: "GardenDatabase", code: 221, userInfo: [NSLocalizedDescriptionKey: "Nom de cultivar vide"])
        }

        return try dbPool.write { db in
            if let id {
                guard var record = try DBCultivar.fetchOne(db, key: id), !record.deleted else {
                    throw NSError(domain: "GardenDatabase", code: 226, userInfo: [NSLocalizedDescriptionKey: "Cultivar introuvable"])
                }
                record.applyWriteInput(name: trimmedName, input: input, updatedAt: now)
                try record.update(db)
                return id
            }

            guard let speciesId else {
                throw NSError(domain: "GardenDatabase", code: 227, userInfo: [NSLocalizedDescriptionKey: "speciesId manquant pour creation cultivar"])
            }

            var record = DBCultivar.makeNew(
                speciesId: speciesId,
                name: trimmedName,
                input: input,
                updatedAt: now
            )
            try record.insert(db)
            return Int(record.id ?? 0)
        }
    }

    func deleteCultivarRecord(id: Int32) throws -> Bool {
        try dbPool.write { db in
            let linkedPlants = try DBPlant
                .filter(DBPlant.columns.varietyId == Int64(id) && DBPlant.columns.deleted == false)
                .fetchCount(db)
            if linkedPlants > 0 {
                return false
            }
            guard var cultivar = try DBCultivar.fetchOne(db, key: Int(id)) else {
                return false
            }
            cultivar.deleted = true
            cultivar.updatedAt = nowISO8601()
            try cultivar.update(db)
            return true
        }
    }

    func deleteSpeciesRecord(id: Int32) throws -> GardenDeleteSpeciesResult {
        try dbPool.write { db in
            let linkedCultivars = try DBCultivar
                .filter(DBCultivar.columns.speciesId == Int64(id) && DBCultivar.columns.deleted == false)
                .fetchCount(db)
            if linkedCultivars > 0 {
                return .linkedToCultivars
            }

            let linkedPlants = try DBPlant
                .filter(DBPlant.columns.speciesId == Int64(id) && DBPlant.columns.deleted == false)
                .fetchCount(db)
            if linkedPlants > 0 {
                return .linkedToPlants
            }

            guard var species = try DBSpecies.fetchOne(db, key: Int(id)) else {
                return .failure
            }
            species.deleted = true
            species.updatedAt = nowISO8601()
            try species.update(db)
            return .success
        }
    }

    func fetchSpecies() throws -> [GardenTaxon] {
        try dbPool.read { db in
            let records = try DBSpecies
                .filter(DBSpecies.columns.deleted == false)
                .order(DBSpecies.columns.commonName.collating(.localizedCaseInsensitiveCompare))
                .fetchAll(db)
            return records.map { $0.asTaxon(kind: .species) }
        }
    }

    func fetchImageDiagnostics(sampleLimit: Int = 5) throws -> ImageDiagnostics {
        try dbPool.read { db in
            let speciesCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM species") ?? 0
            let speciesWithImage = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM species WHERE image_url IS NOT NULL AND TRIM(image_url) <> ''"
            ) ?? 0
            let speciesWithImageActive = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM species WHERE COALESCE(deleted, 0) = 0 AND image_url IS NOT NULL AND TRIM(image_url) <> ''"
            ) ?? 0
            let plantCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM plants") ?? 0
            let plantsWithLocalImage = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM plants WHERE image_local IS NOT NULL AND TRIM(image_local) <> ''"
            ) ?? 0
            let sampleSpeciesImageURLs = try String.fetchAll(
                db,
                sql: "SELECT image_url FROM species WHERE image_url IS NOT NULL AND TRIM(image_url) <> '' LIMIT ?",
                arguments: [sampleLimit]
            )
            return ImageDiagnostics(
                speciesCount: speciesCount,
                speciesWithImage: speciesWithImage,
                speciesWithImageActive: speciesWithImageActive,
                plantCount: plantCount,
                plantsWithLocalImage: plantsWithLocalImage,
                sampleSpeciesImageURLs: sampleSpeciesImageURLs
            )
        }
    }

    func getLastSyncedAt(for table: String) throws -> String? {
        try dbPool.read { db in
            try DBSyncState.filter(DBSyncState.columns.tableName == table).fetchOne(db)?.lastSyncedAt
        }
    }

    func updateLastSyncedAt(for table: String, value: String) throws {
        try dbPool.write { db in
            var state = DBSyncState(tableName: table, lastSyncedAt: value)
            try state.save(db)
        }
    }

    func syncSpeciesFromSupabase(remoteSpecies: [SpeciesDTO]) throws {
        try dbPool.write { db in
            for sp in remoteSpecies {
                try upsertSpeciesFromSupabase(db: db, dto: sp)
            }
            try backfillMissingSpeciesImageURLsFromBundle(db: db)
        }
    }

    /// Force les `image_url` distantes sur la base locale (source de vérité = Supabase).
    /// N'écrase que si l'URL distante est non vide.
    func forceUpdateSpeciesImagesFromSupabase(remoteSpecies: [SpeciesDTO]) throws {
        let now = nowISO8601()
        try dbPool.write { db in
            for sp in remoteSpecies {
                let trimmed = sp.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !trimmed.isEmpty else { continue }
                try db.execute(
                    sql: "UPDATE species SET image_url = ?, updated_at = ? WHERE id = ?",
                    arguments: [trimmed, sp.updatedAt ?? now, sp.id]
                )
            }
        }
    }

    func syncCultivarsFromSupabase(remoteCultivars: [CultivarDTO]) throws {
        try dbPool.write { db in
            for c in remoteCultivars {
                var record = DBCultivar(dto: c)
                try resolveCultivarUniqueNameConflictIfNeeded(db: db, incoming: record)
                try record.save(db)
            }
        }
    }

    func syncPlantsFromSupabase(remotePlants: [PlantDTO]) throws {
        try dbPool.write { db in
            for p in remotePlants {
                var record = DBPlant(dto: p)
                try record.save(db)
            }
        }
    }

    private func upsertSpeciesFromSupabase(db: Database, dto: SpeciesDTO) throws {
        var incoming = DBSpecies(dto: dto)
        let incomingImage = incoming.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if incomingImage.isEmpty,
           let local = try DBSpecies.fetchOne(db, key: dto.id) {
            let localImage = local.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !localImage.isEmpty {
                incoming.imageURL = local.imageURL
            }
        }
        try incoming.save(db)
    }

    private func backfillMissingSpeciesImageURLsFromBundle(db: Database) throws {
        guard let bundledURL = Bundle.main.url(forResource: "jardin", withExtension: "db") else {
            return
        }

        let bundledQueue = try DatabaseQueue(path: bundledURL.path)
        let bundledRows = try bundledQueue.read { bundledDB in
            try Row.fetchAll(
                bundledDB,
                sql: """
                SELECT latin_name, common_name, image_url
                FROM species
                WHERE image_url IS NOT NULL
                  AND TRIM(image_url) <> ''
                """
            )
        }

        var imageByLatin = [String: String]()
        var imageByCommon = [String: String]()

        for row in bundledRows {
            let image: String = row["image_url"]
            let latin: String? = row["latin_name"]
            let common: String? = row["common_name"]

            if let key = lookupKey(latin), imageByLatin[key] == nil {
                imageByLatin[key] = image
            }
            if let key = lookupKey(common), imageByCommon[key] == nil {
                imageByCommon[key] = image
            }
        }

        let missingRows = try Row.fetchAll(
            db,
            sql: """
            SELECT id, latin_name, common_name
            FROM species
            WHERE image_url IS NULL
               OR TRIM(image_url) = ''
            """
        )

        for row in missingRows {
            let id: Int64 = row["id"]
            let latin: String? = row["latin_name"]
            let common: String? = row["common_name"]

            let replacement = lookupKey(latin).flatMap { imageByLatin[$0] }
                ?? lookupKey(common).flatMap { imageByCommon[$0] }

            guard let replacement else { continue }

            try db.execute(
                sql: "UPDATE species SET image_url = ? WHERE id = ?",
                arguments: [replacement, id]
            )
        }
    }

    private func lookupKey(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "fr_FR")
        ).lowercased()
    }

    private func resolveCultivarUniqueNameConflictIfNeeded(
        db: Database,
        incoming: DBCultivar
    ) throws {
        guard let incomingID = incoming.id else { return }

        let conflicts = try DBCultivar
            .filter(
                DBCultivar.columns.speciesId == incoming.speciesId &&
                DBCultivar.columns.name == incoming.name &&
                DBCultivar.columns.id != incomingID
            )
            .fetchAll(db)

        guard !conflicts.isEmpty else { return }

        for conflict in conflicts {
            guard let conflictID = conflict.id else { continue }

            // Preserve plant links by re-pointing to the incoming remote cultivar id.
            try db.execute(
                sql: """
                UPDATE \(DBPlant.databaseTableName)
                SET \(DBPlant.columns.varietyId.name) = ?
                WHERE \(DBPlant.columns.varietyId.name) = ?
                """,
                arguments: [incomingID, conflictID]
            )

            try db.execute(
                sql: """
                DELETE FROM \(DBCultivar.databaseTableName)
                WHERE \(DBCultivar.columns.id.name) = ?
                """,
                arguments: [conflictID]
            )
        }
    }

    func fetchLocalSpeciesChanges(since: String?) throws -> [SpeciesDTO] {
        try dbPool.read { db in
            var request = DBSpecies.all()
            if let since {
                request = request.filter(DBSpecies.columns.updatedAt > since)
            }
            return try request.fetchAll(db).map { $0.asDTO() }
        }
    }

    func fetchLocalPlantChanges(since: String?) throws -> [PlantDTO] {
        try dbPool.read { db in
            var request = DBPlant.all()
            if let since {
                request = request.filter(DBPlant.columns.updatedAt > since)
            }
            return try request.fetchAll(db).map { $0.asDTO() }
        }
    }

    func fetchLocalCultivarChanges(since: String?) throws -> [CultivarDTO] {
        try dbPool.read { db in
            var request = DBCultivar.all()
            if let since {
                request = request.filter(DBCultivar.columns.updatedAt > since)
            }
            return try request.fetchAll(db).map { $0.asDTO() }
        }
    }

    func softDeletePlant(id: Int) throws {
        try dbPool.write { db in
            guard var plant = try DBPlant.fetchOne(db, key: id) else {
                throw NSError(domain: "GardenDatabase", code: 201, userInfo: [NSLocalizedDescriptionKey: "Plante introuvable"])
            }
            plant.deleted = true
            plant.updatedAt = nowISO8601()
            try plant.update(db)
        }
    }

    private func normalizedSortKey(_ value: String?) -> String {
        (value ?? "").folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "fr_FR")
        )
    }

    private func strataRank(_ strata: String?) -> Int {
        switch normalizedSortKey(strata) {
        case "canopee": return 1
        case "sous-etage": return 2
        case "arbuste": return 3
        case "liane": return 4
        case "couvre-sol": return 5
        default: return 6
        }
    }

    private func speciesMap(db: Database, ids: Set<Int64>) throws -> [Int64: DBSpecies] {
        guard !ids.isEmpty else { return [:] }
        let species = try DBSpecies
            .filter(Array(ids).contains(DBSpecies.columns.id) && DBSpecies.columns.deleted == false)
            .fetchAll(db)
        return Dictionary(uniqueKeysWithValues: species.compactMap { record in
            guard let id = record.id else { return nil }
            return (id, record)
        })
    }

    private func cultivarMap(db: Database, ids: Set<Int64>) throws -> [Int64: DBCultivar] {
        guard !ids.isEmpty else { return [:] }
        let cultivars = try DBCultivar
            .filter(Array(ids).contains(DBCultivar.columns.id) && DBCultivar.columns.deleted == false)
            .fetchAll(db)
        return Dictionary(uniqueKeysWithValues: cultivars.compactMap { record in
            guard let id = record.id else { return nil }
            return (id, record)
        })
    }

    func fetchStats() throws -> JardinStats {
        try dbPool.read { db in
            let plantCount = try DBPlant.filter(DBPlant.columns.deleted == false).fetchCount(db)
            let speciesCount = try DBSpecies.filter(DBSpecies.columns.deleted == false).fetchCount(db)
            let hiveCount = try DBHive.fetchCount(db)
            let colonyCount = try DBHiveColony.fetchCount(db)
            let zoneCount = try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(DISTINCT \(DBPlant.columns.zone.name))
                FROM \(DBPlant.databaseTableName)
                WHERE \(DBPlant.columns.zone.name) IS NOT NULL
                  AND TRIM(\(DBPlant.columns.zone.name)) <> ''
                """
            ) ?? 0
            return JardinStats(
                plantCount: plantCount,
                speciesCount: speciesCount,
                zoneCount: zoneCount,
                hiveCount: hiveCount,
                colonyCount: colonyCount
            )
        }
    }

    func fetchPlants() throws -> [GardenPlant] {
        try dbPool.read { db in
            let plants = try DBPlant.filter(DBPlant.columns.deleted == false).fetchAll(db)
            guard !plants.isEmpty else { return [] }

            let speciesByID = try speciesMap(db: db, ids: Set(plants.map(\.speciesId)))
            let cultivarByID = try cultivarMap(db: db, ids: Set(plants.compactMap(\.varietyId)))

            let mapped = plants.compactMap { plant -> GardenPlant? in
                guard let species = speciesByID[plant.speciesId] else { return nil }
                let cultivar = plant.varietyId.flatMap { cultivarByID[$0] }
                return plant.asGardenPlant(species: species, cultivar: cultivar)
            }

            return mapped.sorted { lhs, rhs in
                let lhsRank = strataRank(lhs.strata)
                let rhsRank = strataRank(rhs.strata)
                if lhsRank != rhsRank { return lhsRank < rhsRank }

                let lhsFamily = normalizedSortKey(lhs.family)
                let rhsFamily = normalizedSortKey(rhs.family)
                if lhsFamily != rhsFamily { return lhsFamily < rhsFamily }

                let lhsGenus = normalizedSortKey(lhs.genus)
                let rhsGenus = normalizedSortKey(rhs.genus)
                if lhsGenus != rhsGenus { return lhsGenus < rhsGenus }

                let lhsLatin = normalizedSortKey(lhs.latinName)
                let rhsLatin = normalizedSortKey(rhs.latinName)
                if lhsLatin != rhsLatin { return lhsLatin < rhsLatin }

                return normalizedSortKey(lhs.label) < normalizedSortKey(rhs.label)
            }
        }
    }

    func fetchSpeciesDetail(speciesId: Int32) throws -> GardenTaxonDetailData? {
        let latinName = try dbPool.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT \(DBSpecies.columns.latinName.name) FROM \(DBSpecies.databaseTableName) WHERE \(DBSpecies.columns.id.name) = ? LIMIT 1",
                arguments: [speciesId]
            )
        }
        guard let latinName else { return nil }
        return try fetchSpeciesDetail(latinName: latinName)
    }

    func fetchSpeciesDetail(latinName: String) throws -> GardenTaxonDetailData? {
        try dbPool.write { db in
            let speciesRows = try DBSpecies
                .filter(DBSpecies.columns.deleted == false && DBSpecies.columns.latinName == latinName)
                .order(DBSpecies.columns.id.asc)
                .fetchAll(db)

            guard !speciesRows.isEmpty else { return nil }

            let baseRecord = speciesRows.first {
                let trimmed = $0.varietyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty
            } ?? speciesRows[0]

            let baseSpecies = baseRecord.asTaxon(kind: .speciesDetail)

            var speciesIDs = Set(speciesRows.compactMap(\.id))
            speciesIDs.insert(Int64(baseSpecies.id))
            let speciesIDArray = Array(speciesIDs)

            let cultivars = try DBCultivar
                .filter(speciesIDArray.contains(DBCultivar.columns.speciesId) && DBCultivar.columns.deleted == false)
                .order(DBCultivar.columns.name.collating(.localizedCaseInsensitiveCompare))
                .fetchAll(db)

            let plants = try DBPlant
                .filter(speciesIDArray.contains(DBPlant.columns.speciesId))
                .fetchAll(db)

            let speciesByID = try speciesMap(db: db, ids: Set(plants.map(\.speciesId)).union(speciesIDs))
            let cultivarByID = try cultivarMap(db: db, ids: Set(plants.compactMap(\.varietyId)))

            let plantCountByCultivar = plants.reduce(into: [Int64: Int]()) { partial, plant in
                guard let varietyId = plant.varietyId else { return }
                partial[varietyId, default: 0] += 1
            }

            let cultivarModels = cultivars.map { cultivar in
                cultivar.asTaxon(
                    plantCount: plantCountByCultivar[cultivar.id ?? -1] ?? 0
                )
            }

            let plantModels = plants.compactMap { plant -> GardenPlant? in
                let species = speciesByID[plant.speciesId] ?? baseRecord
                let cultivar = plant.varietyId.flatMap { cultivarByID[$0] }
                return plant.asGardenPlant(species: species, cultivar: cultivar)
            }.sorted { lhs, rhs in
                let lhsCultivar = normalizedSortKey(lhs.varietyName)
                let rhsCultivar = normalizedSortKey(rhs.varietyName)
                if lhsCultivar != rhsCultivar { return lhsCultivar < rhsCultivar }
                return normalizedSortKey(lhs.label) < normalizedSortKey(rhs.label)
            }

            return GardenTaxonDetailData(
                base: baseSpecies,
                cultivars: cultivarModels,
                plants: plantModels
            )
        }
    }

    func updateSpeciesCommonFields(
        forLatinName latinName: String,
        fallbackSpeciesId: Int?,
        with input: SpeciesCommonWriteInput
    ) throws {
        let trimmedLatin = latinName.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = nowISO8601()

        try dbPool.write { db in
            var request = DBSpecies.filter(DBSpecies.columns.deleted == false)
            if !trimmedLatin.isEmpty {
                request = request.filter(DBSpecies.columns.latinName == trimmedLatin)
            } else if let fallbackSpeciesId {
                request = request.filter(DBSpecies.columns.id == Int64(fallbackSpeciesId))
            } else {
                return
            }

            let records = try request.fetchAll(db)
            for var record in records {
                record.applyCommonWriteInput(input, updatedAt: now)
                try record.update(db)
            }
        }
    }

    func fetchSpeciesBase() throws -> [GardenTaxon] {
        try dbPool.read { db in
            let species = try DBSpecies
                .filter(DBSpecies.columns.deleted == false)
                .fetchAll(db)
            guard !species.isEmpty else { return [] }

            let speciesIDArray = Array(Set(species.compactMap(\.id)))

            let plants = try DBPlant
                .filter(DBPlant.columns.deleted == false && speciesIDArray.contains(DBPlant.columns.speciesId))
                .fetchAll(db)
            let cultivars = try DBCultivar
                .filter(DBCultivar.columns.deleted == false && speciesIDArray.contains(DBCultivar.columns.speciesId))
                .fetchAll(db)

            let plantCountBySpeciesID = plants.reduce(into: [Int64: Int]()) { partial, plant in
                partial[plant.speciesId, default: 0] += 1
            }
            let cultivarCountBySpeciesID = cultivars.reduce(into: [Int64: Int]()) { partial, cultivar in
                partial[cultivar.speciesId, default: 0] += 1
            }

            let groupedByLatin = Dictionary(grouping: species) { (record: DBSpecies) in
                record.latinName ?? ""
            }

            let result = groupedByLatin.map { latinName, records -> GardenTaxon in
                DBSpecies.asBaseTaxon(
                    latinName: latinName,
                    records: records,
                    plantCountBySpeciesID: plantCountBySpeciesID,
                    cultivarCountBySpeciesID: cultivarCountBySpeciesID
                )
            }

            return result.sorted { lhs, rhs in
                let lhsFamily = normalizedSortKey(lhs.family)
                let rhsFamily = normalizedSortKey(rhs.family)
                if lhsFamily != rhsFamily { return lhsFamily < rhsFamily }

                let lhsGenus = normalizedSortKey(lhs.genus)
                let rhsGenus = normalizedSortKey(rhs.genus)
                if lhsGenus != rhsGenus { return lhsGenus < rhsGenus }

                return normalizedSortKey(lhs.latinName) < normalizedSortKey(rhs.latinName)
            }
        }
    }

    func fetchHives() throws -> [GardenHive] {
        try dbPool.read { db in
            let rows = try DBHive
                .order(DBHive.columns.code.asc, DBHive.columns.name.asc)
                .fetchAll(db)
            return rows.map { $0.asGardenHive() }
        }
    }

    func fetchHive(id: Int) throws -> GardenHive? {
        try dbPool.read { db in
            guard let hive = try DBHive.fetchOne(db, key: id) else {
                return nil
            }
            return hive.asGardenHive()
        }
    }
}
