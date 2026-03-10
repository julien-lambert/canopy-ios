// Generated file. Do not edit manually.
// Source: jardin-supabase/schema/entities.yaml

import Foundation

enum CanopySchema {
    enum Tables {
        static let modulesCatalog = "modules_catalog"
        static let siteMembers = "site_members"
        static let siteModules = "site_modules"
        static let siteTemplates = "site_templates"
        static let sites = "sites"
        static let speciesGlobal = "species_global"
        static let speciesPrivate = "species_private"
        static let cultivars = "cultivars"
        static let individuals = "individuals"
        static let individualPhotos = "individual_photos"
        static let observations = "observations"
        static let hives = "hives"
        static let colonies = "colonies"
    }

    enum ModulesCatalogFields {
        static let code = "code"
        static let minPlan = "min_plan"
        static let isBillable = "is_billable"
        static let dependsOn = "depends_on"
        static let metadata = "metadata"
        static let billing = "billing"
        static let ui = "ui"
        static let createdAt = "created_at"
        static let updatedAt = "updated_at"
    }

    enum SiteMembersFields {
        static let siteId = "site_id"
        static let userId = "user_id"
        static let role = "role"
        static let createdAt = "created_at"
        static let updatedAt = "updated_at"
        static let deletedAt = "deleted_at"
    }

    enum SiteModulesFields {
        static let siteId = "site_id"
        static let moduleCode = "module_code"
        static let enabled = "enabled"
        static let config = "config"
        static let createdAt = "created_at"
        static let updatedAt = "updated_at"
        static let deletedAt = "deleted_at"
    }

    enum SiteTemplatesFields {
        static let name = "name"
        static let description = "description"
        static let modules = "modules"
        static let moduleConfigs = "module_configs"
        static let defaults = "defaults"
        static let createdAt = "created_at"
        static let updatedAt = "updated_at"
    }

    enum SitesFields {
        static let id = "id"
        static let ownerId = "owner_id"
        static let name = "name"
        static let slug = "slug"
        static let description = "description"
        static let geom = "geom"
        static let isPublic = "is_public"
        static let settings = "settings"
        static let createdAt = "created_at"
        static let updatedAt = "updated_at"
        static let deletedAt = "deleted_at"
    }

    enum SpeciesGlobalFields {
        static let id = "id"
        static let latinName = "latin_name"
        static let commonName = "common_name"
        static let family = "family"
        static let genus = "genus"
        static let strata = "strata"
        static let origin = "origin"
        static let plantType = "plant_type"
        static let morphology = "morphology"
        static let culture = "culture"
        static let uses = "uses"
        static let melliferousLevel = "melliferous_level"
        static let ornamentalInterest = "ornamental_interest"
        static let lifespanMin = "lifespan_min"
        static let lifespanMax = "lifespan_max"
        static let heightMin = "height_min"
        static let heightMax = "height_max"
        static let floweringPeriod = "flowering_period"
        static let fruitingPeriod = "fruiting_period"
        static let envergureMin = "envergure_min"
        static let envergureMax = "envergure_max"
        static let imageUrl = "image_url"
        static let tags = "tags"
        static let notes = "notes"
        static let metadata = "metadata"
        static let validatedAt = "validated_at"
        static let createdAt = "created_at"
        static let updatedAt = "updated_at"
        static let deletedAt = "deleted_at"
    }

    enum SpeciesPrivateFields {
        static let id = "id"
        static let siteId = "site_id"
        static let speciesGlobalId = "species_global_id"
        static let latinName = "latin_name"
        static let commonName = "common_name"
        static let family = "family"
        static let genus = "genus"
        static let strata = "strata"
        static let origin = "origin"
        static let plantType = "plant_type"
        static let morphology = "morphology"
        static let culture = "culture"
        static let uses = "uses"
        static let melliferousLevel = "melliferous_level"
        static let ornamentalInterest = "ornamental_interest"
        static let lifespanMin = "lifespan_min"
        static let lifespanMax = "lifespan_max"
        static let heightMin = "height_min"
        static let heightMax = "height_max"
        static let floweringPeriod = "flowering_period"
        static let fruitingPeriod = "fruiting_period"
        static let envergureMin = "envergure_min"
        static let envergureMax = "envergure_max"
        static let imageUrl = "image_url"
        static let tags = "tags"
        static let notes = "notes"
        static let metadata = "metadata"
        static let createdAt = "created_at"
        static let updatedAt = "updated_at"
        static let deletedAt = "deleted_at"
    }

    enum CultivarsFields {
        static let id = "id"
        static let siteId = "site_id"
        static let speciesGlobalId = "species_global_id"
        static let speciesPrivateId = "species_private_id"
        static let name = "name"
        static let imageUrl = "image_url"
        static let notes = "notes"
        static let tags = "tags"
        static let origin = "origin"
        static let createdAt = "created_at"
        static let updatedAt = "updated_at"
        static let deletedAt = "deleted_at"
    }

    enum IndividualsFields {
        static let id = "id"
        static let siteId = "site_id"
        static let speciesGlobalId = "species_global_id"
        static let speciesPrivateId = "species_private_id"
        static let cultivarId = "cultivar_id"
        static let code = "code"
        static let label = "label"
        static let imageUrl = "image_url"
        static let status = "status"
        static let plantedAt = "planted_at"
        static let locationLat = "location_lat"
        static let locationLng = "location_lng"
        static let locationAlt = "location_alt"
        static let zone = "zone"
        static let notes = "notes"
        static let tags = "tags"
        static let metadata = "metadata"
        static let createdAt = "created_at"
        static let updatedAt = "updated_at"
        static let deletedAt = "deleted_at"
    }

    enum IndividualPhotosFields {
        static let id = "id"
        static let siteId = "site_id"
        static let individualId = "individual_id"
        static let photoUuid = "photo_uuid"
        static let url = "url"
        static let localPath = "local_path"
        static let caption = "caption"
        static let dateTaken = "date_taken"
        static let createdAt = "created_at"
        static let updatedAt = "updated_at"
        static let deletedAt = "deleted_at"
    }

    enum ObservationsFields {
        static let id = "id"
        static let siteId = "site_id"
        static let targetType = "target_type"
        static let targetId = "target_id"
        static let eventType = "event_type"
        static let observedOn = "observed_on"
        static let notes = "notes"
        static let payload = "payload"
        static let createdAt = "created_at"
        static let updatedAt = "updated_at"
        static let deletedAt = "deleted_at"
    }

    enum HivesFields {
        static let id = "id"
        static let siteId = "site_id"
        static let code = "code"
        static let name = "name"
        static let status = "status"
        static let location = "location"
        static let notes = "notes"
        static let createdAt = "created_at"
        static let updatedAt = "updated_at"
        static let deletedAt = "deleted_at"
    }

    enum ColoniesFields {
        static let id = "id"
        static let siteId = "site_id"
        static let hiveId = "hive_id"
        static let beeRace = "bee_race"
        static let queenYear = "queen_year"
        static let notes = "notes"
        static let createdAt = "created_at"
        static let updatedAt = "updated_at"
        static let deletedAt = "deleted_at"
    }

}
