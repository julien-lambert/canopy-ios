import Foundation
import GRDB

enum CanopyLocalSchema {
    static let databaseFileName = "canopy.db"
    static let previousDatabaseFileName = "jardin_v2.db"
    static let syncStateTableName = "sync_state_local"
    static let syncOutboxTableName = "sync_outbox_local"

    static func makeConfiguration() -> Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.busyMode = .timeout(5.0)
        return configuration
    }

    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v2_0001_base") { db in
            try db.create(table: "app_context", ifNotExists: true) { table in
                table.column("id", .integer).primaryKey()
                table.column("current_user_id", .text)
                table.column("current_site_id", .text)
                table.column("last_full_pull_at", .text)
                table.column("updated_at", .text).notNull()
            }

            try db.create(table: syncStateTableName, ifNotExists: true) { table in
                table.column("table_name", .text).primaryKey()
                table.column("last_synced_at", .text)
                table.column("updated_at", .text).notNull()
            }

            try db.create(table: syncOutboxTableName, ifNotExists: true) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("site_id", .text).notNull()
                table.column("entity_type", .text).notNull()
                table.column("entity_remote_id", .text)
                table.column("op_type", .text).notNull()
                table.column("payload_json", .text).notNull()
                table.column("status", .text).notNull().defaults(to: "pending")
                table.column("attempt_count", .integer).notNull().defaults(to: 0)
                table.column("last_error", .text)
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
            }
            try db.create(index: "idx_sync_outbox_status", on: syncOutboxTableName, columns: ["status"], ifNotExists: true)

            try db.create(table: "species_private_local", ifNotExists: true) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("remote_id", .text).notNull().unique(onConflict: .replace)
                table.column("site_id", .text).notNull()
                table.column("species_global_id", .text)
                table.column("latin_name", .text)
                table.column("common_name", .text)
                table.column("family", .text)
                table.column("genus", .text)
                table.column("strata", .text)
                table.column("origin", .text)
                table.column("plant_type", .text)
                table.column("morphology", .text)
                table.column("culture", .text)
                table.column("uses", .text)
                table.column("melliferous_level", .text)
                table.column("ornamental_interest", .text)
                table.column("lifespan_min", .integer)
                table.column("lifespan_max", .integer)
                table.column("height_min", .double)
                table.column("height_max", .double)
                table.column("flowering_period", .text)
                table.column("fruiting_period", .text)
                table.column("envergure_min", .double)
                table.column("envergure_max", .double)
                table.column("image_url", .text)
                table.column("tags_json", .text)
                table.column("notes", .text)
                table.column("metadata_json", .text)
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
                table.column("deleted_at", .text)
            }
            try db.create(index: "idx_species_private_local_site", on: "species_private_local", columns: ["site_id"], ifNotExists: true)

            try db.create(table: "cultivars_local", ifNotExists: true) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("remote_id", .text).notNull().unique(onConflict: .replace)
                table.column("site_id", .text).notNull()
                table.column("species_global_id", .text)
                table.column("species_private_id", .text)
                table.column("name", .text).notNull()
                table.column("image_url", .text)
                table.column("notes", .text)
                table.column("tags_json", .text)
                table.column("origin", .text)
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
                table.column("deleted_at", .text)
            }
            try db.create(index: "idx_cultivars_local_site", on: "cultivars_local", columns: ["site_id"], ifNotExists: true)

            try db.create(table: "individuals_local", ifNotExists: true) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("remote_id", .text).notNull().unique(onConflict: .replace)
                table.column("site_id", .text).notNull()
                table.column("species_global_id", .text)
                table.column("species_private_id", .text)
                table.column("cultivar_id", .text)
                table.column("code", .text)
                table.column("label", .text)
                table.column("image_url", .text)
                table.column("status", .text).notNull().defaults(to: "plante")
                table.column("planted_at", .text)
                table.column("location_lat", .double)
                table.column("location_lng", .double)
                table.column("location_alt", .double)
                table.column("site_ilot_id", .text)
                table.column("height_current", .double)
                table.column("envergure_current", .double)
                table.column("zone", .text)
                table.column("notes", .text)
                table.column("tags_json", .text)
                table.column("metadata_json", .text)
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
                table.column("deleted_at", .text)
            }
            try db.create(index: "idx_individuals_local_site", on: "individuals_local", columns: ["site_id"], ifNotExists: true)
            try db.create(index: "idx_individuals_local_species_private", on: "individuals_local", columns: ["species_private_id"], ifNotExists: true)

            try db.create(table: "individual_photos_local", ifNotExists: true) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("remote_id", .text).notNull().unique(onConflict: .replace)
                table.column("site_id", .text).notNull()
                table.column("individual_id", .text).notNull()
                table.column("photo_uuid", .text)
                table.column("url", .text)
                table.column("local_path", .text)
                table.column("caption", .text)
                table.column("date_taken", .text)
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
                table.column("deleted_at", .text)
            }
            try db.create(index: "idx_individual_photos_local_site", on: "individual_photos_local", columns: ["site_id"], ifNotExists: true)
            try db.create(index: "idx_individual_photos_local_individual", on: "individual_photos_local", columns: ["individual_id"], ifNotExists: true)

            try db.create(table: "observations_local", ifNotExists: true) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("remote_id", .text).notNull().unique(onConflict: .replace)
                table.column("site_id", .text).notNull()
                table.column("target_type", .text).notNull()
                table.column("target_id", .text).notNull()
                table.column("event_type", .text).notNull()
                table.column("observed_on", .text)
                table.column("notes", .text)
                table.column("payload_json", .text)
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
                table.column("deleted_at", .text)
            }
            try db.create(index: "idx_observations_local_site", on: "observations_local", columns: ["site_id"], ifNotExists: true)
        }

        migrator.registerMigration("v2_0002_individual_measurements") { db in
            let existingColumns = try Set(db.columns(in: "individuals_local").map(\.name))

            if !existingColumns.contains("height_current") {
                try db.alter(table: "individuals_local") { table in
                    table.add(column: "height_current", .double)
                }
            }

            if !existingColumns.contains("envergure_current") {
                try db.alter(table: "individuals_local") { table in
                    table.add(column: "envergure_current", .double)
                }
            }

            try db.execute(
                sql: """
                  UPDATE individuals_local
                  SET
                    height_current = COALESCE(height_current, CAST(json_extract(metadata_json, '$.height_current') AS REAL)),
                    envergure_current = COALESCE(envergure_current, CAST(json_extract(metadata_json, '$.envergure_current') AS REAL))
                  WHERE metadata_json IS NOT NULL
                """
            )
        }

        migrator.registerMigration("local_0003_sync_tables") { db in
            let tableNames = try Set(String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'"))

            if tableNames.contains("sync_state_v2"), !tableNames.contains(syncStateTableName) {
                try db.rename(table: "sync_state_v2", to: syncStateTableName)
            }

            if tableNames.contains("sync_outbox_v2"), !tableNames.contains(syncOutboxTableName) {
                try db.rename(table: "sync_outbox_v2", to: syncOutboxTableName)
            }

            try db.create(index: "idx_sync_outbox_status", on: syncOutboxTableName, columns: ["status"], ifNotExists: true)
        }

        migrator.registerMigration("local_0004_site_ilots") { db in
            let individualColumns = try Set(db.columns(in: "individuals_local").map(\.name))

            if !individualColumns.contains("site_ilot_id") {
                try db.alter(table: "individuals_local") { table in
                    table.add(column: "site_ilot_id", .text)
                }
            }

            try db.create(table: "site_ilots_local", ifNotExists: true) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("remote_id", .text).notNull().unique(onConflict: .replace)
                table.column("site_id", .text).notNull()
                table.column("code", .text).notNull()
                table.column("name", .text)
                table.column("geom_json", .text)
                table.column("centroid_json", .text)
                table.column("centroid_lat", .double)
                table.column("centroid_lng", .double)
                table.column("area_m2", .double)
                table.column("sun_exposure", .text)
                table.column("humidity_profile", .text)
                table.column("pedology", .text)
                table.column("drainage_profile", .text)
                table.column("frost_exposure", .text)
                table.column("management_intensity", .text)
                table.column("slope_pct", .double)
                table.column("aspect", .text)
                table.column("wind_exposure", .text)
                table.column("notes", .text)
                table.column("tags_json", .text)
                table.column("metadata_json", .text)
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
                table.column("deleted_at", .text)
            }

            try db.create(index: "idx_site_ilots_local_site", on: "site_ilots_local", columns: ["site_id"], ifNotExists: true)
            try db.create(index: "idx_site_ilots_local_code", on: "site_ilots_local", columns: ["site_id", "code"], ifNotExists: true)
        }

        migrator.registerMigration("local_0005_sites_cache") { db in
            try db.create(table: "sites_local", ifNotExists: true) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("remote_id", .text).notNull().unique(onConflict: .replace)
                table.column("name", .text).notNull()
                table.column("slug", .text)
                table.column("description", .text)
                table.column("geom_json", .text)
                table.column("settings_json", .text)
                table.column("is_public", .integer)
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
                table.column("deleted_at", .text)
            }

            try db.create(index: "idx_sites_local_slug", on: "sites_local", columns: ["slug"], ifNotExists: true)
        }

        migrator.registerMigration("local_0006_site_ilots_agronomic_profiles") { db in
            let columns = try db.columns(in: "site_ilots_local").map(\.name)
            if !columns.contains("drainage_profile") {
                try db.alter(table: "site_ilots_local") { table in
                    table.add(column: "drainage_profile", .text)
                }
            }
            if !columns.contains("frost_exposure") {
                try db.alter(table: "site_ilots_local") { table in
                    table.add(column: "frost_exposure", .text)
                }
            }
            if !columns.contains("management_intensity") {
                try db.alter(table: "site_ilots_local") { table in
                    table.add(column: "management_intensity", .text)
                }
            }
        }

        return migrator
    }
}

struct CanopyLocalSpeciesRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "species_private_local"

    var id: Int64?
    var remoteID: String
    var siteID: String
    var speciesGlobalID: String?
    var latinName: String?
    var commonName: String?
    var family: String?
    var genus: String?
    var strata: String?
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
    var envergureMin: Double?
    var envergureMax: Double?
    var imageURL: String?
    var tagsJSON: String?
    var notes: String?
    var metadataJSON: String?
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case remoteID = "remote_id"
        case siteID = "site_id"
        case speciesGlobalID = "species_global_id"
        case latinName = "latin_name"
        case commonName = "common_name"
        case family
        case genus
        case strata
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
        case envergureMin = "envergure_min"
        case envergureMax = "envergure_max"
        case imageURL = "image_url"
        case tagsJSON = "tags_json"
        case notes
        case metadataJSON = "metadata_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct CanopyLocalCultivarRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cultivars_local"

    var id: Int64?
    var remoteID: String
    var siteID: String
    var speciesGlobalID: String?
    var speciesPrivateID: String?
    var name: String
    var imageURL: String?
    var notes: String?
    var tagsJSON: String?
    var origin: String?
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case remoteID = "remote_id"
        case siteID = "site_id"
        case speciesGlobalID = "species_global_id"
        case speciesPrivateID = "species_private_id"
        case name
        case imageURL = "image_url"
        case notes
        case tagsJSON = "tags_json"
        case origin
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct CanopyLocalIndividualRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "individuals_local"

    var id: Int64?
    var remoteID: String
    var siteID: String
    var speciesGlobalID: String?
    var speciesPrivateID: String?
    var cultivarID: String?
    var code: String?
    var label: String?
    var imageURL: String?
    var status: String
    var plantedAt: String?
    var locationLat: Double?
    var locationLng: Double?
    var locationAlt: Double?
    var siteIlotID: String?
    var heightCurrent: Double?
    var envergureCurrent: Double?
    var zone: String?
    var notes: String?
    var tagsJSON: String?
    var metadataJSON: String?
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case remoteID = "remote_id"
        case siteID = "site_id"
        case speciesGlobalID = "species_global_id"
        case speciesPrivateID = "species_private_id"
        case cultivarID = "cultivar_id"
        case code
        case label
        case imageURL = "image_url"
        case status
        case plantedAt = "planted_at"
        case locationLat = "location_lat"
        case locationLng = "location_lng"
        case locationAlt = "location_alt"
        case siteIlotID = "site_ilot_id"
        case heightCurrent = "height_current"
        case envergureCurrent = "envergure_current"
        case zone
        case notes
        case tagsJSON = "tags_json"
        case metadataJSON = "metadata_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct CanopyLocalSiteIlotRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "site_ilots_local"

    var id: Int64?
    var remoteID: String
    var siteID: String
    var code: String
    var name: String?
    var geomJSON: String?
    var centroidJSON: String?
    var centroidLat: Double?
    var centroidLng: Double?
    var areaM2: Double?
    var sunExposure: String?
    var humidityProfile: String?
    var pedology: String?
    var drainageProfile: String?
    var frostExposure: String?
    var managementIntensity: String?
    var slopePct: Double?
    var aspect: String?
    var windExposure: String?
    var notes: String?
    var tagsJSON: String?
    var metadataJSON: String?
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case remoteID = "remote_id"
        case siteID = "site_id"
        case code
        case name
        case geomJSON = "geom_json"
        case centroidJSON = "centroid_json"
        case centroidLat = "centroid_lat"
        case centroidLng = "centroid_lng"
        case areaM2 = "area_m2"
        case sunExposure = "sun_exposure"
        case humidityProfile = "humidity_profile"
        case pedology
        case drainageProfile = "drainage_profile"
        case frostExposure = "frost_exposure"
        case managementIntensity = "management_intensity"
        case slopePct = "slope_pct"
        case aspect
        case windExposure = "wind_exposure"
        case notes
        case tagsJSON = "tags_json"
        case metadataJSON = "metadata_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct CanopyLocalSiteRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "sites_local"

    var id: Int64?
    var remoteID: String
    var name: String
    var slug: String?
    var description: String?
    var geomJSON: String?
    var settingsJSON: String?
    var isPublic: Bool?
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case remoteID = "remote_id"
        case name
        case slug
        case description
        case geomJSON = "geom_json"
        case settingsJSON = "settings_json"
        case isPublic = "is_public"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
