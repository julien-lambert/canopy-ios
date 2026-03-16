import SwiftUI

/// Formulaire d’édition / création d’une espèce (tronc commun uniquement).
struct SpeciesFormView: View {
    @EnvironmentObject private var store: CanopyStore
    @Environment(\.dismiss) private var dismiss

    /// Espèce complète passée par la fiche détail.
    let existingSpecies: GardenTaxon?

    /// Conservé pour compatibilité d’appel depuis SpeciesDetailView.
    /// Les cultivars sont désormais gérés par un formulaire dédié.
    let cultivars: [GardenTaxon]

    @State private var commonName: String
    @State private var latinName: String
    @State private var family: String
    @State private var genus: String
    @State private var strata: String
    @State private var tags: String
    @State private var notes: String
    @State private var imageURL: String
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
    @State private var envergureMin: String
    @State private var envergureMax: String
    @State private var floweringPeriod: String
    @State private var fruitingPeriod: String
    @State private var isAIFilling = false
    @State private var showAIErrorAlert = false
    @State private var aiErrorMessage = ""
    @State private var showDeleteConfirmation = false
    @State private var showDeleteResultAlert = false
    @State private var deleteResultMessage = ""
    @State private var replacementQueue: [AIReplacement] = []
    @State private var currentReplacement: AIReplacement?

    private enum AIField {
        case commonName
        case latinName
        case family
        case genus
        case strata
        case tags
        case imageURL
        case origin
        case plantType
        case morphology
        case uses
        case melliferousLevel
        case ornamentalInterest
        case lifespanMin
        case lifespanMax
        case heightMin
        case heightMax
        case floweringPeriod
        case fruitingPeriod
        case notes
        case culture
    }

    private struct AIReplacement: Identifiable {
        let id = UUID()
        let field: AIField
        let fieldLabel: String
        let currentValue: String
        let proposedValue: String
    }

    init(
        existingSpecies: GardenTaxon? = nil,
        cultivars: [GardenTaxon] = []
    ) {
        self.existingSpecies = existingSpecies
        self.cultivars = cultivars

        _commonName = State(initialValue: existingSpecies?.commonName ?? "")
        _latinName = State(initialValue: existingSpecies?.latinName ?? "")
        _family = State(initialValue: existingSpecies?.family ?? "")
        _genus = State(initialValue: existingSpecies?.genus ?? "")
        _strata = State(initialValue: existingSpecies?.strata ?? "")
        _tags = State(initialValue: existingSpecies?.tags ?? "")
        _notes = State(initialValue: existingSpecies?.notes ?? "")
        _imageURL = State(initialValue: existingSpecies?.imageURL ?? "")
        _origin = State(initialValue: existingSpecies?.origin ?? "")
        _plantType = State(initialValue: existingSpecies?.plantType ?? "")
        _morphology = State(initialValue: existingSpecies?.morphology ?? "")
        _culture = State(initialValue: existingSpecies?.culture ?? "")
        _uses = State(initialValue: existingSpecies?.uses ?? "")
        _melliferousLevel = State(initialValue: existingSpecies?.melliferousLevel ?? "")
        _ornamentalInterest = State(initialValue: existingSpecies?.ornamentalInterest ?? "")
        _lifespanMin = State(initialValue: existingSpecies?.lifespanMin.map(String.init) ?? "")
        _lifespanMax = State(initialValue: existingSpecies?.lifespanMax.map(String.init) ?? "")
        _heightMin = State(initialValue: existingSpecies?.heightMin.map { String(format: "%.2f", $0) } ?? "")
        _heightMax = State(initialValue: existingSpecies?.heightMax.map { String(format: "%.2f", $0) } ?? "")
        _envergureMin = State(initialValue: existingSpecies?.spreadMin.map { String(format: "%.2f", $0) } ?? "")
        _envergureMax = State(initialValue: existingSpecies?.spreadMax.map { String(format: "%.2f", $0) } ?? "")
        _floweringPeriod = State(initialValue: existingSpecies?.floweringPeriod ?? "")
        _fruitingPeriod = State(initialValue: existingSpecies?.fruitingPeriod ?? "")
    }

    var body: some View {
        Form {
            Section(header: Text("Identité botanique")) {
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

                TextField("Nom vernaculaire", text: $commonName)
#if os(iOS)
                    .textInputAutocapitalization(.words)
#endif

                TextField("Nom latin", text: $latinName)
#if os(iOS)
                    .textInputAutocapitalization(.none)
#endif
                    .italic()
                    .disabled(existingSpecies != nil)

                TextField("Famille", text: $family)
                TextField("Genre", text: $genus)
                TextField("Strate (canopée, arbuste, …)", text: $strata)
                TextField("Origine", text: $origin)
                TextField("Type (arbre, arbuste, vivace…)", text: $plantType)
            }

            if let existing = existingSpecies, store.canMutateCultivars {
                Section(header: Text("Cultivars")) {
                    NavigationLink {
                        CultivarFormView(
                            mode: .create(
                                speciesId: Int(existing.id),
                                speciesName: existing.commonName
                            )
                        )
                    } label: {
                        Label("Ajouter un cultivar", systemImage: "plus.circle.fill")
                    }
                    .font(.subheadline.weight(.semibold))

                    if cultivars.isEmpty {
                        Text("Aucun cultivar enregistré.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(cultivars) { cv in
                            NavigationLink {
                                CultivarFormView(
                                    mode: .edit(
                                        speciesId: Int(existing.id),
                                        speciesName: existing.commonName,
                                        cultivar: cv
                                    )
                                )
                            } label: {
                                HStack {
                                    Text(cv.varietyName)
                                    Spacer()
                                    Text("\(cv.plantCount)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            Section(header: Text("Écologie, culture, usages")) {
                TextField("Morphologie", text: $morphology, axis: .vertical)
                TextField("Culture", text: $culture, axis: .vertical)
                TextField("Usages", text: $uses, axis: .vertical)
                TextField("Notes générales", text: $notes, axis: .vertical)
            }

            Section(header: Text("Intérêt, longévité, hauteur")) {
                TextField("Niveau mellifère", text: $melliferousLevel)
                TextField("Intérêt ornemental", text: $ornamentalInterest)

                HStack {
                    TextField("Longévité min (ans)", text: $lifespanMin)
#if os(iOS)
                        .keyboardType(.numberPad)
#endif
                    Text("–")
                    TextField("max", text: $lifespanMax)
#if os(iOS)
                        .keyboardType(.numberPad)
#endif
                }

                HStack {
                    TextField("Hauteur min (m)", text: $heightMin)
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                    Text("–")
                    TextField("max", text: $heightMax)
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                }

                HStack {
                    TextField("Envergure min (m)", text: $envergureMin)
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                    Text("–")
                    TextField("max", text: $envergureMax)
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                }

                TextField("Période de floraison", text: $floweringPeriod)
                TextField("Période de fructification", text: $fruitingPeriod)
            }

            Section(header: Text("Méta / médias")) {
                TextField("URL d’image", text: $imageURL)
#if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.none)
#endif
                TextField("Tags (séparés par , ; |)", text: $tags)
            }

            if let existing = existingSpecies {
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Supprimer cette espèce", systemImage: "trash")
                    }
                    .disabled(!canDeleteSpecies(existing))

                    if !canDeleteSpecies(existing) {
                        Text(deleteBlockerMessage(for: existing))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle(existingSpecies == nil ? "Nouvelle espèce" : "Modifier l’espèce")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
#endif
        .canopyEditorToolbar(
            saveTitle: existingSpecies == nil ? "Créer" : "Enregistrer",
            isSaveDisabled: commonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onCancel: { dismiss() },
            onSave: { saveSpecies() }
        )
        .alert("Erreur IA", isPresented: $showAIErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(aiErrorMessage)
        }
        .alert("Suppression espèce", isPresented: $showDeleteResultAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteResultMessage)
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
            "Supprimer cette espèce ?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                deleteSpecies()
            }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("Cette action est définitive.")
        }
    }

    private func saveSpecies() {
        let trimmedCommon = commonName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLatin = latinName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedCommon.isEmpty else {
            AppLog.warning("saveSpecies annule: commonName vide", category: .ui)
            return
        }

        func parseDouble(_ value: String) -> Double? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return Double(trimmed.replacingOccurrences(of: ",", with: "."))
        }

        let lfMin = Int(lifespanMin.trimmingCharacters(in: .whitespacesAndNewlines))
        let lfMax = Int(lifespanMax.trimmingCharacters(in: .whitespacesAndNewlines))
        let hMin = parseDouble(heightMin)
        let hMax = parseDouble(heightMax)
        let evMin = parseDouble(envergureMin)
        let evMax = parseDouble(envergureMax)

        func trimmedOrNil(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }

        let familyOrNil = trimmedOrNil(family)
        let genusOrNil = trimmedOrNil(genus)
        let strataOrNil = trimmedOrNil(strata)
        let tagsOrNil = trimmedOrNil(tags)
        let notesOrNil = trimmedOrNil(notes)
        let imageURLOrNil = trimmedOrNil(imageURL)
        let originOrNil = trimmedOrNil(origin)
        let plantTypeOrNil = trimmedOrNil(plantType)
        let morphologyOrNil = trimmedOrNil(morphology)
        let cultureOrNil = trimmedOrNil(culture)
        let usesOrNil = trimmedOrNil(uses)
        let mellifOrNil = trimmedOrNil(melliferousLevel)
        let ornOrNil = trimmedOrNil(ornamentalInterest)
        let floweringOrNil = trimmedOrNil(floweringPeriod)
        let fruitingOrNil = trimmedOrNil(fruitingPeriod)

        if let existing = existingSpecies {
            store.updateSpeciesCommonFields(
                latinName: existing.latinName,
                speciesId: Int(existing.id),
                with: SpeciesCommonWriteInput(
                    commonName: trimmedCommon,
                    family: familyOrNil,
                    genus: genusOrNil,
                    strata: strataOrNil,
                    tags: tagsOrNil,
                    notes: notesOrNil,
                    imageURL: imageURLOrNil,
                    origin: originOrNil,
                    plantType: plantTypeOrNil,
                    morphology: morphologyOrNil,
                    culture: cultureOrNil,
                    uses: usesOrNil,
                    melliferousLevel: mellifOrNil,
                    ornamentalInterest: ornOrNil,
                    lifespanMin: lfMin,
                    lifespanMax: lfMax,
                    heightMin: hMin,
                    heightMax: hMax,
                    envergureMin: evMin,
                    envergureMax: evMax,
                    floweringPeriod: floweringOrNil,
                    fruitingPeriod: fruitingOrNil
                )
            )
        } else {
            _ = store.createSpecies(
                SpeciesWriteInput(
                    commonName: trimmedCommon,
                    varietyName: nil,
                    latinName: trimmedLatin,
                    family: familyOrNil,
                    genus: genusOrNil,
                    strata: strataOrNil,
                    tags: tagsOrNil,
                    notes: notesOrNil,
                    imageURL: imageURLOrNil,
                    origin: originOrNil,
                    plantType: plantTypeOrNil,
                    morphology: morphologyOrNil,
                    culture: cultureOrNil,
                    uses: usesOrNil,
                    melliferousLevel: mellifOrNil,
                    ornamentalInterest: ornOrNil,
                    lifespanMin: lfMin,
                    lifespanMax: lfMax,
                    heightMin: hMin,
                    heightMax: hMax,
                    envergureMin: evMin,
                    envergureMax: evMax,
                    floweringPeriod: floweringOrNil,
                    fruitingPeriod: fruitingOrNil,
                    varietyNotes: nil
                )
            )
        }

        dismiss()
    }

    @MainActor
    private func fillWithAI() async {
        guard !(commonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                latinName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) else {
            aiErrorMessage = "Renseigne au moins un nom d’espèce avant d’utiliser l’IA."
            showAIErrorAlert = true
            return
        }

        isAIFilling = true
        defer { isAIFilling = false }

        do {
            let payload = SpeciesAIPayload(
                commonName: normalized(commonName),
                nomLatin: normalized(latinName),
                famille: normalized(family),
                genre: normalized(genus),
                strate: normalized(strata),
                tags: normalized(tags),
                notes: normalized(notes),
                imageURL: normalized(imageURL),
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
            var completed = try await GardenAIService.shared.completeSpeciesPayload(payload)
            let hadProgressAfterStructured = hasFillProgress(from: payload, to: completed)

            // Fallback: si aucune valeur vide n'a été complétée, on force une requête botanique ciblée.
            if !hadProgressAfterStructured {
                let query = normalized(latinName) ?? normalized(commonName) ?? ""
                if !query.isEmpty {
                    let fallback = try await GardenAIService.shared.fetchSpeciesData(for: query)
                    completed = merge(payload: completed, with: fallback)
                }
            }

            if !hasFillProgress(from: payload, to: completed) {
                aiErrorMessage = "L'IA n'a proposé aucune nouvelle donnée pour les champs vides."
                showAIErrorAlert = true
                return
            }

            applyCompletedPayload(completed)
        } catch {
            aiErrorMessage = error.localizedDescription
            showAIErrorAlert = true
        }
    }

    @MainActor
    private func applyCompletedPayload(_ payload: SpeciesAIPayload) {
        commonName = payload.commonName ?? commonName
        latinName = payload.nomLatin ?? latinName
        family = payload.famille ?? family
        genus = payload.genre ?? genus
        strata = payload.strate ?? strata
        tags = payload.tags ?? tags
        notes = payload.notes ?? notes
        imageURL = payload.imageURL ?? imageURL
        origin = payload.origine ?? origin
        plantType = payload.typePlante ?? plantType
        morphology = payload.morphologie ?? morphology
        culture = payload.culture ?? culture
        uses = payload.usages ?? uses
        melliferousLevel = payload.niveauMellifere ?? melliferousLevel
        ornamentalInterest = payload.interetOrnemental ?? ornamentalInterest
        lifespanMin = payload.longeviteMin ?? lifespanMin
        lifespanMax = payload.longeviteMax ?? lifespanMax
        heightMin = payload.hauteurMin ?? heightMin
        heightMax = payload.hauteurMax ?? heightMax
        floweringPeriod = payload.periodeFloraison ?? floweringPeriod
        fruitingPeriod = payload.periodeFructification ?? fruitingPeriod
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func linkedPlantsCount(for species: GardenTaxon) -> Int {
        store.plants.filter { $0.speciesID == Int(species.id) }.count
    }

    private func canDeleteSpecies(_ species: GardenTaxon) -> Bool {
        cultivars.isEmpty && linkedPlantsCount(for: species) == 0
    }

    private func deleteBlockerMessage(for species: GardenTaxon) -> String {
        let plantsCount = linkedPlantsCount(for: species)
        if !cultivars.isEmpty {
            return "Suppression impossible: cette espèce possède \(cultivars.count) cultivar(s)."
        }
        if plantsCount > 0 {
            return "Suppression impossible: cette espèce est liée à \(plantsCount) individu(s)."
        }
        return ""
    }

    private func deleteSpecies() {
        guard let existing = existingSpecies else { return }
        let result = store.deleteSpecies(id: existing.id)
        switch result {
        case .success:
            dismiss()
        case .linkedToCultivars:
            deleteResultMessage = "Suppression impossible: cette espèce est liée à des cultivars."
            showDeleteResultAlert = true
        case .linkedToPlants:
            deleteResultMessage = "Suppression impossible: cette espèce est liée à des individus."
            showDeleteResultAlert = true
        case .failure:
            deleteResultMessage = "Échec de suppression de l’espèce."
            showDeleteResultAlert = true
        }
    }

    private func hasFillProgress(from original: SpeciesAIPayload, to completed: SpeciesAIPayload) -> Bool {
        let before: [String?] = [
            original.commonName, original.nomLatin, original.famille, original.genre, original.strate,
            original.tags, original.notes, original.imageURL, original.origine, original.typePlante,
            original.morphologie, original.culture, original.usages, original.niveauMellifere,
            original.interetOrnemental, original.longeviteMin, original.longeviteMax,
            original.hauteurMin, original.hauteurMax, original.periodeFloraison, original.periodeFructification
        ]
        let after: [String?] = [
            completed.commonName, completed.nomLatin, completed.famille, completed.genre, completed.strate,
            completed.tags, completed.notes, completed.imageURL, completed.origine, completed.typePlante,
            completed.morphologie, completed.culture, completed.usages, completed.niveauMellifere,
            completed.interetOrnemental, completed.longeviteMin, completed.longeviteMax,
            completed.hauteurMin, completed.hauteurMax, completed.periodeFloraison, completed.periodeFructification
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

    private func merge(payload: SpeciesAIPayload, with fallback: SpeciesAIResponse) -> SpeciesAIPayload {
        SpeciesAIPayload(
            commonName: payload.commonName ?? normalized(fallback.commonName ?? ""),
            nomLatin: payload.nomLatin ?? normalized(fallback.nomLatin ?? ""),
            famille: payload.famille ?? normalized(fallback.famille ?? ""),
            genre: payload.genre ?? normalized(fallback.genre ?? ""),
            strate: payload.strate ?? normalized(fallback.strate ?? ""),
            tags: payload.tags ?? normalized(fallback.tags ?? ""),
            notes: payload.notes ?? normalized(fallback.notes ?? ""),
            imageURL: payload.imageURL ?? normalized(fallback.imageURL ?? ""),
            origine: payload.origine ?? normalized(fallback.origine ?? ""),
            typePlante: payload.typePlante ?? normalized(fallback.typePlante ?? ""),
            morphologie: payload.morphologie ?? normalized(fallback.morphologie ?? ""),
            culture: payload.culture ?? normalized(fallback.culture ?? ""),
            usages: payload.usages ?? normalized(fallback.usages ?? ""),
            niveauMellifere: payload.niveauMellifere ?? normalized(fallback.niveauMellifere ?? ""),
            interetOrnemental: payload.interetOrnemental ?? normalized(fallback.interetOrnemental ?? ""),
            longeviteMin: payload.longeviteMin ?? normalized(fallback.longeviteMin ?? ""),
            longeviteMax: payload.longeviteMax ?? normalized(fallback.longeviteMax ?? ""),
            hauteurMin: payload.hauteurMin ?? normalized(fallback.hauteurMin ?? ""),
            hauteurMax: payload.hauteurMax ?? normalized(fallback.hauteurMax ?? ""),
            periodeFloraison: payload.periodeFloraison ?? normalized(fallback.periodeFloraison ?? ""),
            periodeFructification: payload.periodeFructification ?? normalized(fallback.periodeFructification ?? "")
        )
    }

    @MainActor
    private func queueOrApply(field: AIField, label: String, proposed: String?) {
        let trimmed = (proposed ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
        case .commonName: return commonName
        case .latinName: return latinName
        case .family: return family
        case .genus: return genus
        case .strata: return strata
        case .tags: return tags
        case .imageURL: return imageURL
        case .origin: return origin
        case .plantType: return plantType
        case .morphology: return morphology
        case .uses: return uses
        case .melliferousLevel: return melliferousLevel
        case .ornamentalInterest: return ornamentalInterest
        case .lifespanMin: return lifespanMin
        case .lifespanMax: return lifespanMax
        case .heightMin: return heightMin
        case .heightMax: return heightMax
        case .floweringPeriod: return floweringPeriod
        case .fruitingPeriod: return fruitingPeriod
        case .notes: return notes
        case .culture: return culture
        }
    }

    @MainActor
    private func apply(_ value: String, to field: AIField) {
        switch field {
        case .commonName:
            commonName = value
        case .latinName:
            latinName = value
        case .family:
            family = value
        case .genus:
            genus = value
        case .strata:
            strata = value
        case .tags:
            tags = value
        case .imageURL:
            imageURL = value
        case .origin:
            origin = value
        case .plantType:
            plantType = value
        case .morphology:
            morphology = value
        case .uses:
            uses = value
        case .melliferousLevel:
            melliferousLevel = value
        case .ornamentalInterest:
            ornamentalInterest = value
        case .lifespanMin:
            lifespanMin = value
        case .lifespanMax:
            lifespanMax = value
        case .heightMin:
            heightMin = value
        case .heightMax:
            heightMax = value
        case .floweringPeriod:
            floweringPeriod = value
        case .fruitingPeriod:
            fruitingPeriod = value
        case .notes:
            notes = value
        case .culture:
            culture = value
        }
    }
}
