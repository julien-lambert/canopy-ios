import Foundation

struct CanopyV2PullSummary {
    let siteID: String
    let speciesCount: Int
    let cultivarsCount: Int
    let individualsCount: Int
    let speciesMaxUpdatedAt: String?
    let cultivarsMaxUpdatedAt: String?
    let individualsMaxUpdatedAt: String?
}

final class CanopyV2ProjectionSync {
    private let remoteClient: CanopyRemoteClient
    private let localDB: LocalV2Database
    private let pushEngine: CanopyV2PushEngine
    private let speciesSyncKey = CanopySchema.Tables.speciesPrivate
    private let cultivarsSyncKey = CanopySchema.Tables.cultivars
    private let individualsSyncKey = CanopySchema.Tables.individuals

    init(
        remoteClient: CanopyRemoteClient = CanopyRemoteClient(),
        localDB: LocalV2Database
    ) {
        self.remoteClient = remoteClient
        self.localDB = localDB
        self.pushEngine = CanopyV2PushEngine(localDB: localDB)
    }

    func pullLatest() async throws -> CanopyV2PullSummary? {
        _ = try await pushEngine.pushPending(limit: 100)

        let membershipRows = try await remoteClient.fetchSiteMemberships()
        let localSelectedSiteID = try localDB.currentSiteID()
        guard let selected = selectMembership(membershipRows, preferredSiteID: localSelectedSiteID) else {
            return nil
        }

        let siteID = selected.siteID.uuidString
        if localSelectedSiteID != siteID {
            try localDB.setCurrentSiteID(siteID)
        }

        let speciesSince = try localDB.lastSyncedAt(for: speciesSyncKey)
        let cultivarsSince = try localDB.lastSyncedAt(for: cultivarsSyncKey)
        let individualsSince = try localDB.lastSyncedAt(for: individualsSyncKey)

        let speciesRows = try await remoteClient.fetchSpeciesPrivate(siteID: selected.siteID, since: speciesSince)
        let cultivarRows = try await remoteClient.fetchCultivars(siteID: selected.siteID, since: cultivarsSince)
        let individualRows = try await remoteClient.fetchIndividuals(siteID: selected.siteID, since: individualsSince)

        try localDB.upsertSpeciesPrivateRows(siteID: siteID, rows: speciesRows)
        try localDB.upsertCultivarsRows(siteID: siteID, rows: cultivarRows)
        try localDB.upsertIndividualsRows(siteID: siteID, rows: individualRows)

        let speciesMax = maxUpdatedAt(in: speciesRows, key: CanopySchema.SpeciesPrivateFields.updatedAt)
        let cultivarsMax = maxUpdatedAt(in: cultivarRows, key: CanopySchema.CultivarsFields.updatedAt)
        let individualsMax = maxUpdatedAt(in: individualRows, key: CanopySchema.IndividualsFields.updatedAt)

        if speciesMax != nil {
            try localDB.setLastSyncedAt(speciesMax, for: speciesSyncKey)
        }
        if cultivarsMax != nil {
            try localDB.setLastSyncedAt(cultivarsMax, for: cultivarsSyncKey)
        }
        if individualsMax != nil {
            try localDB.setLastSyncedAt(individualsMax, for: individualsSyncKey)
        }

        return CanopyV2PullSummary(
            siteID: siteID,
            speciesCount: speciesRows.count,
            cultivarsCount: cultivarRows.count,
            individualsCount: individualRows.count,
            speciesMaxUpdatedAt: speciesMax,
            cultivarsMaxUpdatedAt: cultivarsMax,
            individualsMaxUpdatedAt: individualsMax
        )
    }

    private struct SelectedMembership {
        let siteID: UUID
        let role: String
    }

    private func selectMembership(_ rows: [CanopyDynamicRow], preferredSiteID: String?) -> SelectedMembership? {
        let siteIDField = CanopySchema.SiteMembersFields.siteId
        let roleField = CanopySchema.SiteMembersFields.role
        let deletedAtField = CanopySchema.SiteMembersFields.deletedAt

        let mapped: [SelectedMembership] = rows.compactMap { row in
            if row[deletedAtField]?.stringValue != nil { return nil }
            guard
                let siteIDRaw = row[siteIDField]?.stringValue,
                let siteID = UUID(uuidString: siteIDRaw),
                let role = row[roleField]?.stringValue
            else {
                return nil
            }
            return SelectedMembership(siteID: siteID, role: role)
        }

        if let preferredSiteID,
           let preferredUUID = UUID(uuidString: preferredSiteID),
           let preferred = mapped.first(where: { $0.siteID == preferredUUID }) {
            return preferred
        }

        return mapped.sorted { lhs, rhs in
            let leftRank = roleRank(lhs.role)
            let rightRank = roleRank(rhs.role)
            if leftRank == rightRank {
                return lhs.siteID.uuidString < rhs.siteID.uuidString
            }
            return leftRank > rightRank
        }.first
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

    private func maxUpdatedAt(in rows: [CanopyDynamicRow], key updatedAtKey: String) -> String? {
        rows.compactMap { row in
            row[updatedAtKey]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
        .max()
    }
}
