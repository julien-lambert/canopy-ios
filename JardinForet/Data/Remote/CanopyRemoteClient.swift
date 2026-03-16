import Foundation
import Supabase

enum CanopyRemoteClientError: LocalizedError {
    case notConfigured
    case notAuthenticated
    case incompatibleProject(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Supabase non configuré. Vérifie SUPABASE_URL / SUPABASE_ANON_KEY."
        case .notAuthenticated:
            return "Session Supabase absente. Connecte-toi sur l'écran de connexion."
        case .incompatibleProject(let detail):
            return "Projet Supabase incompatible (site_members introuvable). Pointe vers Canopy v0. Détail: \(detail)"
        }
    }
}

final class CanopyRemoteClient {
    private let client: SupabaseClient?

    private struct SiteModuleInsertPayload: Encodable {
        let site_id: String
        let module_code: String
        let enabled: Bool
    }

    init() {
        self.client = CanopySupabaseClientProvider.shared
        if self.client == nil {
            AppLog.warning("CanopyRemoteClient non configure: SUPABASE_URL / SUPABASE_ANON_KEY manquants.", category: .network)
        }
    }

    private func configuredProjectRef() -> String? {
        guard let host = CanopySupabaseConfig.url?.host else { return nil }
        return host.split(separator: ".").first.map(String.init)
    }

    private func validateExpectedProjectRef() throws {
        guard
            let expected = CanopySupabaseConfig.expectedProjectRef,
            !expected.isEmpty,
            let configured = configuredProjectRef(),
            !configured.isEmpty,
            expected != configured
        else {
            return
        }
        throw CanopyRemoteClientError.incompatibleProject(
            "project_ref attendu=\(expected), configuré=\(configured)"
        )
    }

    private func requireClientForSiteScopedQueries() async throws -> SupabaseClient {
        guard let client else { throw CanopyRemoteClientError.notConfigured }
        try validateExpectedProjectRef()
        do {
            _ = try await CanopySupabaseAuthBootstrap.shared.ensureAuthenticated(client: client)
        } catch {
            AppLog.error("Supabase auth bootstrap failed: \(error)", category: .network)
            throw CanopyRemoteClientError.notAuthenticated
        }
        return client
    }

    func fetchSiteMemberships() async throws -> [CanopyDynamicRow] {
        let client = try await requireClientForSiteScopedQueries()
        let rows: [CanopyDynamicRow]
        do {
            rows = try await client
                .from(CanopySchema.Tables.siteMembers)
                .select()
                .execute()
                .value
        } catch {
            let detail = String(describing: error)
            if detail.contains("PGRST205"), detail.contains("site_members") {
                throw CanopyRemoteClientError.incompatibleProject(detail)
            }
            throw error
        }
        return rows.filter { row in
            row[CanopySchema.SiteMembersFields.deletedAt]?.stringValue == nil
        }
    }

    func fetchSites(siteID: UUID? = nil, since: String? = nil) async throws -> [CanopyDynamicRow] {
        let client = try await requireClientForSiteScopedQueries()
        var query = client
            .from(CanopySchema.Tables.sites)
            .select()
        if let siteID {
            query = query.eq(CanopySchema.SitesFields.id, value: siteID.uuidString)
        }
        if let since, !since.isEmpty {
            query = query.gte(CanopySchema.SitesFields.updatedAt, value: since)
        }
        let rows: [CanopyDynamicRow] = try await query.execute().value

        return rows.filter { row in
            row[CanopySchema.SitesFields.deletedAt]?.stringValue == nil
        }
    }

    func fetchSiteModules(siteID: UUID) async throws -> [CanopyDynamicRow] {
        let client = try await requireClientForSiteScopedQueries()
        let rows: [CanopyDynamicRow] = try await client
            .from(CanopySchema.Tables.siteModules)
            .select()
            .eq(CanopySchema.SiteModulesFields.siteId, value: siteID.uuidString)
            .execute()
            .value

        return rows.filter { row in
            row[CanopySchema.SiteModulesFields.deletedAt]?.stringValue == nil
        }
    }

    func fetchModulesCatalog() async throws -> [CanopyDynamicRow] {
        let client = try await requireClientForSiteScopedQueries()
        let rows: [CanopyDynamicRow] = try await client
            .from(CanopySchema.Tables.modulesCatalog)
            .select()
            .execute()
            .value
        return rows
    }

    func setSiteModuleEnabled(siteID: UUID, moduleCode: String, enabled: Bool) async throws {
        let client = try await requireClientForSiteScopedQueries()

        let updatePayload = CanopyDynamicRow(values: [
            CanopySchema.SiteModulesFields.enabled: .bool(enabled)
        ])

        let updatedRows: [CanopyDynamicRow] = try await client
            .from(CanopySchema.Tables.siteModules)
            .update(updatePayload)
            .eq(CanopySchema.SiteModulesFields.siteId, value: siteID.uuidString)
            .eq(CanopySchema.SiteModulesFields.moduleCode, value: moduleCode)
            .select()
            .execute()
            .value

        if !updatedRows.isEmpty || !enabled {
            return
        }

        let payload = SiteModuleInsertPayload(
            site_id: siteID.uuidString,
            module_code: moduleCode,
            enabled: true
        )

        _ = try await client
            .from(CanopySchema.Tables.siteModules)
            .insert(payload)
            .execute()
    }

    func fetchSpeciesPrivate(siteID: UUID, since: String? = nil) async throws -> [CanopyDynamicRow] {
        let client = try await requireClientForSiteScopedQueries()
        var query = client
            .from(CanopySchema.Tables.speciesPrivate)
            .select()
            .eq(CanopySchema.SpeciesPrivateFields.siteId, value: siteID.uuidString)

        if let since, !since.isEmpty {
            query = query.gte(CanopySchema.SpeciesPrivateFields.updatedAt, value: since)
        }

        return try await query.execute().value
    }

    func fetchIndividuals(siteID: UUID, since: String? = nil) async throws -> [CanopyDynamicRow] {
        let client = try await requireClientForSiteScopedQueries()
        var query = client
            .from(CanopySchema.Tables.individuals)
            .select()
            .eq(CanopySchema.IndividualsFields.siteId, value: siteID.uuidString)

        if let since, !since.isEmpty {
            query = query.gte(CanopySchema.IndividualsFields.updatedAt, value: since)
        }

        return try await query.execute().value
    }

    func fetchCultivars(siteID: UUID, since: String? = nil) async throws -> [CanopyDynamicRow] {
        let client = try await requireClientForSiteScopedQueries()
        var query = client
            .from(CanopySchema.Tables.cultivars)
            .select()
            .eq(CanopySchema.CultivarsFields.siteId, value: siteID.uuidString)

        if let since, !since.isEmpty {
            query = query.gte(CanopySchema.CultivarsFields.updatedAt, value: since)
        }

        return try await query.execute().value
    }

    func fetchSiteIlots(siteID: UUID, since: String? = nil) async throws -> [CanopyDynamicRow] {
        let client = try await requireClientForSiteScopedQueries()
        var query = client
            .from(CanopySchema.Tables.siteIlots)
            .select()
            .eq(CanopySchema.SiteIlotsFields.siteId, value: siteID.uuidString)

        if let since, !since.isEmpty {
            query = query.gte(CanopySchema.SiteIlotsFields.updatedAt, value: since)
        }

        return try await query.execute().value
    }
}
