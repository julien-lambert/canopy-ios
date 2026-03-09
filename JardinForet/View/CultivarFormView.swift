import SwiftUI

struct CultivarFormView: View {
    enum Mode {
        case create(speciesId: Int, speciesName: String)
        case edit(speciesId: Int, speciesName: String, cultivar: GardenTaxon)
    }

    @EnvironmentObject private var store: GardenStore
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var name: String
    @State private var notes: String
    @State private var tags: String
    @State private var origin: String
    @State private var plantType: String
    @State private var morphology: String
    @State private var culture: String
    @State private var uses: String
    @State private var melliferousLevel: String
    @State private var ornamentalInterest: String
    @State private var lifespanMin: String
    @State private var lifespanMax: String
    @State private var heightMin: String
    @State private var heightMax: String
    @State private var floweringPeriod: String
    @State private var fruitingPeriod: String
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var showDeleteConfirmation = false
    @State private var isAIFilling = false
    @State private var replacementQueue: [AIReplacement] = []
    @State private var currentReplacement: AIReplacement?

    private enum AIField {
        case name
        case tags
        case plantType
        case morphology
        case notes
        case culture
        case uses
    }

    private struct AIReplacement: Identifiable {
        let id = UUID()
        let field: AIField
        let fieldLabel: String
        let currentValue: String
        let proposedValue: String
    }

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _notes = State(initialValue: "")
            _tags = State(initialValue: "")
            _origin = State(initialValue: "")
            _plantType = State(initialValue: "")
            _morphology = State(initialValue: "")
            _culture = State(initialValue: "")
            _uses = State(initialValue: "")
            _melliferousLevel = State(initialValue: "")
            _ornamentalInterest = State(initialValue: "")
            _lifespanMin = State(initialValue: "")
            _lifespanMax = State(initialValue: "")
            _heightMin = State(initialValue: "")
            _heightMax = State(initialValue: "")
            _floweringPeriod = State(initialValue: "")
            _fruitingPeriod = State(initialValue: "")
        case .edit(_, _, let cultivar):
            _name = State(initialValue: cultivar.varietyName)
            _notes = State(initialValue: cultivar.notes ?? "")
            _tags = State(initialValue: cultivar.tags ?? "")
            _origin = State(initialValue: cultivar.origin ?? "")
            _plantType = State(initialValue: cultivar.plantType ?? "")
            _morphology = State(initialValue: cultivar.morphology ?? "")
            _culture = State(initialValue: cultivar.culture ?? "")
            _uses = State(initialValue: cultivar.uses ?? "")
            _melliferousLevel = State(initialValue: cultivar.melliferousLevel ?? "")
            _ornamentalInterest = State(initialValue: cultivar.ornamentalInterest ?? "")
            _lifespanMin = State(initialValue: cultivar.lifespanMin.map(String.init) ?? "")
            _lifespanMax = State(initialValue: cultivar.lifespanMax.map(String.init) ?? "")
            _heightMin = State(initialValue: cultivar.heightMin.map { String($0) } ?? "")
            _heightMax = State(initialValue: cultivar.heightMax.map { String($0) } ?? "")
            _floweringPeriod = State(initialValue: cultivar.floweringPeriod ?? "")
            _fruitingPeriod = State(initialValue: cultivar.fruitingPeriod ?? "")
        }
    }

    var body: some View {
        Form {
            Section("Cultivar") {
                Button {
                    Task {
                        await fillWithAI()
                    }
                } label: {
                    if isAIFilling {
                        Label("Analyse IA en cours…", systemImage: "hourglass")
                    } else {
                        Label("Remplir avec l’IA", systemImage: "sparkles")
                    }
                }
                .disabled(isAIFilling)

                TextField("Nom du cultivar", text: $name)
#if os(iOS)
                    .textInputAutocapitalization(.words)
#endif
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
                TextField("Tags (séparés par , ; |)", text: $tags)
            }

            Section("Caractéristiques du cultivar") {
                TextField("Origine", text: $origin)
                TextField("Type", text: $plantType)
                TextField("Morphologie", text: $morphology, axis: .vertical)
                    .lineLimit(2...4)
                TextField("Culture", text: $culture, axis: .vertical)
                    .lineLimit(2...4)
                TextField("Usages", text: $uses, axis: .vertical)
                    .lineLimit(2...4)
                TextField("Niveau mellifère", text: $melliferousLevel)
                TextField("Intérêt ornemental", text: $ornamentalInterest)
                TextField("Longévité min (ans)", text: $lifespanMin)
#if os(iOS)
                    .keyboardType(.numberPad)
#endif
                TextField("Longévité max (ans)", text: $lifespanMax)
#if os(iOS)
                    .keyboardType(.numberPad)
#endif
                TextField("Hauteur min (m)", text: $heightMin)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
                TextField("Hauteur max (m)", text: $heightMax)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
                TextField("Période de floraison", text: $floweringPeriod)
                TextField("Période de fructification", text: $fruitingPeriod)
            }

            Section {
                Button(modeButtonTitle) {
                    save()
                }
                .fontWeight(.semibold)
            }

            if case .edit(_, _, let cultivar) = mode {
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Supprimer ce cultivar", systemImage: "trash")
                    }
                    .disabled(cultivar.plantCount > 0)

                    if cultivar.plantCount > 0 {
                        Text("Suppression impossible: ce cultivar est associé à \(cultivar.plantCount) individu(s).")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle(modeNavigationTitle)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
#endif
        .alert("Impossible d'enregistrer", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert(item: $currentReplacement) { replacement in
            Alert(
                title: Text(replacement.fieldLabel),
                message: Text("L’IA propose \"\(replacement.proposedValue)\".\nVoulez-vous remplacer votre donnée actuelle ?"),
                primaryButton: .destructive(Text("Remplacer")) {
                    apply(replacement.proposedValue, to: replacement.field)
                    advanceReplacementQueue()
                },
                secondaryButton: .cancel(Text("Conserver")) {
                    advanceReplacementQueue()
                }
            )
        }
        .confirmationDialog(
            "Supprimer ce cultivar ?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                deleteCultivar()
            }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("Cette action est définitive.")
        }
    }

    private var modeNavigationTitle: String {
        switch mode {
        case .create:
            return "Nouveau cultivar"
        case .edit:
            return "Modifier cultivar"
        }
    }

    private var modeButtonTitle: String {
        switch mode {
        case .create:
            return "Créer le cultivar"
        case .edit:
            return "Enregistrer"
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTags = tags.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOrigin = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPlantType = plantType.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMorphology = morphology.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCulture = culture.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUses = uses.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMelliferous = melliferousLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOrnamental = ornamentalInterest.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFlowering = floweringPeriod.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFruiting = fruitingPeriod.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesOrNil = trimmedNotes.isEmpty ? nil : trimmedNotes
        let tagsOrNil = trimmedTags.isEmpty ? nil : trimmedTags
        let originOrNil = trimmedOrigin.isEmpty ? nil : trimmedOrigin
        let plantTypeOrNil = trimmedPlantType.isEmpty ? nil : trimmedPlantType
        let morphologyOrNil = trimmedMorphology.isEmpty ? nil : trimmedMorphology
        let cultureOrNil = trimmedCulture.isEmpty ? nil : trimmedCulture
        let usesOrNil = trimmedUses.isEmpty ? nil : trimmedUses
        let melliferousOrNil = trimmedMelliferous.isEmpty ? nil : trimmedMelliferous
        let ornamentalOrNil = trimmedOrnamental.isEmpty ? nil : trimmedOrnamental
        let floweringOrNil = trimmedFlowering.isEmpty ? nil : trimmedFlowering
        let fruitingOrNil = trimmedFruiting.isEmpty ? nil : trimmedFruiting
        let lifespanMinValue = Int(lifespanMin.trimmingCharacters(in: .whitespacesAndNewlines))
        let lifespanMaxValue = Int(lifespanMax.trimmingCharacters(in: .whitespacesAndNewlines))
        let heightMinValue = Double(heightMin.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
        let heightMaxValue = Double(heightMax.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))

        guard !trimmedName.isEmpty else {
            errorMessage = "Le nom du cultivar est obligatoire."
            showErrorAlert = true
            return
        }

        let context: (speciesId: Int, editingCultivarId: Int?) = {
            switch mode {
            case .create(let speciesId, _):
                return (speciesId, nil)
            case .edit(let speciesId, _, let cultivar):
                return (speciesId, cultivar.id)
            }
        }()

        if isDuplicateCultivarName(
            trimmedName,
            speciesId: context.speciesId,
            excludingCultivarId: context.editingCultivarId
        ) {
            errorMessage = "Ce nom de cultivar existe déjà pour cette espèce."
            showErrorAlert = true
            return
        }

        let success: Bool
        let writeInput = CultivarWriteInput(
            name: trimmedName,
            notes: notesOrNil,
            tags: tagsOrNil,
            origin: originOrNil,
            plantType: plantTypeOrNil,
            morphology: morphologyOrNil,
            culture: cultureOrNil,
            uses: usesOrNil,
            melliferousLevel: melliferousOrNil,
            ornamentalInterest: ornamentalOrNil,
            lifespanMin: lifespanMinValue,
            lifespanMax: lifespanMaxValue,
            heightMin: heightMinValue,
            heightMax: heightMaxValue,
            floweringPeriod: floweringOrNil,
            fruitingPeriod: fruitingOrNil
        )
        switch mode {
        case .create(let speciesId, _):
            success = store.createCultivar(speciesId: speciesId, input: writeInput)
        case .edit(_, _, let cultivar):
            success = store.updateCultivar(id: cultivar.id, with: writeInput)
        }

        guard success else {
            errorMessage = "Échec de sauvegarde. Vérifie les doublons ou la synchronisation."
            showErrorAlert = true
            return
        }

        dismiss()
    }

    private func isDuplicateCultivarName(
        _ rawName: String,
        speciesId: Int,
        excludingCultivarId: Int?
    ) -> Bool {
        guard let detail = store.fetchSpeciesDetail(speciesId: Int32(speciesId)) else {
            return false
        }
        let candidate = normalizedCultivarName(rawName)
        guard !candidate.isEmpty else { return false }

        return detail.cultivars.contains { cultivar in
            if let excludingCultivarId, cultivar.id == excludingCultivarId {
                return false
            }
            return normalizedCultivarName(cultivar.varietyName) == candidate
        }
    }

    private func normalizedCultivarName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
    }

    private func deleteCultivar() {
        guard case .edit(_, _, let cultivar) = mode else { return }

        let result = store.deleteCultivar(id: cultivar.id)
        switch result {
        case .success:
            dismiss()
        case .linkedToPlants:
            errorMessage = "Impossible de supprimer: ce cultivar est lié à des individus."
            showErrorAlert = true
        case .failure:
            errorMessage = "Échec de suppression du cultivar."
            showErrorAlert = true
        }
    }

    @MainActor
    private func fillWithAI() async {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Renseigne au moins un nom de cultivar/espèce avant d’utiliser l’IA."
            showErrorAlert = true
            return
        }

        isAIFilling = true
        defer { isAIFilling = false }

        do {
            let payload = CultivarAIPayload(
                species: currentSpeciesPayload(),
                cultivar: .init(
                    nom: normalized(name),
                    notes: normalized(notes),
                    tags: normalized(tags),
                    origine: normalized(origin),
                    typePlante: normalized(plantType),
                    morphologie: normalized(morphology),
                    culture: normalized(culture),
                    usages: normalized(uses),
                    niveauMellifere: normalized(melliferousLevel),
                    interetOrnemental: normalized(ornamentalInterest),
                    longeviteMin: normalized(lifespanMin),
                    longeviteMax: normalized(lifespanMax),
                    hauteurMin: normalized(heightMin),
                    hauteurMax: normalized(heightMax),
                    periodeFloraison: normalized(floweringPeriod),
                    periodeFructification: normalized(fruitingPeriod)
                )
            )
            var completed = try await GardenAIService.shared.completeCultivarPayload(payload)
            let hadProgressAfterStructured = hasFillProgress(from: payload, to: completed)

            // Fallback: si rien n'a été complété, on tente une requête IA ciblée cultivar.
            if !hadProgressAfterStructured {
                let query = normalized(name) ?? ""
                if !query.isEmpty {
                    let fallback = try await GardenAIService.shared.fetchPlantData(for: query)
                    completed = merge(payload: completed, with: fallback)
                }
            }

            if !hasFillProgress(from: payload, to: completed) {
                errorMessage = "L'IA n'a proposé aucune nouvelle donnée pour les champs vides."
                showErrorAlert = true
                return
            }

            applyCompletedPayload(completed)
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    @MainActor
    private func applyCompletedPayload(_ payload: CultivarAIPayload) {
        name = payload.cultivar.nom ?? name
        notes = payload.cultivar.notes ?? notes
        tags = payload.cultivar.tags ?? tags
        origin = payload.cultivar.origine ?? origin
        plantType = payload.cultivar.typePlante ?? plantType
        morphology = payload.cultivar.morphologie ?? morphology
        culture = payload.cultivar.culture ?? culture
        uses = payload.cultivar.usages ?? uses
        melliferousLevel = payload.cultivar.niveauMellifere ?? melliferousLevel
        ornamentalInterest = payload.cultivar.interetOrnemental ?? ornamentalInterest
        lifespanMin = payload.cultivar.longeviteMin ?? lifespanMin
        lifespanMax = payload.cultivar.longeviteMax ?? lifespanMax
        heightMin = payload.cultivar.hauteurMin ?? heightMin
        heightMax = payload.cultivar.hauteurMax ?? heightMax
        floweringPeriod = payload.cultivar.periodeFloraison ?? floweringPeriod
        fruitingPeriod = payload.cultivar.periodeFructification ?? fruitingPeriod
    }

    private func currentSpeciesPayload() -> SpeciesAIPayload {
        let speciesId: Int?
        let speciesName: String
        switch mode {
        case .create(let id, let name):
            speciesId = id
            speciesName = name
        case .edit(let id, let name, _):
            speciesId = id
            speciesName = name
        }

        let parent = store.species.first {
            guard let speciesId else { return false }
            return $0.id == speciesId
        }

        return SpeciesAIPayload(
            commonName: normalized(parent?.commonName ?? speciesName),
            nomLatin: normalized(parent?.latinName),
            famille: normalized(parent?.family),
            genre: normalized(parent?.genus),
            strate: normalized(parent?.strata),
            tags: normalized(parent?.tags),
            notes: normalized(parent?.notes),
            imageURL: normalized(parent?.imageURL),
            origine: normalized(parent?.origin),
            typePlante: normalized(parent?.plantType),
            morphologie: normalized(parent?.morphology),
            culture: normalized(parent?.culture),
            usages: normalized(parent?.uses),
            niveauMellifere: normalized(parent?.melliferousLevel),
            interetOrnemental: normalized(parent?.ornamentalInterest),
            longeviteMin: parent?.lifespanMin.map { String($0) },
            longeviteMax: parent?.lifespanMax.map { String($0) },
            hauteurMin: parent?.heightMin.map { String($0) },
            hauteurMax: parent?.heightMax.map { String($0) },
            periodeFloraison: normalized(parent?.floweringPeriod),
            periodeFructification: normalized(parent?.fruitingPeriod)
        )
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func hasFillProgress(from original: CultivarAIPayload, to completed: CultivarAIPayload) -> Bool {
        let before: [String?] = [
            original.cultivar.nom, original.cultivar.notes, original.cultivar.tags, original.cultivar.origine,
            original.cultivar.typePlante, original.cultivar.morphologie, original.cultivar.culture,
            original.cultivar.usages, original.cultivar.niveauMellifere, original.cultivar.interetOrnemental,
            original.cultivar.longeviteMin, original.cultivar.longeviteMax, original.cultivar.hauteurMin,
            original.cultivar.hauteurMax, original.cultivar.periodeFloraison, original.cultivar.periodeFructification
        ]
        let after: [String?] = [
            completed.cultivar.nom, completed.cultivar.notes, completed.cultivar.tags, completed.cultivar.origine,
            completed.cultivar.typePlante, completed.cultivar.morphologie, completed.cultivar.culture,
            completed.cultivar.usages, completed.cultivar.niveauMellifere, completed.cultivar.interetOrnemental,
            completed.cultivar.longeviteMin, completed.cultivar.longeviteMax, completed.cultivar.hauteurMin,
            completed.cultivar.hauteurMax, completed.cultivar.periodeFloraison, completed.cultivar.periodeFructification
        ]

        for idx in before.indices {
            let oldVal = (before[idx] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let newVal = (after[idx] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if oldVal.isEmpty && !newVal.isEmpty {
                return true
            }
        }
        return false
    }

    private func merge(payload: CultivarAIPayload, with fallback: PlantAIResponse) -> CultivarAIPayload {
        var result = payload
        if (result.cultivar.nom ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.cultivar.nom = normalized(fallback.nomLatin)
        }
        if (result.cultivar.typePlante ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.cultivar.typePlante = normalized(fallback.famille)
        }
        if (result.cultivar.morphologie ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.cultivar.morphologie = normalized(fallback.description)
        }
        if (result.cultivar.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.cultivar.notes = normalized(fallback.rusticite)
        }
        if (result.cultivar.culture ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.cultivar.culture = normalized(fallback.besoinsEau)
        }
        if (result.cultivar.usages ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.cultivar.usages = normalized(fallback.expositionSoleil)
        }
        return result
    }

    @MainActor
    private func queueOrApply(field: AIField, label: String, proposed: String) {
        let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let current = value(for: field).trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty {
            apply(trimmed, to: field)
            return
        }
        if current == trimmed {
            return
        }

        replacementQueue.append(
            AIReplacement(
                field: field,
                fieldLabel: label,
                currentValue: current,
                proposedValue: trimmed
            )
        )
    }

    @MainActor
    private func advanceReplacementQueue() {
        if replacementQueue.isEmpty {
            currentReplacement = nil
            return
        }
        currentReplacement = replacementQueue.removeFirst()
    }

    private func value(for field: AIField) -> String {
        switch field {
        case .name: return name
        case .tags: return tags
        case .plantType: return plantType
        case .morphology: return morphology
        case .notes: return notes
        case .culture: return culture
        case .uses: return uses
        }
    }

    @MainActor
    private func apply(_ value: String, to field: AIField) {
        switch field {
        case .name:
            name = value
        case .tags:
            tags = value
        case .plantType:
            plantType = value
        case .morphology:
            morphology = value
        case .notes:
            notes = value
        case .culture:
            culture = value
        case .uses:
            uses = value
        }
    }
}
