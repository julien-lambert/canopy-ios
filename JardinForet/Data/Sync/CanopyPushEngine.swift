import Foundation
import Supabase

final class CanopyPushEngine {
    private let remoteClient: SupabaseClient?
    private let localDB: CanopyLocalDatabase

    init(localDB: CanopyLocalDatabase) {
        self.localDB = localDB
        self.remoteClient = CanopySupabaseClientProvider.shared
    }

    func pushPending(limit: Int = 100) async throws -> Int {
        guard let remoteClient else { return 0 }
        _ = try await CanopySupabaseAuthBootstrap.shared.ensureAuthenticated(client: remoteClient)
        let pending = try localDB.fetchPendingOutbox(limit: limit)
        guard !pending.isEmpty else { return 0 }

        var successCount = 0
        for item in pending {
            do {
                try await pushItem(item, with: remoteClient)
                try localDB.markOutboxDone(id: item.id)
                successCount += 1
            } catch {
                try? localDB.markOutboxFailed(id: item.id, error: String(describing: error))
            }
        }
        return successCount
    }

    private func pushItem(_ item: CanopyLocalOutboxItem, with client: SupabaseClient) async throws {
        guard let data = item.payloadJSON.data(using: .utf8) else {
            throw NSError(domain: "CanopyPushEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid payload encoding"])
        }

        let payload = try JSONDecoder().decode(CanopyDynamicRow.self, from: data)
        let tableName = item.entityType
        let op = item.opType.lowercased()

        switch op {
        case "upsert":
            _ = try await client.from(tableName).upsert(payload).execute()
        case "delete":
            guard
                let remoteID = item.entityRemoteID,
                let contract = deleteContract(for: tableName)
            else {
                throw NSError(domain: "CanopyPushEngine", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing delete contract for entity \(tableName)"])
            }

            _ = try await client
                .from(tableName)
                .update([contract.deletedAtField: isoNow()])
                .eq(contract.idField, value: remoteID)
                .execute()
        default:
            throw NSError(domain: "CanopyPushEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unsupported outbox op \(item.opType)"])
        }
    }

    private struct DeleteContract {
        let idField: String
        let deletedAtField: String
    }

    private func deleteContract(for tableName: String) -> DeleteContract? {
        switch tableName {
        case CanopySchema.Tables.speciesPrivate:
            return DeleteContract(
                idField: CanopySchema.SpeciesPrivateFields.id,
                deletedAtField: CanopySchema.SpeciesPrivateFields.deletedAt
            )
        case CanopySchema.Tables.individuals:
            return DeleteContract(
                idField: CanopySchema.IndividualsFields.id,
                deletedAtField: CanopySchema.IndividualsFields.deletedAt
            )
        case CanopySchema.Tables.cultivars:
            return DeleteContract(
                idField: CanopySchema.CultivarsFields.id,
                deletedAtField: CanopySchema.CultivarsFields.deletedAt
            )
        case CanopySchema.Tables.individualPhotos:
            return DeleteContract(
                idField: CanopySchema.IndividualPhotosFields.id,
                deletedAtField: CanopySchema.IndividualPhotosFields.deletedAt
            )
        case CanopySchema.Tables.observations:
            return DeleteContract(
                idField: CanopySchema.ObservationsFields.id,
                deletedAtField: CanopySchema.ObservationsFields.deletedAt
            )
        case CanopySchema.Tables.hives:
            return DeleteContract(
                idField: CanopySchema.HivesFields.id,
                deletedAtField: CanopySchema.HivesFields.deletedAt
            )
        case CanopySchema.Tables.colonies:
            return DeleteContract(
                idField: CanopySchema.ColoniesFields.id,
                deletedAtField: CanopySchema.ColoniesFields.deletedAt
            )
        default:
            return nil
        }
    }

    private func isoNow() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
