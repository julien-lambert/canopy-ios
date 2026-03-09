//
//  Untitled.swift
//  JardinForet
//
//  Created by Julien Lambert on 21/11/2025.
//

import Foundation
import Supabase

private enum SupabaseConfig {
    static func stringValue(for key: String) -> String? {
        if let env = ProcessInfo.processInfo.environment[key], !env.isEmpty, !env.hasPrefix("$(") {
            return env
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: key) as? String, !plist.isEmpty, !plist.hasPrefix("$(") {
            return plist
        }
        return nil
    }

    static var url: URL? {
        guard let rawURL = stringValue(for: "SUPABASE_URL") else { return nil }
        return URL(string: rawURL)
    }

    static var anonKey: String? {
        stringValue(for: "SUPABASE_ANON_KEY")
    }
}

enum GardenSyncServiceError: Error {
    case notConfigured
}

class GardenSyncService {
    static let shared = GardenSyncService()

    private let client: SupabaseClient?

    private init() {
        if let url = SupabaseConfig.url, let key = SupabaseConfig.anonKey {
            self.client = SupabaseClient(
                supabaseURL: url,
                supabaseKey: key
            )
        } else {
            self.client = nil
            AppLog.warning("Supabase non configure: definir SUPABASE_URL et SUPABASE_ANON_KEY.", category: .network)
        }
    }

    private func elapsedMilliseconds(since start: Date) -> Int {
        Int((Date().timeIntervalSince(start) * 1000).rounded())
    }

    private func maxUpdatedAt<T>(_ values: [T], keyPath: KeyPath<T, String?>) -> String? {
        values
            .compactMap { entry in
                let trimmed = entry[keyPath: keyPath]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
            .max()
    }

    private func networkLog(_ message: String) {
        let line = "[GardenSyncService] \(message)"
        print(line)
        AppLog.info(line, category: .network)
    }

    // MARK: - Fetch côté Supabase

    /// Récupère les species modifiées depuis `since` (format "YYYY-MM-DD HH:mm:ss") ou tout si nil.
    func fetchSpecies(since: String? = nil) async throws -> [SpeciesDTO] {
        guard let client else { throw GardenSyncServiceError.notConfigured }
        let startedAt = Date()
        networkLog("PULL species start since=\(since ?? "nil")")
        var query = client
            .from("species")
            .select()

        if let since {
            query = query.gte("updated_at", value: since)
        }

        let result: [SpeciesDTO] = try await query.execute().value
        networkLog(
            "PULL species done in \(elapsedMilliseconds(since: startedAt)) ms count=\(result.count) max_updated_at=\(maxUpdatedAt(result, keyPath: \.updatedAt) ?? "nil")"
        )
        return result
    }

    /// Récupère les plants modifiés depuis `since` (format "YYYY-MM-DD HH:mm:ss") ou tout si nil.
    func fetchPlants(since: String? = nil) async throws -> [PlantDTO] {
        guard let client else { throw GardenSyncServiceError.notConfigured }
        let startedAt = Date()
        networkLog("PULL plants start since=\(since ?? "nil")")
        var query = client
            .from("plants")
            .select()

        if let since {
            query = query.gte("updated_at", value: since)
        }

        let result: [PlantDTO] = try await query.execute().value
        networkLog(
            "PULL plants done in \(elapsedMilliseconds(since: startedAt)) ms count=\(result.count) max_updated_at=\(maxUpdatedAt(result, keyPath: \.updatedAt) ?? "nil")"
        )
        return result
    }

    /// Récupère les cultivars modifiés depuis `since` ou tout si nil.
    func fetchCultivars(since: String? = nil) async throws -> [CultivarDTO] {
        guard let client else { throw GardenSyncServiceError.notConfigured }
        let startedAt = Date()
        networkLog("PULL cultivars start since=\(since ?? "nil")")
        var query = client
            .from("cultivars")
            .select()

        if let since {
            query = query.gte("updated_at", value: since)
        }

        let result: [CultivarDTO] = try await query.execute().value
        networkLog(
            "PULL cultivars done in \(elapsedMilliseconds(since: startedAt)) ms count=\(result.count) max_updated_at=\(maxUpdatedAt(result, keyPath: \.updatedAt) ?? "nil")"
        )
        return result
    }

    // MARK: - Offline sync helpers

    /// Fetch remote changes since the given timestamp.
    func fetchChangesSince(_ date: String?) async throws -> (species: [SpeciesDTO], cultivars: [CultivarDTO], plants: [PlantDTO]) {
        let startedAt = Date()
        networkLog("PULL aggregate start since=\(date ?? "nil")")
        async let s = fetchSpecies(since: date)
        async let c = fetchCultivars(since: date)
        async let p = fetchPlants(since: date)
        let species = try await s
        let cultivars = try await c
        let plants = try await p
        networkLog(
            "PULL aggregate done in \(elapsedMilliseconds(since: startedAt)) ms species=\(species.count) cultivars=\(cultivars.count) plants=\(plants.count)"
        )

        return (species: species, cultivars: cultivars, plants: plants)
    }

    /// Push local changes from SQLite to Supabase.
    func pushLocalChanges(_ changes: (species: [SpeciesDTO], cultivars: [CultivarDTO], plants: [PlantDTO])) async throws {
        guard let client else { throw GardenSyncServiceError.notConfigured }
        let startedAt = Date()
        networkLog(
            "PUSH aggregate start species=\(changes.species.count) cultivars=\(changes.cultivars.count) plants=\(changes.plants.count)"
        )
        // 1) D'abord les espèces (pour respecter le FK species_id dans plants)
        if !changes.species.isEmpty {
            let batchStart = Date()
            _ = try await client
                .from("species")
                .upsert(changes.species)   // upsert en batch
                .execute()
            networkLog(
                "PUSH species done in \(elapsedMilliseconds(since: batchStart)) ms count=\(changes.species.count)"
            )
        }

        // 2) Ensuite les cultivars (FK vers species)
        if !changes.cultivars.isEmpty {
            let batchStart = Date()
            _ = try await client
                .from("cultivars")
                .upsert(changes.cultivars)
                .execute()
            networkLog(
                "PUSH cultivars done in \(elapsedMilliseconds(since: batchStart)) ms count=\(changes.cultivars.count)"
            )
        }

        // 3) Enfin les plants (FK vers species et cultivars)
        if !changes.plants.isEmpty {
            let batchStart = Date()
            _ = try await client
                .from("plants")
                .upsert(changes.plants)    // upsert en batch aussi
                .execute()
            networkLog(
                "PUSH plants done in \(elapsedMilliseconds(since: batchStart)) ms count=\(changes.plants.count)"
            )
        }
        networkLog("PUSH aggregate done in \(elapsedMilliseconds(since: startedAt)) ms")
    }
}
