import Foundation

struct HomeAttentionAdvisor {
    func prioritize(plants: [GardenPlant], isPlantsModuleEnabled: Bool) -> [HomePlantAttentionItem] {
        guard isPlantsModuleEnabled else {
            return []
        }

        return plants
            .compactMap(taskItem(for:))
            .sorted { lhs, rhs in
                if lhs.priorityScore != rhs.priorityScore {
                    return lhs.priorityScore > rhs.priorityScore
                }

                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            }
    }

    private func taskItem(for plant: GardenPlant) -> HomePlantAttentionItem? {
        let normalizedStatus = normalizedStatus(plant.status)
        let missingStatus = normalizedStatus.isEmpty
        let requiresTerrainCompletion = missingStatus || statusNeedsTerrainData(normalizedStatus)
        let missingLocation = requiresTerrainCompletion && !hasCoordinates(plant)
        let missingSpread = requiresTerrainCompletion && plant.spreadCurrent == nil

        guard missingStatus || missingLocation || missingSpread else {
            return nil
        }

        return HomePlantAttentionItem(
            plant: plant,
            missingStatus: missingStatus,
            missingLocation: missingLocation,
            missingSpread: missingSpread,
            suggestedSpread: missingSpread ? suggestedSpread(for: plant) : nil
        )
    }

    private func normalizedStatus(_ status: String?) -> String {
        status?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased() ?? ""
    }

    private func statusNeedsTerrainData(_ normalizedStatus: String) -> Bool {
        switch normalizedStatus {
        case "plante", "malade", "a deplacer":
            return true
        default:
            return false
        }
    }

    private func hasCoordinates(_ plant: GardenPlant) -> Bool {
        plant.lat != nil && plant.lon != nil
    }

    // Temporary heuristic: explicit, local, and replaceable later by AI suggestions.
    private func suggestedSpread(for plant: GardenPlant) -> Double? {
        let minSpread = plant.speciesSpreadMin
        let maxSpread = plant.speciesSpreadMax

        if let minSpread, let maxSpread, minSpread > 0, maxSpread > 0 {
            return ((minSpread + maxSpread) / 2.0 * 10).rounded() / 10
        }

        if let minSpread, minSpread > 0 {
            return (minSpread * 10).rounded() / 10
        }

        if let maxSpread, maxSpread > 0 {
            return (maxSpread * 10).rounded() / 10
        }

        return nil
    }
}

struct HomePlantAttentionItem: Identifiable {
    let plant: GardenPlant
    let missingStatus: Bool
    let missingLocation: Bool
    let missingSpread: Bool
    let suggestedSpread: Double?

    var id: Int { plant.id }

    var priorityScore: Int {
        (missingStatus ? 4 : 0) +
        (missingLocation ? 2 : 0) +
        (missingSpread ? 1 : 0)
    }

    var displayTitle: String {
        let trimmedLabel = plant.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedLabel.isEmpty ? plant.commonName : trimmedLabel
    }

    var subtitle: String {
        var parts: [String] = []

        let commonName = plant.commonName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !commonName.isEmpty {
            parts.append(commonName)
        }

        if let varietyName = plant.varietyName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !varietyName.isEmpty {
            parts.append(varietyName)
        }

        let latinName = plant.latinName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !latinName.isEmpty {
            parts.append(latinName)
        }

        return parts.joined(separator: " · ")
    }

    var missingLabels: [String] {
        var labels: [String] = []

        if missingStatus {
            labels.append("Statut")
        }
        if missingLocation {
            labels.append("Position")
        }
        if missingSpread {
            labels.append("Envergure")
        }

        return labels
    }

    var summary: String {
        switch missingLabels.count {
        case 0:
            return ""
        case 1:
            return "À compléter: \(missingLabels[0].lowercased())."
        default:
            let lastLabel = missingLabels.last ?? ""
            let leading = missingLabels.dropLast().map { $0.lowercased() }.joined(separator: ", ")
            return "À compléter: \(leading) et \(lastLabel.lowercased())."
        }
    }
}
