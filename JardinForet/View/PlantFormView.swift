//
//  Untitled.swift
//  JardinForet
//
//  Created by Julien Lambert on 27/11/2025.
//

import SwiftUI
import MapKit

struct PlantFormView: View {

    @EnvironmentObject var store: CanopyStore
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss

    enum Mode {
        case create
        case edit(plant: GardenPlant)
    }

    let mode: Mode
    private let prefill: PlantFormPrefill?

    init(mode: Mode, prefill: PlantFormPrefill? = nil) {
        self.mode = mode
        self.prefill = prefill

        // Initialisation des @State
        _speciesList = State(initialValue: [])
        _cultivarList = State(initialValue: [])
        _selectedCultivarId = State(initialValue: nil)
        _selectedSpeciesId = State(initialValue: prefill?.speciesID)
        _selectedSiteIlotID = State(initialValue: prefill?.siteIlotID ?? "")
        _showQuickSpeciesCreator = State(initialValue: false)
        _showQuickCultivarCreator = State(initialValue: false)

        // Valeurs par défaut des champs supplémentaires
        _microSite          = State(initialValue: "")
        _exposureLocal      = State(initialValue: "")
        _soilLocal          = State(initialValue: "")
        _status             = State(initialValue: prefill?.status ?? "")
        _acquisitionType    = State(initialValue: "")
        _acquisitionSource  = State(initialValue: "")
        _careNotes          = State(initialValue: "")
        _heightCurrent      = State(initialValue: "")
        _envergureCurrent   = State(initialValue: "")

        // Coordonnées GPS par défaut (non renseignées)
        if let latitude = prefill?.latitude {
            _latitudeText = State(initialValue: String(latitude))
        } else {
            _latitudeText = State(initialValue: "")
        }
        if let longitude = prefill?.longitude {
            _longitudeText = State(initialValue: String(longitude))
        } else {
            _longitudeText = State(initialValue: "")
        }

        switch mode {
        case .create:
            _label = State(initialValue: "")
            _zone  = State(initialValue: prefill?.zone ?? "")
            _selectedSiteIlotID = State(initialValue: prefill?.siteIlotID ?? "")
            _notes = State(initialValue: "")
            _showAdvancedFields = State(initialValue: false)
            // Les autres champs restent à "" (déjà initialisés plus haut)

        case .edit(let plant):
            _label = State(initialValue: plant.label ?? "")
            _zone  = State(initialValue: plant.zone  ?? "")
            _selectedSiteIlotID = State(initialValue: plant.siteIlotID ?? "")
            _notes = State(initialValue: plant.notes ?? "")
            _showAdvancedFields = State(
                initialValue: [plant.microSite,
                               plant.exposureLocal,
                               plant.soilLocal,
                               plant.acquisitionType,
                               plant.acquisitionSource,
                               plant.careNotes]
                    .contains { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            )

            // Préremplissage des champs supplémentaires à partir de la plante existante
            _microSite         = State(initialValue: plant.microSite ?? "")
            _exposureLocal     = State(initialValue: plant.exposureLocal ?? "")
            _soilLocal         = State(initialValue: plant.soilLocal ?? "")
            _status            = State(initialValue: plant.status ?? "")
            _acquisitionType   = State(initialValue: plant.acquisitionType ?? "")
            _acquisitionSource = State(initialValue: plant.acquisitionSource ?? "")
            _careNotes         = State(initialValue: plant.careNotes ?? "")
            if let h = plant.heightCurrent {
                _heightCurrent = State(initialValue: String(h))
            }
            if let spread = plant.spreadCurrent {
                _envergureCurrent = State(initialValue: String(spread))
            }
            if let lat = plant.lat {
                _latitudeText = State(initialValue: String(lat))
            }
            if let lon = plant.lon {
                _longitudeText = State(initialValue: String(lon))
            }
        }
    }

    // Liste des espèces possibles (chargées depuis la base locale)
    @State private var speciesList: [GardenTaxon]

    // Liste des cultivars possibles pour l’espèce sélectionnée
    @State private var cultivarList: [GardenTaxon] = []
    @State private var selectedCultivarId: Int?
    @State private var selectedSiteIlotID: String

    // Champs du formulaire
    @State private var selectedSpeciesId: Int?
    @State private var label: String
    @State private var zone: String
    @State private var notes: String
    @State private var showQuickSpeciesCreator: Bool
    @State private var showQuickCultivarCreator: Bool
    @State private var showAdvancedFields: Bool

    // Champs supplémentaires (pour enrichir le formulaire)
    @State private var microSite: String
    @State private var exposureLocal: String
    @State private var soilLocal: String
    @State private var status: String
    @State private var acquisitionType: String
    @State private var acquisitionSource: String
    @State private var careNotes: String
    @State private var heightCurrent: String
    @State private var envergureCurrent: String

    // Position géographique (texte affiché dans le formulaire)
    @State private var latitudeText: String = ""
    @State private var longitudeText: String = ""

    // Options normalisées (doivent rester cohérentes avec la base / template HTML)
    private let statusOptions: [(value: String, label: String)] = [
        ("planifié", "Planifié"),
        ("planté", "Planté"),
        ("en pépinière", "En pépinière"),
        ("malade", "Malade"),
        ("mort", "Mort"),
        ("à déplacer", "À déplacer")
    ]

    private let exposureOptions: [(value: String, label: String)] = [
        ("soleil", "Plein soleil"),
        ("mi-ombre", "Mi-ombre"),
        ("ombre", "Ombre"),
        ("ombre légère", "Ombre légère")
    ]

    private let acquisitionTypeOptions: [(value: String, label: String)] = [
        ("achat", "Achat"),
        ("don", "Don"),
        ("échange", "Échange"),
        ("semis", "Semis"),
        ("bouture", "Bouture"),
        ("greffe", "Greffe"),
        ("repiquage", "Repiquage / transplantation"),
        ("autre", "Autre")
    ]

    var body: some View {
        Form {
            speciesSection
            cultivarSection
            terrainSection
            measurementsSection
            quickObservationSection
            advancedSection
        }
        .navigationTitle(navigationTitle)
        .canopyEditorToolbar(
            saveTitle: "Enregistrer",
            isSaveDisabled: !formIsValid,
            onCancel: { dismiss() },
            onSave: { save() }
        )
        .onAppear {
            loadSpecies()
            hydrateFromExistingIfNeeded()
            normalizePickerSelections()
            loadCultivarsForCurrentSpecies()
            refreshAutomaticLabel()
            refreshSuggestedSiteIlotFromCurrentLocation()
        }
        .onChange(of: selectedSpeciesId) { _, _ in
            loadCultivarsForCurrentSpecies()
            refreshAutomaticLabel()
        }
        .onChange(of: selectedCultivarId) { _, _ in
            refreshAutomaticLabel()
        }
        .sheet(isPresented: $showQuickSpeciesCreator) {
            SpeciesQuickCreateView { newSpeciesID in
                handleQuickSpeciesCreated(newSpeciesID)
            }
            .environmentObject(store)
        }
        .sheet(isPresented: $showQuickCultivarCreator) {
            if let selectedSpecies {
                CultivarQuickCreateView(species: selectedSpecies) { remoteID in
                    handleQuickCultivarCreated(remoteID)
                }
                .environmentObject(store)
            }
        }
#if os(iOS)
        .scrollDismissesKeyboard(.interactively)
#endif
    }

    // MARK: - Sections

    private var speciesSection: some View {
        Section("Espèce") {
            if speciesList.isEmpty {
                Text("Aucune espèce disponible.\nSynchronise ou crée une espèce d’abord.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            } else {
                Picker("Espèce", selection: $selectedSpeciesId) {
                    Text("Choisir une espèce")
                        .tag(Optional<Int>.none)

                    ForEach(speciesList, id: \.id) { sp in
                        Text(speciesDisplayName(sp))
                            .tag(Optional(sp.id))
                    }
                }
#if os(iOS)
                .pickerStyle(.navigationLink)
#endif
            }

            if store.canMutateSpeciesAndIndividuals {
                Button {
                    showQuickSpeciesCreator = true
                } label: {
                    Label("Créer rapidement une espèce", systemImage: "plus.circle.fill")
                }
            }

            if let selectedSpecies, !selectedSpecies.latinName.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedSpecies.latinName)
                        .font(.subheadline)
                        .italic()
                    if let family = selectedSpecies.family, !family.isEmpty {
                        Text(family)
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                }
            }
        }
    }

    private var cultivarSection: some View {
        Section("Cultivar") {
            if selectedSpeciesId == nil {
                Text("Sélectionne d’abord une espèce pour choisir ou créer un cultivar.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else if !cultivarList.isEmpty {
                Picker("Cultivar", selection: $selectedCultivarId) {
                    Text("Aucun").tag(Optional<Int>.none)

                    ForEach(cultivarList, id: \.id) { cv in
                        Text(cv.varietyName)
                            .tag(Optional(Int(cv.id)))
                    }
                }
#if os(iOS)
                .pickerStyle(.navigationLink)
#endif

                if let cultivar = selectedCultivar {
                    Text(cultivarFieldSummary(cultivar))
                        .font(.footnote)
                        .foregroundColor(.textSecondary)
                }
            }

            if store.canMutateCultivars, selectedSpecies != nil {
                Button {
                    showQuickCultivarCreator = true
                } label: {
                    Label("Créer rapidement un cultivar", systemImage: "plus.circle.fill")
                }
            }
        }
    }

    private var terrainSection: some View {
        Section("Terrain") {
            LabeledContent("Étiquette auto", value: label.isEmpty ? "—" : label)

            Picker("Statut", selection: $status) {
                Text("Aucun").tag("")
                ForEach(statusOptions, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }

            if !store.siteIlots.isEmpty {
                Picker("Îlot du site", selection: $selectedSiteIlotID) {
                    Text("Aucun / résolution auto").tag("")
                    ForEach(store.siteIlots.sorted(by: ilotSort), id: \.id) { ilot in
                        Text(ilotDisplayLabel(ilot)).tag(ilot.id)
                    }
                }
            }

            TextField("Lieu libre / repère terrain", text: $zone)

            if locationManager.location != nil {
                Button {
                    applyCurrentLocation()
                } label: {
                    Label(hasCoordinates ? "Actualiser avec ma position" : "Utiliser ma position actuelle",
                          systemImage: "location.fill")
                }
            }

            if hasCoordinates {
                LabeledContent("Coordonnées", value: coordinatesSummary)
                    .font(.footnote)
            } else {
                Text("Aucune coordonnée enregistrée pour cet individu.")
                    .font(.footnote)
                    .foregroundColor(.textSecondary)
            }

            NavigationLink("Placer / déplacer sur la carte") {
                GardenMapView(
                    mode: .pick(
                        initialCoordinate: currentCoordinate,
                        onPick: { coordinate in
                            latitudeText = String(format: "%.7f", coordinate.latitude)
                            longitudeText = String(format: "%.7f", coordinate.longitude)
                            refreshSuggestedSiteIlotFromCurrentLocation()
                        }
                    )
                )
            }
        }
    }

    private var measurementsSection: some View {
        Section("Mesures du jour") {
            TextField("Hauteur actuelle (cm)", text: $heightCurrent)
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                #endif

            TextField("Envergure actuelle (m)", text: $envergureCurrent)
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
        }
    }

    private var quickObservationSection: some View {
        Section("Observation rapide") {
            TextField("Note terrain", text: $notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    private var advancedSection: some View {
        Section {
            DisclosureGroup("Compléter la fiche", isExpanded: $showAdvancedFields) {
                TextField("Micro-site local", text: $microSite)

                Picker("Exposition locale", selection: $exposureLocal) {
                    Text("Aucune").tag("")

                    ForEach(exposureOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }

                TextField("Type de sol local", text: $soilLocal)

                Picker("Type d’acquisition", selection: $acquisitionType) {
                    Text("Aucun").tag("")

                    ForEach(acquisitionTypeOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }

                TextField("Source / fournisseur", text: $acquisitionSource)

                TextField("Notes d’entretien (taille, protection…)", text: $careNotes, axis: .vertical)
                    .lineLimit(2...4)

                TextField("Latitude", text: $latitudeText)
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    #endif

                TextField("Longitude", text: $longitudeText)
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    #endif

                Text("Les champs avancés servent à enrichir la fiche sans ralentir la saisie terrain.")
                    .font(.footnote)
                    .foregroundColor(.textSecondary)
            }
            .tint(.accentPrimary)
        }
    }

    // MARK: - Helpers

    private var hasCoordinates: Bool {
        !latitudeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !longitudeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var coordinatesSummary: String {
        guard let latitude = Double(latitudeText.replacingOccurrences(of: ",", with: ".")),
              let longitude = Double(longitudeText.replacingOccurrences(of: ",", with: ".")) else {
            return "Coordonnées manuelles"
        }
        return String(format: "%.6f, %.6f", latitude, longitude)
    }

    private func cultivarFieldSummary(_ cultivar: GardenTaxon) -> String {
        var parts: [String] = []
        if let type = cultivar.plantType, !type.isEmpty {
            parts.append(type)
        }
        if cultivar.heightMin != nil || cultivar.heightMax != nil {
            let min = cultivar.heightMin.map { String(format: "%.1f", $0) } ?? "?"
            let max = cultivar.heightMax.map { String(format: "%.1f", $0) } ?? "?"
            parts.append("h. \(min)-\(max) m")
        }
        if let fruiting = cultivar.fruitingPeriod, !fruiting.isEmpty {
            parts.append("fruits \(fruiting)")
        }
        return parts.isEmpty ? "Cultivar sélectionné pour cet individu." : parts.joined(separator: " • ")
    }

    private func applyCurrentLocation() {
        guard let location = locationManager.location else { return }
        latitudeText = String(format: "%.7f", location.coordinate.latitude)
        longitudeText = String(format: "%.7f", location.coordinate.longitude)
        refreshSuggestedSiteIlotFromCurrentLocation()
    }

    private var currentCoordinate: CLLocationCoordinate2D? {
        guard
            let latitude = Double(latitudeText.replacingOccurrences(of: ",", with: ".")),
            let longitude = Double(longitudeText.replacingOccurrences(of: ",", with: "."))
        else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func refreshSuggestedSiteIlotFromCurrentLocation() {
        guard selectedSiteIlotID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let coordinate = currentCoordinate else { return }

        let suggestedID = store.suggestedSiteIlotID(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            zone: zone
        )

        if let suggestedID {
            selectedSiteIlotID = suggestedID
        }
    }

    private func handleQuickSpeciesCreated(_ newSpeciesID: Int) {
        loadSpecies()
        selectedSpeciesId = newSpeciesID
        selectedCultivarId = nil
        loadCultivarsForCurrentSpecies()
        refreshAutomaticLabel()
    }

    private func handleQuickCultivarCreated(_ remoteID: String) {
        loadCultivarsForCurrentSpecies()
        if let match = cultivarList.first(where: { $0.uuid == remoteID }) {
            selectedCultivarId = match.id
        }
        refreshAutomaticLabel()
    }

    private var navigationTitle: String {
        switch mode {
        case .create:
            return "Nouvel individu"
        case .edit(_):
            return "Modifier l’individu"
        }
    }

    /// Formulaire valide ?
    private var formIsValid: Bool {
        selectedSpeciesId != nil
    }

    /// S'assure que les valeurs liées aux Picker correspondent à des tags valides
    /// pour éviter les warnings du type "selection ... is invalid and does not have an associated tag".
    private func normalizePickerSelections() {
        let validStatusValues = Set(statusOptions.map { $0.value })
        if !validStatusValues.contains(status) {
            status = ""
        }

        let validExposureValues = Set(exposureOptions.map { $0.value })
        if !validExposureValues.contains(exposureLocal) {
            exposureLocal = ""
        }

        let validAcquisitionValues = Set(acquisitionTypeOptions.map { $0.value })
        if !validAcquisitionValues.contains(acquisitionType) {
            acquisitionType = ""
        }
    }

    /// Texte affiché dans la liste des espèces
    private func speciesDisplayName(_ sp: GardenTaxon) -> String {
        let common = sp.commonName.isEmpty ? "Nom commun ?" : sp.commonName
        let latin  = sp.latinName.isEmpty ? "" : sp.latinName

        if latin.isEmpty {
            return common
        } else {
            return "\(common) (\(latin))"
        }
    }

    private var selectedCultivar: GardenTaxon? {
        guard let selectedCultivarId else { return nil }
        return cultivarList.first(where: { Int($0.id) == selectedCultivarId })
    }

    private var selectedSpecies: GardenTaxon? {
        guard let selectedSpeciesId else { return nil }
        return speciesList.first(where: { $0.id == selectedSpeciesId })
    }

    /// Chargement des espèces depuis la base locale
    private func loadSpecies() {
        let list = store.fetchSpeciesBase()

        // Déduplique les doublons visibles dans le picker (même espèce logique),
        // en gardant l'entrée la plus utile (cultivars/plants les plus nombreux).
        var bestByKey: [String: GardenTaxon] = [:]

        for species in list {
            let latin = species.latinName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let common = species.commonName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let key = latin.isEmpty ? "common:\(common)" : "latin:\(latin)"

            guard let existing = bestByKey[key] else {
                bestByKey[key] = species
                continue
            }

            let currentScore = (species.cultivarCount, species.plantCount, species.id)
            let existingScore = (existing.cultivarCount, existing.plantCount, existing.id)
            if currentScore > existingScore {
                bestByKey[key] = species
            }
        }

        speciesList = bestByKey.values.sorted { lhs, rhs in
            lhs.commonName.localizedCaseInsensitiveCompare(rhs.commonName) == .orderedAscending
        }
    }

    /// Chargement des cultivars pour l'espèce actuellement sélectionnée
    private func loadCultivarsForCurrentSpecies() {
        guard let speciesId = selectedSpeciesId else {
            cultivarList = []
            selectedCultivarId = nil
            return
        }

        // On utilise le détail par ID pour éviter les collisions quand plusieurs
        // lignes legacy partagent le même nom latin.
        guard let detail = store.fetchSpeciesDetail(speciesId: Int32(speciesId)) else {
            cultivarList = []
            selectedCultivarId = nil
            return
        }
        cultivarList = detail.cultivars

        // Si on est en mode édition, on essaie de pré-sélectionner le cultivar correspondant
        if case .edit(let plant) = mode,
           let plantVarietyName = plant.varietyName,
           !plantVarietyName.isEmpty,
           selectedCultivarId == nil {

            if let match = cultivarList.first(where: { $0.varietyName == plantVarietyName }) {
                selectedCultivarId = Int(match.id)
                return
            }
        }

        // Sinon, on vérifie simplement que la sélection actuelle reste cohérente
        if let currentId = selectedCultivarId,
           !cultivarList.contains(where: { Int($0.id) == currentId }) {
            selectedCultivarId = nil
        }
    }

    /// Préremplit les champs si on est en mode édition
    private func hydrateFromExistingIfNeeded() {
        guard case .edit(let plant) = mode else { return }

        // On privilégie l'identifiant stable de l'espèce portée par l'individu.
        if let matchByID = speciesList.first(where: { $0.id == plant.speciesID }) {
            selectedSpeciesId = matchByID.id
        } else if let match = speciesList.first(where: { $0.latinName == plant.latinName }) {
            selectedSpeciesId = match.id
        } else {
            selectedSpeciesId = nil
        }

        // Préremplissage des champs texte à partir de la plante existante
        label = plant.label ?? ""
        zone  = plant.zone  ?? ""
        selectedSiteIlotID = plant.siteIlotID ?? ""
        notes = plant.notes ?? ""
    }

    private func refreshAutomaticLabel() {
        guard let speciesId = selectedSpeciesId else {
            label = ""
            return
        }

        let existingPlantID: Int?
        switch mode {
        case .create:
            existingPlantID = nil
        case .edit(let plant):
            existingPlantID = plant.id
        }

        do {
            label = try store.generateAutomaticPlantLabel(
                speciesId: speciesId,
                varietyId: selectedCultivarId,
                existingPlantID: existingPlantID
            )
        } catch {
            AppLog.error("Erreur génération étiquette auto: \(error)", category: .database)
        }
    }

    /// Action Enregistrer
    private func save() {
        guard let speciesId = selectedSpeciesId else {
            return
        }

        // Nettoyage des chaînes : on évite d’enregistrer des espaces vides
        let cleanZone    = zone.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSelectedIlotID = selectedSiteIlotID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes   = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanStatus  = status.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMicro   = microSite.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanExpo    = exposureLocal.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSoil    = soilLocal.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAcqType = acquisitionType.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAcqSrc  = acquisitionSource.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCare    = careNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        // Conversion des champs numériques éventuels (hauteur, latitude, longitude)
        func parseDouble(_ text: String) -> Double? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
            return Double(normalized)
        }

        let heightValue = parseDouble(heightCurrent)
        let spreadValue = parseDouble(envergureCurrent)
        let latValue    = parseDouble(latitudeText)
        let lonValue    = parseDouble(longitudeText)
        let effectiveSiteIlotID = cleanSelectedIlotID.isEmpty ? nil : cleanSelectedIlotID
        let writeInput = PlantWriteInput(
            speciesId: speciesId,
            varietyId: selectedCultivarId,
            siteIlotID: effectiveSiteIlotID,
            zone: cleanZone.isEmpty ? nil : cleanZone,
            notes: cleanNotes.isEmpty ? nil : cleanNotes,
            status: cleanStatus.isEmpty ? nil : cleanStatus,
            microSite: cleanMicro.isEmpty ? nil : cleanMicro,
            exposureLocal: cleanExpo.isEmpty ? nil : cleanExpo,
            soilLocal: cleanSoil.isEmpty ? nil : cleanSoil,
            acquisitionType: cleanAcqType.isEmpty ? nil : cleanAcqType,
            acquisitionSource: cleanAcqSrc.isEmpty ? nil : cleanAcqSrc,
            careNotes: cleanCare.isEmpty ? nil : cleanCare,
            heightCurrent: heightValue,
            envergureCurrent: spreadValue,
            latitude: latValue,
            longitude: lonValue
        )

        switch mode {
        case .create:
            store.createPlant(writeInput)

        case .edit(let plant):
            store.updatePlant(plant, with: writeInput)
        }

        dismiss()
    }

    private func ilotSort(lhs: GardenSiteIlot, rhs: GardenSiteIlot) -> Bool {
        let lhsCode = lhs.code.localizedStandardCompare(rhs.code)
        if lhsCode != .orderedSame {
            return lhsCode == .orderedAscending
        }
        return (lhs.name ?? "").localizedCaseInsensitiveCompare(rhs.name ?? "") == .orderedAscending
    }

    private func ilotDisplayLabel(_ ilot: GardenSiteIlot) -> String {
        if let name = ilot.name, !name.isEmpty {
            return "\(ilot.code) — \(name)"
        }
        return ilot.code
    }
}
