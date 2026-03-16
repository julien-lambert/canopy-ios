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

    init(mode: Mode) {
        self.mode = mode

        // Initialisation des @State
        _speciesList = State(initialValue: [])
        _cultivarList = State(initialValue: [])
        _selectedCultivarId = State(initialValue: nil)
        _selectedSpeciesId = State(initialValue: nil)
        _selectedSiteIlotCode = State(initialValue: "")
        _showQuickSpeciesCreator = State(initialValue: false)
        _showQuickCultivarCreator = State(initialValue: false)

        // Valeurs par défaut des champs supplémentaires
        _microSite          = State(initialValue: "")
        _exposureLocal      = State(initialValue: "")
        _soilLocal          = State(initialValue: "")
        _status             = State(initialValue: "")
        _acquisitionType    = State(initialValue: "")
        _acquisitionSource  = State(initialValue: "")
        _careNotes          = State(initialValue: "")
        _heightCurrent      = State(initialValue: "")
        _envergureCurrent   = State(initialValue: "")

        // Coordonnées GPS par défaut (non renseignées)
        _latitudeText  = State(initialValue: "")
        _longitudeText = State(initialValue: "")

        switch mode {
        case .create:
            _label = State(initialValue: "")
            _zone  = State(initialValue: "")
            _selectedSiteIlotCode = State(initialValue: "")
            _notes = State(initialValue: "")
            _showAdvancedFields = State(initialValue: false)
            // Les autres champs restent à "" (déjà initialisés plus haut)

        case .edit(let plant):
            _label = State(initialValue: plant.label ?? "")
            _zone  = State(initialValue: plant.zone  ?? "")
            _selectedSiteIlotCode = State(initialValue: plant.siteIlotCode ?? "")
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
    @State private var selectedSiteIlotCode: String

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
                Picker("Îlot du site", selection: $selectedSiteIlotCode) {
                    Text("Auto / aucun").tag("")
                    ForEach(store.siteIlots.sorted(by: ilotSort), id: \.id) { ilot in
                        Text(ilotDisplayLabel(ilot)).tag(ilot.code)
                    }
                }
            }

            TextField("Repère / zone libre", text: $zone)

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
                CoordinatePickerView(
                    latitudeText: $latitudeText,
                    longitudeText: $longitudeText
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
        selectedSiteIlotCode = plant.siteIlotCode ?? ""
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
        let cleanSelectedIlotCode = selectedSiteIlotCode.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let effectiveZone = cleanSelectedIlotCode.isEmpty ? cleanZone : cleanSelectedIlotCode
        let writeInput = PlantWriteInput(
            speciesId: speciesId,
            varietyId: selectedCultivarId,
            zone: effectiveZone.isEmpty ? nil : effectiveZone,
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

// MARK: - Carte de sélection des coordonnées

struct CoordinatePickerView: View {
    @EnvironmentObject var store: CanopyStore
    @Binding var latitudeText: String
    @Binding var longitudeText: String

    @State private var region: MKCoordinateRegion

    init(latitudeText: Binding<String>, longitudeText: Binding<String>) {
        _latitudeText = latitudeText
        _longitudeText = longitudeText

        // Point de départ : soit les valeurs actuelles, soit un centre par défaut
        let lat = Double(latitudeText.wrappedValue) ?? 45.3488
        let lon = Double(longitudeText.wrappedValue) ?? 4.0730

        _region = State(initialValue: MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            span: MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002)
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                #if canImport(UIKit)
                CoordinatePickerMap(
                    region: $region,
                    terrainPolygons: store.mapTerrainPolygons,
                    ilotPolygons: store.mapIlotPolygons
                )
                    .ignoresSafeArea(edges: .top)
                #else
                Map(coordinateRegion: $region)
                    .ignoresSafeArea(edges: .top)
                #endif

                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.red)
                    .shadow(radius: 3)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 8) {
                Text(String(format: "Latitude : %.7f\nLongitude : %.7f",
                            region.center.latitude,
                            region.center.longitude))
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Button("Utiliser ces coordonnées") {
                    latitudeText  = String(format: "%.7f", region.center.latitude)
                    longitudeText = String(format: "%.7f", region.center.longitude)
                }
                .buttonStyle(.borderedProminent)
                .padding(.vertical, 8)
            }
            .padding(.horizontal)

            Spacer()
        }
        .navigationTitle("Positionner l’individu")
        .onAppear {
            let latIsEmpty = latitudeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let lonIsEmpty = longitudeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard latIsEmpty, lonIsEmpty else { return }
            region.center = store.preferredTerrainCoordinate
        }
    }
}

// MARK: - MKMapView wrapper pour afficher les îlots + centre de la carte

// MARK: - MKMapView wrapper pour afficher les îlots + centre de la carte

#if canImport(UIKit)
struct CoordinatePickerMap: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    let terrainPolygons: [[CLLocationCoordinate2D]]
    let ilotPolygons: [[CLLocationCoordinate2D]]

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator

        // Région initiale
        mapView.setRegion(region, animated: false)
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.isRotateEnabled = false

        context.coordinator.syncOverlays(
            on: mapView,
            terrainPolygons: terrainPolygons,
            ilotPolygons: ilotPolygons,
            fitVisibleRect: true
        )

        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.syncOverlays(
            on: uiView,
            terrainPolygons: terrainPolygons,
            ilotPolygons: ilotPolygons,
            fitVisibleRect: false
        )
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: CoordinatePickerMap
        private var lastOverlaySignature: String?

        init(_ parent: CoordinatePickerMap) {
            self.parent = parent
        }

        func syncOverlays(
            on mapView: MKMapView,
            terrainPolygons: [[CLLocationCoordinate2D]],
            ilotPolygons: [[CLLocationCoordinate2D]],
            fitVisibleRect: Bool
        ) {
            let signature = overlaySignature(terrainPolygons: terrainPolygons, ilotPolygons: ilotPolygons)
            guard signature != lastOverlaySignature else { return }
            lastOverlaySignature = signature

            mapView.removeOverlays(mapView.overlays)

            let terrainOverlays = terrainPolygons.compactMap { coordinates -> MKPolygon? in
                guard coordinates.count >= 3 else { return nil }
                return MKPolygon(coordinates: coordinates, count: coordinates.count)
            }

            let ilotOverlays = ilotPolygons.compactMap { coordinates -> MKPolygon? in
                guard coordinates.count >= 3 else { return nil }
                return MKPolygon(coordinates: coordinates, count: coordinates.count)
            }

            let overlays = terrainOverlays + ilotOverlays
            mapView.addOverlays(overlays)

            guard fitVisibleRect, !overlays.isEmpty else { return }

            let rect = overlays.reduce(MKMapRect.null) { partial, overlay in
                partial.isNull ? overlay.boundingMapRect : partial.union(overlay.boundingMapRect)
            }
            if rect.size.width > 0 && rect.size.height > 0 {
                mapView.setVisibleMapRect(
                    rect,
                    edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
                    animated: false
                )
            }
        }

        private func overlaySignature(
            terrainPolygons: [[CLLocationCoordinate2D]],
            ilotPolygons: [[CLLocationCoordinate2D]]
        ) -> String {
            let terrainPoints = terrainPolygons.reduce(into: 0) { $0 += $1.count }
            let ilotPoints = ilotPolygons.reduce(into: 0) { $0 += $1.count }
            return "\(terrainPolygons.count)-\(terrainPoints)-\(ilotPolygons.count)-\(ilotPoints)"
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // On renvoie en permanence la région actuelle vers le binding SwiftUI
            parent.region = mapView.region
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.lineWidth = 1.0
                renderer.strokeColor = UIColor.systemGreen.withAlphaComponent(0.8)
                renderer.fillColor = UIColor.systemGreen.withAlphaComponent(0.2)
                return renderer
            } else if let multi = overlay as? MKMultiPolygon {
                let renderer = MKMultiPolygonRenderer(multiPolygon: multi)
                renderer.lineWidth = 1.0
                renderer.strokeColor = UIColor.systemGreen.withAlphaComponent(0.8)
                renderer.fillColor = UIColor.systemGreen.withAlphaComponent(0.2)
                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

#endif
