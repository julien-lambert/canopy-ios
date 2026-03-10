import Foundation

@MainActor
final class CanopyWorkspaceStore: ObservableObject {
    struct SiteSummary: Identifiable, Hashable {
        let id: String
        let name: String
        let slug: String?
        let role: String
    }

    struct ModuleSummary: Identifiable, Hashable {
        var id: String { code }
        let code: String
        let label: String
        let description: String?
        let minPlan: String?
        let isBillable: Bool
        let dependsOn: [String]
        let enabled: Bool
    }

    @Published private(set) var sites: [SiteSummary] = []
    @Published private(set) var selectedSiteID: String?
    @Published private(set) var modules: [ModuleSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var didLoadOnce = false
    @Published var errorMessage: String?

    private let remoteClient: CanopyRemoteClient
    private let localV2DB: LocalV2Database?

    init(
        remoteClient: CanopyRemoteClient = CanopyRemoteClient(),
        localV2DB: LocalV2Database? = try? LocalV2Database()
    ) {
        self.remoteClient = remoteClient
        self.localV2DB = localV2DB
    }

    var selectedSite: SiteSummary? {
        guard let selectedSiteID else { return nil }
        return sites.first(where: { $0.id == selectedSiteID })
    }

    var selectedSiteName: String {
        selectedSite?.name ?? "Site"
    }

    var enabledModuleCodes: Set<String> {
        Set(modules.filter(\.enabled).map(\.code))
    }

    var canManageModules: Bool {
        guard let role = selectedSite?.role else { return false }
        return roleRank(role) >= roleRank("admin")
    }

    func isModuleEnabled(_ code: String) -> Bool {
        enabledModuleCodes.contains(code)
    }

    func refresh() async {
        isLoading = true
        defer {
            isLoading = false
            didLoadOnce = true
        }

        do {
            let membershipRows = try await remoteClient.fetchSiteMemberships()
            let memberships = parseMemberships(membershipRows)
            guard !memberships.isEmpty else {
                self.sites = []
                self.selectedSiteID = nil
                self.modules = []
                self.errorMessage = "Aucun site membre détecté pour ce compte."
                return
            }

            let sitesRows = try await remoteClient.fetchSites()
            let sites = buildSites(from: sitesRows, memberships: memberships)
            self.sites = sites

            let selectedSiteID = try await chooseSelectedSiteID(from: sites)
            self.selectedSiteID = selectedSiteID

            guard let selectedSiteID, let selectedUUID = UUID(uuidString: selectedSiteID) else {
                self.modules = []
                self.errorMessage = "Aucun site sélectionnable."
                return
            }

            let catalogRows = try await remoteClient.fetchModulesCatalog()
            let moduleRows = try await remoteClient.fetchSiteModules(siteID: selectedUUID)
            self.modules = buildModules(catalogRows: catalogRows, siteModulesRows: moduleRows)
            self.errorMessage = nil
        } catch {
            self.errorMessage = String(describing: error)
            AppLog.error("workspace refresh: \(error)", category: .sync)
        }
    }

    func selectSite(_ siteID: String) async {
        guard selectedSiteID != siteID else { return }
        selectedSiteID = siteID
        try? localV2DB?.setCurrentSiteID(siteID)
        await reloadModulesForSelectedSite()
    }

    func setModuleEnabled(code: String, enabled: Bool) {
        Task { await setModuleEnabledAsync(code: code, enabled: enabled) }
    }

    private func setModuleEnabledAsync(code: String, enabled: Bool) async {
        guard canManageModules else {
            errorMessage = "Droits insuffisants pour modifier les modules."
            return
        }
        guard let selectedSiteID, let selectedUUID = UUID(uuidString: selectedSiteID) else {
            errorMessage = "Site courant invalide."
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            try await remoteClient.setSiteModuleEnabled(
                siteID: selectedUUID,
                moduleCode: code,
                enabled: enabled
            )
            await reloadModulesForSelectedSite()
            errorMessage = nil
        } catch {
            errorMessage = "Module '\(code)' non mis à jour: \(error)"
            AppLog.error("setModuleEnabled \(code)=\(enabled): \(error)", category: .sync)
        }
    }

    private func reloadModulesForSelectedSite() async {
        guard let selectedSiteID, let selectedUUID = UUID(uuidString: selectedSiteID) else {
            modules = []
            return
        }
        do {
            let catalogRows = try await remoteClient.fetchModulesCatalog()
            let moduleRows = try await remoteClient.fetchSiteModules(siteID: selectedUUID)
            modules = buildModules(catalogRows: catalogRows, siteModulesRows: moduleRows)
        } catch {
            errorMessage = "Impossible de charger les modules: \(error)"
        }
    }

    private func parseMemberships(_ rows: [CanopyDynamicRow]) -> [String: String] {
        var membershipBySite: [String: String] = [:]
        for row in rows {
            guard
                let siteID = row[CanopySchema.SiteMembersFields.siteId]?.stringValue,
                let role = row[CanopySchema.SiteMembersFields.role]?.stringValue
            else {
                continue
            }
            if let existing = membershipBySite[siteID] {
                if roleRank(role) > roleRank(existing) {
                    membershipBySite[siteID] = role
                }
            } else {
                membershipBySite[siteID] = role
            }
        }
        return membershipBySite
    }

    private func buildSites(from rows: [CanopyDynamicRow], memberships: [String: String]) -> [SiteSummary] {
        rows.compactMap { row in
            guard let id = row[CanopySchema.SitesFields.id]?.stringValue else { return nil }
            guard let role = memberships[id] else { return nil }
            let name = row[CanopySchema.SitesFields.name]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            let slug = row[CanopySchema.SitesFields.slug]?.stringValue
            let resolvedName = (name?.isEmpty == false ? name! : (slug ?? id))
            return SiteSummary(id: id, name: resolvedName, slug: slug, role: role)
        }
        .sorted { lhs, rhs in
            let leftRank = roleRank(lhs.role)
            let rightRank = roleRank(rhs.role)
            if leftRank == rightRank {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return leftRank > rightRank
        }
    }

    private func chooseSelectedSiteID(from sites: [SiteSummary]) async throws -> String? {
        if let selectedSiteID, sites.contains(where: { $0.id == selectedSiteID }) {
            try localV2DB?.setCurrentSiteID(selectedSiteID)
            return selectedSiteID
        }

        if let localSiteID = try localV2DB?.currentSiteID(),
           sites.contains(where: { $0.id == localSiteID }) {
            try localV2DB?.setCurrentSiteID(localSiteID)
            return localSiteID
        }

        let first = sites.first?.id
        try localV2DB?.setCurrentSiteID(first)
        return first
    }

    private func buildModules(catalogRows: [CanopyDynamicRow], siteModulesRows: [CanopyDynamicRow]) -> [ModuleSummary] {
        let enabledByCode: [String: Bool] = siteModulesRows.reduce(into: [:]) { result, row in
            guard let code = row[CanopySchema.SiteModulesFields.moduleCode]?.stringValue else { return }
            let enabled = boolValue(row[CanopySchema.SiteModulesFields.enabled]) ?? false
            result[code] = enabled
        }

        var modules: [ModuleSummary] = catalogRows.compactMap { row in
            guard let code = row[CanopySchema.ModulesCatalogFields.code]?.stringValue else { return nil }
            let metadata = row[CanopySchema.ModulesCatalogFields.metadata]?.dictionaryValue
            let label = metadata?["label"]?.stringValue ?? code
            let description = metadata?["description"]?.stringValue
            let minPlan = row[CanopySchema.ModulesCatalogFields.minPlan]?.stringValue
            let isBillable = boolValue(row[CanopySchema.ModulesCatalogFields.isBillable]) ?? false
            let dependsOn = decodeStringArray(row[CanopySchema.ModulesCatalogFields.dependsOn])
            return ModuleSummary(
                code: code,
                label: label,
                description: description,
                minPlan: minPlan,
                isBillable: isBillable,
                dependsOn: dependsOn,
                enabled: enabledByCode[code] ?? false
            )
        }

        let knownCodes = Set(modules.map(\.code))
        let unknownEnabledCodes = enabledByCode
            .filter { $0.value }
            .map(\.key)
            .filter { !knownCodes.contains($0) }
        for code in unknownEnabledCodes {
            modules.append(
                ModuleSummary(
                    code: code,
                    label: code,
                    description: nil,
                    minPlan: nil,
                    isBillable: false,
                    dependsOn: [],
                    enabled: true
                )
            )
        }

        return modules.sorted {
            $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
    }

    private func decodeStringArray(_ value: CanopyJSONValue?) -> [String] {
        switch value {
        case .array(let items):
            return items.compactMap(\.stringValue).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
        case .string(let raw):
            return raw
                .split(whereSeparator: { ",;|".contains($0) })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        default:
            return []
        }
    }

    private func boolValue(_ value: CanopyJSONValue?) -> Bool? {
        switch value {
        case .bool(let value):
            return value
        case .int(let value):
            return value != 0
        case .double(let value):
            return value != 0
        case .string(let value):
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "t", "1", "yes", "y":
                return true
            case "false", "f", "0", "no", "n":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private func roleRank(_ role: String) -> Int {
        switch role {
        case "owner": return 4
        case "admin": return 3
        case "contributor": return 2
        case "viewer": return 1
        default: return 0
        }
    }
}
