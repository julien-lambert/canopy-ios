//
//  Untitled.swift
//  JardinForet
//
//  Created by Julien Lambert on 27/11/2025.
//

import SwiftUI
import MapKit

struct PlantFormView: View {

    @EnvironmentObject var store: GardenStore
    @Environment(\.dismiss) private var dismiss

    /// Mode actuel : pour l’instant uniquement création
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

        // Valeurs par défaut des champs supplémentaires
        _microSite          = State(initialValue: "")
        _exposureLocal      = State(initialValue: "")
        _soilLocal          = State(initialValue: "")
        _status             = State(initialValue: "")
        _acquisitionType    = State(initialValue: "")
        _acquisitionSource  = State(initialValue: "")
        _careNotes          = State(initialValue: "")
        _heightCurrent      = State(initialValue: "")

        // Coordonnées GPS par défaut (non renseignées)
        _latitudeText  = State(initialValue: "")
        _longitudeText = State(initialValue: "")

        switch mode {
        case .create:
            _label = State(initialValue: "")
            _zone  = State(initialValue: "")
            _notes = State(initialValue: "")
            // Les autres champs restent à "" (déjà initialisés plus haut)

        case .edit(let plant):
            _label = State(initialValue: plant.label ?? "")
            _zone  = State(initialValue: plant.zone  ?? "")
            _notes = State(initialValue: plant.notes ?? "")

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
        }
    }

    // Liste des espèces possibles (chargées depuis la base locale)
    @State private var speciesList: [GardenTaxon]

    // Liste des cultivars possibles pour l’espèce sélectionnée
    @State private var cultivarList: [GardenTaxon] = []
    @State private var selectedCultivarId: Int?

    // Champs du formulaire
    @State private var selectedSpeciesId: Int?
    @State private var label: String
    @State private var zone: String
    @State private var notes: String

    // Champs supplémentaires (pour enrichir le formulaire)
    @State private var microSite: String
    @State private var exposureLocal: String
    @State private var soilLocal: String
    @State private var status: String
    @State private var acquisitionType: String
    @State private var acquisitionSource: String
    @State private var careNotes: String
    @State private var heightCurrent: String

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
            identitySection
            locationSection
            geoSection
            growthSection
            acquisitionSection
            notesSection
        }
        .navigationTitle(navigationTitle)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") {
                    save()
                }
                .disabled(!formIsValid)
            }
        }
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

            NavigationLink {
                SpeciesFormView(existingSpecies: nil, cultivars: [])
            } label: {
                Label("Créer une espèce", systemImage: "plus.circle")
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
                    LabeledContent("Origine", value: cultivar.origin ?? "—")
                    LabeledContent("Type", value: cultivar.plantType ?? "—")
                    LabeledContent("Mellifère", value: cultivar.melliferousLevel ?? "—")
                    LabeledContent("Ornemental", value: cultivar.ornamentalInterest ?? "—")

                    if cultivar.lifespanMin != nil || cultivar.lifespanMax != nil {
                        let min = cultivar.lifespanMin.map(String.init) ?? "?"
                        let max = cultivar.lifespanMax.map(String.init) ?? "?"
                        LabeledContent("Longévité", value: "\(min) – \(max) ans")
                    }

                    if cultivar.heightMin != nil || cultivar.heightMax != nil {
                        let min = cultivar.heightMin.map { String(format: "%.1f", $0) } ?? "?"
                        let max = cultivar.heightMax.map { String(format: "%.1f", $0) } ?? "?"
                        LabeledContent("Hauteur", value: "\(min) – \(max) m")
                    }

                    if let flowering = cultivar.floweringPeriod, !flowering.isEmpty {
                        LabeledContent("Floraison", value: flowering)
                    }
                    if let fruiting = cultivar.fruitingPeriod, !fruiting.isEmpty {
                        LabeledContent("Fructification", value: fruiting)
                    }
                }
            }

            if let selectedSpecies {
                NavigationLink {
                    CultivarFormView(
                        mode: .create(
                            speciesId: selectedSpecies.id,
                            speciesName: selectedSpecies.commonName
                        )
                    )
                } label: {
                    Label("Créer un cultivar", systemImage: "plus.circle")
                }
            }
        }
    }

    private var identitySection: some View {
        Section("Informations sur l’individu") {
            TextField("Étiquette (générée automatiquement)", text: $label)
                .disabled(true)

            Picker("Statut de l’individu", selection: $status) {
                // Option vide = statut non renseigné
                Text("Aucun").tag("")

                ForEach(statusOptions, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
        }
    }

    private var locationSection: some View {
        Section("Localisation") {
            TextField("Zone / îlot", text: $zone)
            TextField("Micro-site local", text: $microSite)

            Picker("Exposition locale", selection: $exposureLocal) {
                Text("Aucune").tag("")

                ForEach(exposureOptions, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }

            TextField("Type de sol local", text: $soilLocal)
        }
    }

    private var geoSection: some View {
        Section("Position géographique") {
            HStack {
                Text("Latitude")
                Spacer()
                TextField("Latitude", text: $latitudeText)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
            }

            HStack {
                Text("Longitude")
                Spacer()
                TextField("Longitude", text: $longitudeText)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
            }

            NavigationLink("Placer / déplacer sur la carte") {
                CoordinatePickerView(
                    latitudeText: $latitudeText,
                    longitudeText: $longitudeText
                )
            }
        }
    }

    private var growthSection: some View {
        Section("Croissance") {
            TextField("Hauteur actuelle (cm)", text: $heightCurrent)
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
        }
    }

    private var acquisitionSection: some View {
        Section("Acquisition & origine") {
            Picker("Type d’acquisition", selection: $acquisitionType) {
                Text("Aucun").tag("")

                ForEach(acquisitionTypeOptions, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }

            TextField("Source / fournisseur", text: $acquisitionSource)
        }
    }

    private var notesSection: some View {
        Section("Notes & entretien") {
            TextField("Notes générales", text: $notes, axis: .vertical)
                .lineLimit(3...6)

            TextField("Notes d’entretien (taille, protection…)", text: $careNotes, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    // MARK: - Helpers

    private var navigationTitle: String {
        switch mode {
        case .create:
            return "Nouvelle plante"
        case .edit(_):
            return "Modifier la plante"
        }
    }

    /// Formulaire valide ?
    private var formIsValid: Bool {
        // Pour l’instant : il faut au moins une espèce sélectionnée
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
        // On trie par nom commun
        speciesList = list.sorted { (a, b) in
            a.commonName.localizedCaseInsensitiveCompare(b.commonName) == .orderedAscending
        }
    }

    /// Chargement des cultivars pour l'espèce actuellement sélectionnée
    private func loadCultivarsForCurrentSpecies() {
        guard let speciesId = selectedSpeciesId else {
            cultivarList = []
            selectedCultivarId = nil
            return
        }

        // On récupère l'espèce correspondante pour obtenir son nom latin
        guard let species = speciesList.first(where: { $0.id == speciesId }) else {
            cultivarList = []
            selectedCultivarId = nil
            return
        }

        // On utilise le détail d'espèce pour récupérer la liste des cultivars
        guard let detail = store.fetchSpeciesDetail(latinName: species.latinName) else {
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

        // On essaie de retrouver l'espèce correspondante à partir du nom latin de la plante
        if let match = speciesList.first(where: { $0.latinName == plant.latinName }) {
            selectedSpeciesId = match.id
        } else {
            selectedSpeciesId = nil
        }

        // Préremplissage des champs texte à partir de la plante existante
        label = plant.label ?? ""
        zone  = plant.zone  ?? ""
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
        let latValue    = parseDouble(latitudeText)
        let lonValue    = parseDouble(longitudeText)
        let writeInput = PlantWriteInput(
            speciesId: speciesId,
            varietyId: selectedCultivarId,
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
}

// MARK: - Carte de sélection des coordonnées

struct CoordinatePickerView: View {
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
                CoordinatePickerMap(region: $region)
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
    }
}

// MARK: - MKMapView wrapper pour afficher les îlots + centre de la carte

// MARK: - MKMapView wrapper pour afficher les îlots + centre de la carte

#if canImport(UIKit)
struct CoordinatePickerMap: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion

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

        // Chargement des îlots depuis le bundle
        if let url = Bundle.main.url(forResource: "ilots_wgs84", withExtension: "geojson") {
            do {
                let data = try Data(contentsOf: url)
                let decoder = MKGeoJSONDecoder()
                let objects = try decoder.decode(data)

                var overlays: [MKOverlay] = []

                for object in objects {
                    guard let feature = object as? MKGeoJSONFeature else { continue }
                    for geom in feature.geometry {
                        if let polygon = geom as? MKPolygon {
                            overlays.append(polygon)
                        } else if let multi = geom as? MKMultiPolygon {
                            overlays.append(multi)
                        }
                    }
                }

                mapView.addOverlays(overlays)

                if !overlays.isEmpty {
                    let rect = overlays.reduce(MKMapRect.null) { partial, overlay in
                        if partial.isNull {
                            return overlay.boundingMapRect
                        } else {
                            return partial.union(overlay.boundingMapRect)
                        }
                    }
                    // On garde un zoom serré sur les îlots, sans écraser la région initiale si elle est loin
                    if rect.size.width > 0 && rect.size.height > 0 {
                        mapView.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40), animated: false)
                    }
                }

            } catch {
                AppLog.error("Erreur chargement ilots_wgs84.geojson: \(error)", category: .map)
            }
        } else {
            AppLog.warning("Fichier ilots_wgs84.geojson introuvable dans le bundle", category: .map)
        }

        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        // Ici, on laisse la carte être pilotée essentiellement par l’utilisateur.
        // Si plus tard tu veux recadrer depuis l’extérieur, tu pourras adapter.
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: CoordinatePickerMap

        init(_ parent: CoordinatePickerMap) {
            self.parent = parent
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
