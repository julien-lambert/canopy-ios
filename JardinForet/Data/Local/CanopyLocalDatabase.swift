import Foundation
import GRDB

struct CanopyLocalOutboxItem: FetchableRecord, Decodable {
    let id: Int64
    let siteID: String
    let entityType: String
    let entityRemoteID: String?
    let opType: String
    let payloadJSON: String
    let status: String
    let attemptCount: Int
    let lastError: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case siteID = "site_id"
        case entityType = "entity_type"
        case entityRemoteID = "entity_remote_id"
        case opType = "op_type"
        case payloadJSON = "payload_json"
        case status
        case attemptCount = "attempt_count"
        case lastError = "last_error"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

final class CanopyLocalDatabase {
    private let dbPool: DatabasePool
    private let encoder = JSONEncoder()

    init() throws {
        let dbURL = try Self.resolveDatabaseURL()
        dbPool = try DatabasePool(path: dbURL.path, configuration: CanopyLocalSchema.makeConfiguration())
        let migrator = CanopyLocalSchema.makeMigrator()
        try migrator.migrate(dbPool)
    }

    private static func resolveDatabaseURL() throws -> URL {
        let fm = FileManager.default
        let docsURL = try fm.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dbURL = docsURL.appendingPathComponent(CanopyLocalSchema.databaseFileName)
        let previousURL = docsURL.appendingPathComponent(CanopyLocalSchema.previousDatabaseFileName)

        if !fm.fileExists(atPath: dbURL.path), fm.fileExists(atPath: previousURL.path) {
            try fm.moveItem(at: previousURL, to: dbURL)
        }

        return dbURL
    }

    func fetchSpeciesPrivateActive(siteID: String?) throws -> [CanopyLocalSpeciesRecord] {
        try dbPool.read { db in
            if let siteID, !siteID.isEmpty {
                return try CanopyLocalSpeciesRecord.fetchAll(
                    db,
                    sql: """
                      SELECT *
                      FROM species_private_local
                      WHERE site_id = ?
                        AND deleted_at IS NULL
                      ORDER BY COALESCE(common_name, latin_name, remote_id) COLLATE NOCASE
                    """,
                    arguments: [siteID]
                )
            }

            return try CanopyLocalSpeciesRecord.fetchAll(
                db,
                sql: """
                  SELECT *
                  FROM species_private_local
                  WHERE deleted_at IS NULL
                  ORDER BY COALESCE(common_name, latin_name, remote_id) COLLATE NOCASE
                """
            )
        }
    }

    func fetchIndividualsActive(siteID: String?) throws -> [CanopyLocalIndividualRecord] {
        try dbPool.read { db in
            if let siteID, !siteID.isEmpty {
                return try CanopyLocalIndividualRecord.fetchAll(
                    db,
                    sql: """
                      SELECT *
                      FROM individuals_local
                      WHERE site_id = ?
                        AND deleted_at IS NULL
                      ORDER BY COALESCE(label, remote_id) COLLATE NOCASE
                    """,
                    arguments: [siteID]
                )
            }

            return try CanopyLocalIndividualRecord.fetchAll(
                db,
                sql: """
                  SELECT *
                  FROM individuals_local
                  WHERE deleted_at IS NULL
                  ORDER BY COALESCE(label, remote_id) COLLATE NOCASE
                """
            )
        }
    }

    func fetchCultivarsActive(siteID: String?) throws -> [CanopyLocalCultivarRecord] {
        try dbPool.read { db in
            if let siteID, !siteID.isEmpty {
                return try CanopyLocalCultivarRecord.fetchAll(
                    db,
                    sql: """
                      SELECT *
                      FROM cultivars_local
                      WHERE site_id = ?
                        AND deleted_at IS NULL
                      ORDER BY COALESCE(name, remote_id) COLLATE NOCASE
                    """,
                    arguments: [siteID]
                )
            }

            return try CanopyLocalCultivarRecord.fetchAll(
                db,
                sql: """
                  SELECT *
                  FROM cultivars_local
                  WHERE deleted_at IS NULL
                  ORDER BY COALESCE(name, remote_id) COLLATE NOCASE
                """
            )
        }
    }

    func fetchSiteIlotsActive(siteID: String?) throws -> [CanopyLocalSiteIlotRecord] {
        try dbPool.read { db in
            if let siteID, !siteID.isEmpty {
                return try CanopyLocalSiteIlotRecord.fetchAll(
                    db,
                    sql: """
                      SELECT *
                      FROM site_ilots_local
                      WHERE site_id = ?
                        AND deleted_at IS NULL
                      ORDER BY code COLLATE NOCASE, remote_id COLLATE NOCASE
                    """,
                    arguments: [siteID]
                )
            }

            return try CanopyLocalSiteIlotRecord.fetchAll(
                db,
                sql: """
                  SELECT *
                  FROM site_ilots_local
                  WHERE deleted_at IS NULL
                  ORDER BY code COLLATE NOCASE, remote_id COLLATE NOCASE
                """
            )
        }
    }

    func fetchSiteRecord(remoteID: String) throws -> CanopyLocalSiteRecord? {
        try dbPool.read { db in
            try CanopyLocalSiteRecord.fetchOne(
                db,
                sql: """
                  SELECT *
                  FROM sites_local
                  WHERE remote_id = ?
                  LIMIT 1
                """,
                arguments: [remoteID]
            )
        }
    }

    func fetchSpeciesPrivateRecord(remoteID: String) throws -> CanopyLocalSpeciesRecord? {
        try dbPool.read { db in
            try CanopyLocalSpeciesRecord.fetchOne(
                db,
                sql: """
                  SELECT *
                  FROM species_private_local
                  WHERE remote_id = ?
                  LIMIT 1
                """,
                arguments: [remoteID]
            )
        }
    }

    func fetchCultivarRecord(remoteID: String) throws -> CanopyLocalCultivarRecord? {
        try dbPool.read { db in
            try CanopyLocalCultivarRecord.fetchOne(
                db,
                sql: """
                  SELECT *
                  FROM cultivars_local
                  WHERE remote_id = ?
                  LIMIT 1
                """,
                arguments: [remoteID]
            )
        }
    }

    func fetchIndividualRecord(remoteID: String) throws -> CanopyLocalIndividualRecord? {
        try dbPool.read { db in
            try CanopyLocalIndividualRecord.fetchOne(
                db,
                sql: """
                  SELECT *
                  FROM individuals_local
                  WHERE remote_id = ?
                  LIMIT 1
                """,
                arguments: [remoteID]
            )
        }
    }

    func currentSiteID() throws -> String? {
        try dbPool.read { db in
            try String.fetchOne(db, sql: "SELECT current_site_id FROM app_context WHERE id = 1")
        }
    }

    func setCurrentSiteID(_ siteID: String?) throws {
        let now = nowISO8601()
        try dbPool.write { db in
            try db.execute(
                sql: """
                  INSERT INTO app_context(id, current_site_id, updated_at)
                  VALUES (1, ?, ?)
                  ON CONFLICT(id) DO UPDATE SET
                    current_site_id = excluded.current_site_id,
                    updated_at = excluded.updated_at
                """,
                arguments: [siteID, now]
            )
        }
    }

    func lastSyncedAt(for tableName: String) throws -> String? {
        try dbPool.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT last_synced_at FROM \(CanopyLocalSchema.syncStateTableName) WHERE table_name = ?",
                arguments: [tableName]
            )
        }
    }

    func setLastSyncedAt(_ value: String?, for tableName: String) throws {
        let now = nowISO8601()
        try dbPool.write { db in
            try db.execute(
                sql: """
                  INSERT INTO \(CanopyLocalSchema.syncStateTableName)(table_name, last_synced_at, updated_at)
                  VALUES (?, ?, ?)
                  ON CONFLICT(table_name) DO UPDATE SET
                    last_synced_at = excluded.last_synced_at,
                    updated_at = excluded.updated_at
                """,
                arguments: [tableName, value, now]
            )
        }
    }

    func upsertSpeciesPrivateRows(siteID: String, rows: [CanopyDynamicRow]) throws {
        guard !rows.isEmpty else { return }
        let idKey = CanopySchema.SpeciesPrivateFields.id
        let speciesGlobalIDKey = CanopySchema.SpeciesPrivateFields.speciesGlobalId
        let latinNameKey = CanopySchema.SpeciesPrivateFields.latinName
        let commonNameKey = CanopySchema.SpeciesPrivateFields.commonName
        let familyKey = CanopySchema.SpeciesPrivateFields.family
        let genusKey = CanopySchema.SpeciesPrivateFields.genus
        let strataKey = CanopySchema.SpeciesPrivateFields.strata
        let originKey = CanopySchema.SpeciesPrivateFields.origin
        let plantTypeKey = CanopySchema.SpeciesPrivateFields.plantType
        let morphologyKey = CanopySchema.SpeciesPrivateFields.morphology
        let cultureKey = CanopySchema.SpeciesPrivateFields.culture
        let usesKey = CanopySchema.SpeciesPrivateFields.uses
        let melliferousLevelKey = CanopySchema.SpeciesPrivateFields.melliferousLevel
        let ornamentalInterestKey = CanopySchema.SpeciesPrivateFields.ornamentalInterest
        let lifespanMinKey = CanopySchema.SpeciesPrivateFields.lifespanMin
        let lifespanMaxKey = CanopySchema.SpeciesPrivateFields.lifespanMax
        let heightMinKey = CanopySchema.SpeciesPrivateFields.heightMin
        let heightMaxKey = CanopySchema.SpeciesPrivateFields.heightMax
        let floweringPeriodKey = CanopySchema.SpeciesPrivateFields.floweringPeriod
        let fruitingPeriodKey = CanopySchema.SpeciesPrivateFields.fruitingPeriod
        let envergureMinKey = CanopySchema.SpeciesPrivateFields.envergureMin
        let envergureMaxKey = CanopySchema.SpeciesPrivateFields.envergureMax
        let imageURLKey = CanopySchema.SpeciesPrivateFields.imageUrl
        let tagsKey = CanopySchema.SpeciesPrivateFields.tags
        let notesKey = CanopySchema.SpeciesPrivateFields.notes
        let metadataKey = CanopySchema.SpeciesPrivateFields.metadata
        let createdAtKey = CanopySchema.SpeciesPrivateFields.createdAt
        let updatedAtKey = CanopySchema.SpeciesPrivateFields.updatedAt
        let deletedAtKey = CanopySchema.SpeciesPrivateFields.deletedAt

        try dbPool.write { db in
            for row in rows {
                guard let remoteID = row[idKey]?.stringValue else { continue }
                let tagsJSON = jsonString(from: row[tagsKey])
                let metadataJSON = jsonString(from: row[metadataKey])
                let now = nowISO8601()
                let updatedAt = row[updatedAtKey]?.stringValue ?? now
                let createdAt = row[createdAtKey]?.stringValue ?? updatedAt

                try db.execute(
                    sql: """
                      INSERT INTO species_private_local(
                        remote_id,
                        site_id,
                        species_global_id,
                        latin_name,
                        common_name,
                        family,
                        genus,
                        strata,
                        origin,
                        plant_type,
                        morphology,
                        culture,
                        uses,
                        melliferous_level,
                        ornamental_interest,
                        lifespan_min,
                        lifespan_max,
                        height_min,
                        height_max,
                        flowering_period,
                        fruiting_period,
                        envergure_min,
                        envergure_max,
                        image_url,
                        tags_json,
                        notes,
                        metadata_json,
                        created_at,
                        updated_at,
                        deleted_at
                      )
                      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                      ON CONFLICT(remote_id) DO UPDATE SET
                        site_id = excluded.site_id,
                        species_global_id = excluded.species_global_id,
                        latin_name = excluded.latin_name,
                        common_name = excluded.common_name,
                        family = excluded.family,
                        genus = excluded.genus,
                        strata = excluded.strata,
                        origin = excluded.origin,
                        plant_type = excluded.plant_type,
                        morphology = excluded.morphology,
                        culture = excluded.culture,
                        uses = excluded.uses,
                        melliferous_level = excluded.melliferous_level,
                        ornamental_interest = excluded.ornamental_interest,
                        lifespan_min = excluded.lifespan_min,
                        lifespan_max = excluded.lifespan_max,
                        height_min = excluded.height_min,
                        height_max = excluded.height_max,
                        flowering_period = excluded.flowering_period,
                        fruiting_period = excluded.fruiting_period,
                        envergure_min = excluded.envergure_min,
                        envergure_max = excluded.envergure_max,
                        image_url = excluded.image_url,
                        tags_json = excluded.tags_json,
                        notes = excluded.notes,
                        metadata_json = excluded.metadata_json,
                        created_at = excluded.created_at,
                        updated_at = excluded.updated_at,
                        deleted_at = excluded.deleted_at
                    """,
                    arguments: [
                        remoteID,
                        siteID,
                        row[speciesGlobalIDKey]?.stringValue,
                        row[latinNameKey]?.stringValue,
                        row[commonNameKey]?.stringValue,
                        row[familyKey]?.stringValue,
                        row[genusKey]?.stringValue,
                        row[strataKey]?.stringValue,
                        row[originKey]?.stringValue,
                        row[plantTypeKey]?.stringValue,
                        row[morphologyKey]?.stringValue,
                        row[cultureKey]?.stringValue,
                        row[usesKey]?.stringValue,
                        row[melliferousLevelKey]?.stringValue,
                        row[ornamentalInterestKey]?.stringValue,
                        row[lifespanMinKey]?.intValue,
                        row[lifespanMaxKey]?.intValue,
                        row[heightMinKey]?.doubleValue,
                        row[heightMaxKey]?.doubleValue,
                        row[floweringPeriodKey]?.stringValue,
                        row[fruitingPeriodKey]?.stringValue,
                        row[envergureMinKey]?.doubleValue,
                        row[envergureMaxKey]?.doubleValue,
                        row[imageURLKey]?.stringValue,
                        tagsJSON,
                        row[notesKey]?.stringValue,
                        metadataJSON,
                        createdAt,
                        updatedAt,
                        row[deletedAtKey]?.stringValue
                    ]
                )
            }
        }
    }

    func upsertCultivarsRows(siteID: String, rows: [CanopyDynamicRow]) throws {
        guard !rows.isEmpty else { return }
        let idKey = CanopySchema.CultivarsFields.id
        let speciesGlobalIDKey = CanopySchema.CultivarsFields.speciesGlobalId
        let speciesPrivateIDKey = CanopySchema.CultivarsFields.speciesPrivateId
        let nameKey = CanopySchema.CultivarsFields.name
        let imageURLKey = CanopySchema.CultivarsFields.imageUrl
        let notesKey = CanopySchema.CultivarsFields.notes
        let tagsKey = CanopySchema.CultivarsFields.tags
        let originKey = CanopySchema.CultivarsFields.origin
        let createdAtKey = CanopySchema.CultivarsFields.createdAt
        let updatedAtKey = CanopySchema.CultivarsFields.updatedAt
        let deletedAtKey = CanopySchema.CultivarsFields.deletedAt

        try dbPool.write { db in
            for row in rows {
                guard let remoteID = row[idKey]?.stringValue else { continue }
                guard let name = row[nameKey]?.stringValue, !name.isEmpty else { continue }
                let tagsJSON = jsonString(from: row[tagsKey])
                let now = nowISO8601()
                let updatedAt = row[updatedAtKey]?.stringValue ?? now
                let createdAt = row[createdAtKey]?.stringValue ?? updatedAt

                try db.execute(
                    sql: """
                      INSERT INTO cultivars_local(
                        remote_id,
                        site_id,
                        species_global_id,
                        species_private_id,
                        name,
                        image_url,
                        notes,
                        tags_json,
                        origin,
                        created_at,
                        updated_at,
                        deleted_at
                      )
                      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                      ON CONFLICT(remote_id) DO UPDATE SET
                        site_id = excluded.site_id,
                        species_global_id = excluded.species_global_id,
                        species_private_id = excluded.species_private_id,
                        name = excluded.name,
                        image_url = excluded.image_url,
                        notes = excluded.notes,
                        tags_json = excluded.tags_json,
                        origin = excluded.origin,
                        created_at = excluded.created_at,
                        updated_at = excluded.updated_at,
                        deleted_at = excluded.deleted_at
                    """,
                    arguments: [
                        remoteID,
                        siteID,
                        row[speciesGlobalIDKey]?.stringValue,
                        row[speciesPrivateIDKey]?.stringValue,
                        name,
                        row[imageURLKey]?.stringValue,
                        row[notesKey]?.stringValue,
                        tagsJSON,
                        row[originKey]?.stringValue,
                        createdAt,
                        updatedAt,
                        row[deletedAtKey]?.stringValue,
                    ]
                )
            }
        }
    }

    func upsertIndividualsRows(siteID: String, rows: [CanopyDynamicRow]) throws {
        guard !rows.isEmpty else { return }
        let idKey = CanopySchema.IndividualsFields.id
        let speciesGlobalIDKey = CanopySchema.IndividualsFields.speciesGlobalId
        let speciesPrivateIDKey = CanopySchema.IndividualsFields.speciesPrivateId
        let cultivarIDKey = CanopySchema.IndividualsFields.cultivarId
        let codeKey = CanopySchema.IndividualsFields.code
        let labelKey = CanopySchema.IndividualsFields.label
        let imageURLKey = CanopySchema.IndividualsFields.imageUrl
        let statusKey = CanopySchema.IndividualsFields.status
        let plantedAtKey = CanopySchema.IndividualsFields.plantedAt
        let locationLatKey = CanopySchema.IndividualsFields.locationLat
        let locationLngKey = CanopySchema.IndividualsFields.locationLng
        let locationAltKey = CanopySchema.IndividualsFields.locationAlt
        let siteIlotIDKey = CanopySchema.IndividualsFields.siteIlotId
        let heightCurrentKey = CanopySchema.IndividualsFields.heightCurrent
        let envergureCurrentKey = CanopySchema.IndividualsFields.envergureCurrent
        let zoneKey = CanopySchema.IndividualsFields.zone
        let notesKey = CanopySchema.IndividualsFields.notes
        let tagsKey = CanopySchema.IndividualsFields.tags
        let metadataKey = CanopySchema.IndividualsFields.metadata
        let createdAtKey = CanopySchema.IndividualsFields.createdAt
        let updatedAtKey = CanopySchema.IndividualsFields.updatedAt
        let deletedAtKey = CanopySchema.IndividualsFields.deletedAt

        try dbPool.write { db in
            for row in rows {
                guard let remoteID = row[idKey]?.stringValue else { continue }
                let tagsJSON = jsonString(from: row[tagsKey])
                let metadataJSON = jsonString(from: row[metadataKey])
                let now = nowISO8601()
                let updatedAt = row[updatedAtKey]?.stringValue ?? now
                let createdAt = row[createdAtKey]?.stringValue ?? updatedAt
                let status = row[statusKey]?.stringValue ?? "plante"

                try db.execute(
                    sql: """
                      INSERT INTO individuals_local(
                        remote_id,
                        site_id,
                        species_global_id,
                        species_private_id,
                        cultivar_id,
                        code,
                        label,
                        image_url,
                        status,
                        planted_at,
                        location_lat,
                        location_lng,
                        location_alt,
                        site_ilot_id,
                        height_current,
                        envergure_current,
                        zone,
                        notes,
                        tags_json,
                        metadata_json,
                        created_at,
                        updated_at,
                        deleted_at
                      )
                      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                      ON CONFLICT(remote_id) DO UPDATE SET
                        site_id = excluded.site_id,
                        species_global_id = excluded.species_global_id,
                        species_private_id = excluded.species_private_id,
                        cultivar_id = excluded.cultivar_id,
                        code = excluded.code,
                        label = excluded.label,
                        image_url = excluded.image_url,
                        status = excluded.status,
                        planted_at = excluded.planted_at,
                        location_lat = excluded.location_lat,
                        location_lng = excluded.location_lng,
                        location_alt = excluded.location_alt,
                        site_ilot_id = excluded.site_ilot_id,
                        height_current = excluded.height_current,
                        envergure_current = excluded.envergure_current,
                        zone = excluded.zone,
                        notes = excluded.notes,
                        tags_json = excluded.tags_json,
                        metadata_json = excluded.metadata_json,
                        created_at = excluded.created_at,
                        updated_at = excluded.updated_at,
                        deleted_at = excluded.deleted_at
                    """,
                    arguments: [
                        remoteID,
                        siteID,
                        row[speciesGlobalIDKey]?.stringValue,
                        row[speciesPrivateIDKey]?.stringValue,
                        row[cultivarIDKey]?.stringValue,
                        row[codeKey]?.stringValue,
                        row[labelKey]?.stringValue,
                        row[imageURLKey]?.stringValue,
                        status,
                        row[plantedAtKey]?.stringValue,
                        row[locationLatKey]?.doubleValue,
                        row[locationLngKey]?.doubleValue,
                        row[locationAltKey]?.doubleValue,
                        row[siteIlotIDKey]?.stringValue,
                        row[heightCurrentKey]?.doubleValue,
                        row[envergureCurrentKey]?.doubleValue,
                        row[zoneKey]?.stringValue,
                        row[notesKey]?.stringValue,
                        tagsJSON,
                        metadataJSON,
                        createdAt,
                        updatedAt,
                        row[deletedAtKey]?.stringValue
                    ]
                )
            }
        }
    }

    func upsertSiteIlotsRows(siteID: String, rows: [CanopyDynamicRow]) throws {
        guard !rows.isEmpty else { return }

        let idKey = CanopySchema.SiteIlotsFields.id
        let codeKey = CanopySchema.SiteIlotsFields.code
        let nameKey = CanopySchema.SiteIlotsFields.name
        let geomKey = CanopySchema.SiteIlotsFields.geom
        let centroidKey = CanopySchema.SiteIlotsFields.centroid
        let centroidLatKey = CanopySchema.SiteIlotsFields.centroidLat
        let centroidLngKey = CanopySchema.SiteIlotsFields.centroidLng
        let areaM2Key = CanopySchema.SiteIlotsFields.areaM2
        let sunExposureKey = CanopySchema.SiteIlotsFields.sunExposure
        let humidityProfileKey = CanopySchema.SiteIlotsFields.humidityProfile
        let pedologyKey = CanopySchema.SiteIlotsFields.pedology
        let drainageProfileKey = CanopySchema.SiteIlotsFields.drainageProfile
        let frostExposureKey = CanopySchema.SiteIlotsFields.frostExposure
        let managementIntensityKey = CanopySchema.SiteIlotsFields.managementIntensity
        let slopePctKey = CanopySchema.SiteIlotsFields.slopePct
        let aspectKey = CanopySchema.SiteIlotsFields.aspect
        let windExposureKey = CanopySchema.SiteIlotsFields.windExposure
        let notesKey = CanopySchema.SiteIlotsFields.notes
        let tagsKey = CanopySchema.SiteIlotsFields.tags
        let metadataKey = CanopySchema.SiteIlotsFields.metadata
        let createdAtKey = CanopySchema.SiteIlotsFields.createdAt
        let updatedAtKey = CanopySchema.SiteIlotsFields.updatedAt
        let deletedAtKey = CanopySchema.SiteIlotsFields.deletedAt

        try dbPool.write { db in
            for row in rows {
                guard let remoteID = row[idKey]?.stringValue else { continue }
                guard let code = row[codeKey]?.stringValue, !code.isEmpty else { continue }

                let geomJSON = jsonString(from: row[geomKey])
                let centroidJSON = jsonString(from: row[centroidKey])
                let tagsJSON = jsonString(from: row[tagsKey])
                let metadataJSON = jsonString(from: row[metadataKey])
                let now = nowISO8601()
                let updatedAt = row[updatedAtKey]?.stringValue ?? now
                let createdAt = row[createdAtKey]?.stringValue ?? updatedAt

                try db.execute(
                    sql: """
                      INSERT INTO site_ilots_local(
                        remote_id,
                        site_id,
                        code,
                        name,
                        geom_json,
                        centroid_json,
                        centroid_lat,
                        centroid_lng,
                        area_m2,
                        sun_exposure,
                        humidity_profile,
                        pedology,
                        drainage_profile,
                        frost_exposure,
                        management_intensity,
                        slope_pct,
                        aspect,
                        wind_exposure,
                        notes,
                        tags_json,
                        metadata_json,
                        created_at,
                        updated_at,
                        deleted_at
                      )
                      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                      ON CONFLICT(remote_id) DO UPDATE SET
                        site_id = excluded.site_id,
                        code = excluded.code,
                        name = excluded.name,
                        geom_json = excluded.geom_json,
                        centroid_json = excluded.centroid_json,
                        centroid_lat = excluded.centroid_lat,
                        centroid_lng = excluded.centroid_lng,
                        area_m2 = excluded.area_m2,
                        sun_exposure = excluded.sun_exposure,
                        humidity_profile = excluded.humidity_profile,
                        pedology = excluded.pedology,
                        drainage_profile = excluded.drainage_profile,
                        frost_exposure = excluded.frost_exposure,
                        management_intensity = excluded.management_intensity,
                        slope_pct = excluded.slope_pct,
                        aspect = excluded.aspect,
                        wind_exposure = excluded.wind_exposure,
                        notes = excluded.notes,
                        tags_json = excluded.tags_json,
                        metadata_json = excluded.metadata_json,
                        created_at = excluded.created_at,
                        updated_at = excluded.updated_at,
                        deleted_at = excluded.deleted_at
                    """,
                    arguments: [
                        remoteID,
                        siteID,
                        code,
                        row[nameKey]?.stringValue,
                        geomJSON,
                        centroidJSON,
                        row[centroidLatKey]?.doubleValue,
                        row[centroidLngKey]?.doubleValue,
                        row[areaM2Key]?.doubleValue,
                        row[sunExposureKey]?.stringValue,
                        row[humidityProfileKey]?.stringValue,
                        row[pedologyKey]?.stringValue,
                        row[drainageProfileKey]?.stringValue,
                        row[frostExposureKey]?.stringValue,
                        row[managementIntensityKey]?.stringValue,
                        row[slopePctKey]?.doubleValue,
                        row[aspectKey]?.stringValue,
                        row[windExposureKey]?.stringValue,
                        row[notesKey]?.stringValue,
                        tagsJSON,
                        metadataJSON,
                        createdAt,
                        updatedAt,
                        row[deletedAtKey]?.stringValue,
                    ]
                )
            }
        }
    }

    func upsertSitesRows(rows: [CanopyDynamicRow]) throws {
        guard !rows.isEmpty else { return }

        let idKey = CanopySchema.SitesFields.id
        let nameKey = CanopySchema.SitesFields.name
        let slugKey = CanopySchema.SitesFields.slug
        let descriptionKey = CanopySchema.SitesFields.description
        let geomKey = CanopySchema.SitesFields.geom
        let settingsKey = CanopySchema.SitesFields.settings
        let isPublicKey = CanopySchema.SitesFields.isPublic
        let createdAtKey = CanopySchema.SitesFields.createdAt
        let updatedAtKey = CanopySchema.SitesFields.updatedAt
        let deletedAtKey = CanopySchema.SitesFields.deletedAt

        try dbPool.write { db in
            for row in rows {
                guard let remoteID = row[idKey]?.stringValue else { continue }
                guard let name = row[nameKey]?.stringValue, !name.isEmpty else { continue }

                let geomJSON = jsonString(from: row[geomKey])
                let settingsJSON = jsonString(from: row[settingsKey])
                let now = nowISO8601()
                let updatedAt = row[updatedAtKey]?.stringValue ?? now
                let createdAt = row[createdAtKey]?.stringValue ?? updatedAt

                try db.execute(
                    sql: """
                      INSERT INTO sites_local(
                        remote_id,
                        name,
                        slug,
                        description,
                        geom_json,
                        settings_json,
                        is_public,
                        created_at,
                        updated_at,
                        deleted_at
                      )
                      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                      ON CONFLICT(remote_id) DO UPDATE SET
                        name = excluded.name,
                        slug = excluded.slug,
                        description = excluded.description,
                        geom_json = excluded.geom_json,
                        settings_json = excluded.settings_json,
                        is_public = excluded.is_public,
                        created_at = excluded.created_at,
                        updated_at = excluded.updated_at,
                        deleted_at = excluded.deleted_at
                    """,
                    arguments: [
                        remoteID,
                        name,
                        row[slugKey]?.stringValue,
                        row[descriptionKey]?.stringValue,
                        geomJSON,
                        settingsJSON,
                        row[isPublicKey]?.boolValue.map { $0 ? 1 : 0 },
                        createdAt,
                        updatedAt,
                        row[deletedAtKey]?.stringValue,
                    ]
                )
            }
        }
    }

    private func nowISO8601() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private func jsonString(from value: CanopyJSONValue?) -> String? {
        guard let value else { return nil }
        switch value {
        case .null:
            return nil
        default:
            guard let data = try? encoder.encode(value), let raw = String(data: data, encoding: .utf8) else {
                return nil
            }
            return raw
        }
    }

    @discardableResult
    func enqueueOutboxOperation(
        siteID: String,
        entityType: String,
        entityRemoteID: String?,
        opType: String,
        payloadJSON: String
    ) throws -> Int64 {
        let now = nowISO8601()
        return try dbPool.write { db in
            try db.execute(
                sql: """
                  INSERT INTO \(CanopyLocalSchema.syncOutboxTableName)(
                    site_id,
                    entity_type,
                    entity_remote_id,
                    op_type,
                    payload_json,
                    status,
                    attempt_count,
                    created_at,
                    updated_at
                  )
                  VALUES (?, ?, ?, ?, ?, 'pending', 0, ?, ?)
                """,
                arguments: [siteID, entityType, entityRemoteID, opType, payloadJSON, now, now]
            )
            return db.lastInsertedRowID
        }
    }

    func fetchPendingOutbox(limit: Int = 100) throws -> [CanopyLocalOutboxItem] {
        try dbPool.read { db in
            try CanopyLocalOutboxItem.fetchAll(
                db,
                sql: """
                  SELECT *
                  FROM \(CanopyLocalSchema.syncOutboxTableName)
                  WHERE status = 'pending'
                  ORDER BY id ASC
                  LIMIT ?
                """,
                arguments: [limit]
            )
        }
    }

    func markOutboxDone(id: Int64) throws {
        let now = nowISO8601()
        try dbPool.write { db in
            try db.execute(
                sql: """
                  UPDATE \(CanopyLocalSchema.syncOutboxTableName)
                  SET status = 'done',
                      updated_at = ?,
                      last_error = NULL
                  WHERE id = ?
                """,
                arguments: [now, id]
            )
        }
    }

    func markOutboxFailed(id: Int64, error: String) throws {
        let now = nowISO8601()
        try dbPool.write { db in
            try db.execute(
                sql: """
                  UPDATE \(CanopyLocalSchema.syncOutboxTableName)
                  SET attempt_count = attempt_count + 1,
                      last_error = ?,
                      updated_at = ?,
                      status = CASE WHEN (attempt_count + 1) >= 5 THEN 'failed' ELSE 'pending' END
                  WHERE id = ?
                """,
                arguments: [error, now, id]
            )
        }
    }

    func deletePendingOutboxOperations(entityType: String, entityRemoteIDs: [String]) throws {
        guard !entityRemoteIDs.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: entityRemoteIDs.count).joined(separator: ", ")
        let arguments = StatementArguments([entityType] + entityRemoteIDs)
        try dbPool.write { db in
            try db.execute(
                sql: """
                  DELETE FROM \(CanopyLocalSchema.syncOutboxTableName)
                  WHERE status = 'pending'
                    AND entity_type = ?
                    AND entity_remote_id IN (\(placeholders))
                """,
                arguments: arguments
            )
        }
    }

    func clearLocalIndividualCoordinates(remoteIDs: [String]) throws {
        guard !remoteIDs.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: remoteIDs.count).joined(separator: ", ")
        let now = nowISO8601()
        let arguments = StatementArguments([now] + remoteIDs)
        try dbPool.write { db in
            try db.execute(
                sql: """
                  UPDATE individuals_local
                  SET location_lat = NULL,
                      location_lng = NULL,
                      location_alt = NULL,
                      site_ilot_id = NULL,
                      updated_at = ?
                  WHERE remote_id IN (\(placeholders))
                """,
                arguments: arguments
            )
        }
    }
}
