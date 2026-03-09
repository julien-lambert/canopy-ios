//
//  GardenMapView.swift
//  JardinForet
//
//  Created by Julien Lambert on 17/11/2025.
//

import SwiftUI
import MapKit


struct GardenMapView: View {
    @EnvironmentObject var store: GardenStore
    @EnvironmentObject var locationManager: LocationManager
    @Environment(\.colorScheme) private var colorScheme

    // Legacy SwiftUI Map state (kept so existing MapContent helpers still compile; not used by MKMapView backend)
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var currentRegion: MKCoordinateRegion? = nil
    @State private var showWisdomTreeLabel = false

    // Legacy viewport size (used by old SwiftUI crown conversion)
    @State private var mapViewportSize: CGSize = .zero


    // Pins issus de la base
    @State private var pins: [PlantPin] = []

    // Filtre de strate sélectionné
    @State private var selectedStrataFilter: StrataFilter = .all

    // Polygones du terrain (GeoJSON)
    @State private var terrainPolygons: [[CLLocationCoordinate2D]] = []

    // Polygones des îlots (GeoJSON)
    @State private var ilotPolygons: [[CLLocationCoordinate2D]] = []

    // Pour ne régler la caméra qu’une seule fois
    @State private var didSetInitialCamera = false

    // Sélection éventuelle d’un pin (si tu veux ensuite afficher un panneau)
    @State private var selectedPin: PlantPin?
    @State private var sheetPin: PlantPin? = nil
    @State private var pendingLongPressPin: PlantPin? = nil
    @State private var editingDraft: PlantEditDraft? = nil

    // Style logique de la carte (photo / plan NB)
    enum MapBaseStyle {
        case photo
        case planNB
        case ignPlan

        var signatureKey: String {
            switch self {
            case .photo: return "photo"
            case .planNB: return "planNB"
            case .ignPlan: return "ignPlan"
            }
        }
    }

    @State private var selectedMapBaseStyle: MapBaseStyle = .ignPlan
    @State private var hillshadeEnabled: Bool = true

    struct PlantEditDraft: Identifiable {
        let id: Int
        let commonName: String
        var coordinate: CLLocationCoordinate2D
        var canopyDiameterMeters: Double
    }

    private let canopyMinMeters: Double = 0.02   // 2 cm
    private let canopyMaxMeters: Double = 20.0   // 20 m

    /// Style MapKit dérivé du style logique
    private var currentMapStyle: MapStyle {
        switch selectedMapBaseStyle {
        case .photo:
            return .hybrid
        case .planNB:
            return .mutedStandard
        case .ignPlan:
            return .mutedStandard
        }
    }

    // Palette de couleurs pastel pour les îlots (remplissage)
    private let ilotFillColors: [Color] = [
        Color(red: 0.95, green: 0.78, blue: 0.78),  // rose pâle
        Color(red: 0.96, green: 0.88, blue: 0.72),  // beige / sable
        Color(red: 0.80, green: 0.90, blue: 0.80),  // vert tendre
        Color(red: 0.78, green: 0.86, blue: 0.96),  // bleu pastel
        Color(red: 0.91, green: 0.80, blue: 0.96)   // mauve clair
    ]

    // Palette correspondant, mais plus foncée pour les contours et labels
    private let ilotStrokeColors: [Color] = [
        Color(red: 0.75, green: 0.30, blue: 0.30),  // rouge brique
        Color(red: 0.70, green: 0.50, blue: 0.15),  // ocre
        Color(red: 0.20, green: 0.55, blue: 0.25),  // vert moyen
        Color(red: 0.20, green: 0.40, blue: 0.70),  // bleu moyen
        Color(red: 0.45, green: 0.25, blue: 0.60)   // mauve soutenu
    ]

    // Helper for uniform map symbols

    // Petit chip de sélection de style de carte
    private struct MapStyleChip: View {
        let systemName: String
        let label: String
        let isActive: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 4) {
                    Image(systemName: systemName)
                        .font(.system(size: 12, weight: .medium))
                    Text(label)
                        .font(.caption2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isActive ? Color.accentPrimary : Color.cardBackground)
                )
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .overlay(
                    Capsule()
                        .stroke(Color.accentPrimary.opacity(isActive ? 0.0 : 0.4), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private struct MapPOI: View {
        let systemName: String
        let color: Color
        let label: String?
        let size: CGFloat = 32  // unified symbol size

        var body: some View {
            VStack(spacing: 2) {
                Image(systemName: systemName)
                    .font(.system(size: size))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(color)

                if let label = label {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(Color.primary)
                }
            }
        }
    }

    // Filtre de strate (toutes / canopée / sous-étage / arbuste / herbacée / couvre-sol / liane)
    enum StrataFilter: String, CaseIterable, Identifiable {
        case all
        case canopee
        case sousEtage
        case arbuste
        case herbacée
        case couvreSol
        case liane

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all:        return "Toutes"
            case .canopee:    return "Canopée"
            case .sousEtage:  return "Sous-étage"
            case .arbuste:    return "Arbustes"
            case .herbacée:   return "Herbacées"
            case .couvreSol:  return "Couvre-sol"
            case .liane:      return "Lianes"
            }
        }

        /// Valeur telle qu’enregistrée en base (champ `strata` en minuscule).
        var dbValue: String? {
            switch self {
            case .all:        return nil
            case .canopee:    return "canopée"
            case .sousEtage:  return "sous-étage"
            case .arbuste:    return "arbuste"
            case .herbacée:   return "herbacée"
            case .couvreSol:  return "couvre-sol"
            case .liane:      return "liane"
            }
        }

        func matches(_ strata: String?) -> Bool {
            guard let stored = strata?.lowercased() else {
                // si aucune strate en base, on ne l’affiche que si on est sur "Toutes"
                return self == .all
            }
            guard let target = dbValue else {
                // filtre = Toutes
                return true
            }
            return stored == target
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            if pins.isEmpty && terrainPolygons.isEmpty {
                MapPlaceholderView()
                    .ignoresSafeArea(edges: .top)
            } else {
                Group {
#if os(iOS) && canImport(MapLibre)
                    if selectedMapBaseStyle == .ignPlan {
                        IGNVectorMapView(
                            pins: pins,
                            selectedStrataFilter: selectedStrataFilter,
                            terrainPolygons: terrainPolygons,
                            ilotPolygons: ilotPolygons,
                            hillshadeEnabled: hillshadeEnabled,
                            hillshadeOpacity: 1.0,
                            editingDraft: editingDraft,
                            onPinTap: { pin in
                                if selectedPin?.id == pin.id {
                                    sheetPin = pin
                                } else {
                                    selectedPin = pin
                                }
                            },
                            onPinLongPress: { pin in
                                pendingLongPressPin = pin
                            },
                            onPinDrag: { pin, coordinate in
                                guard editingDraft?.id == pin.id else { return }
                                editingDraft?.coordinate = coordinate
                            },
                            onRegionChange: { region in
                                currentRegion = region
                            }
                        )
                    } else {
                        GardenMapUIKitView(
                            pins: pins,
                            selectedStrataFilter: selectedStrataFilter,
                            terrainPolygons: terrainPolygons,
                            ilotPolygons: ilotPolygons,
                            mapBaseStyle: selectedMapBaseStyle,
                            hillshadeEnabled: hillshadeEnabled,
                            hillshadeOpacity: 1.0,
                            colorScheme: colorScheme,
                            editingDraft: editingDraft,
                            onPinTap: { pin in
                                if selectedPin?.id == pin.id {
                                    sheetPin = pin
                                } else {
                                    selectedPin = pin
                                }
                            },
                            onPinLongPress: { pin in
                                pendingLongPressPin = pin
                            },
                            onPinDrag: { pin, coordinate in
                                guard editingDraft?.id == pin.id else { return }
                                editingDraft?.coordinate = coordinate
                            },
                            onRegionChange: { region in
                                currentRegion = region
                            }
                        )
                    }
#else
                    GardenMapUIKitView(
                        pins: pins,
                        selectedStrataFilter: selectedStrataFilter,
                        terrainPolygons: terrainPolygons,
                        ilotPolygons: ilotPolygons,
                        mapBaseStyle: selectedMapBaseStyle,
                        hillshadeEnabled: hillshadeEnabled,
                        hillshadeOpacity: 1.0,
                        colorScheme: colorScheme,
                        editingDraft: editingDraft,
                        onPinTap: { pin in
                            if selectedPin?.id == pin.id {
                                sheetPin = pin
                            } else {
                                selectedPin = pin
                            }
                        },
                        onPinLongPress: { pin in
                            pendingLongPressPin = pin
                        },
                        onPinDrag: { pin, coordinate in
                            guard editingDraft?.id == pin.id else { return }
                            editingDraft?.coordinate = coordinate
                        },
                        onRegionChange: { region in
                            currentRegion = region
                        }
                    )
#endif
                }
                .ignoresSafeArea(edges: .top)
            }

            // headerOverlay
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 6) {
                        MapStyleChip(
                            systemName: "photo.on.rectangle",
                            label: "Photo",
                            isActive: selectedMapBaseStyle == .photo
                        ) {
                            selectedMapBaseStyle = .photo
                        }

                        MapStyleChip(
                            systemName: "globe.europe.africa",
                            label: "IGN Plan",
                            isActive: selectedMapBaseStyle == .ignPlan
                        ) {
                            selectedMapBaseStyle = .ignPlan
                        }

                        MapStyleChip(
                            systemName: hillshadeEnabled ? "mountain.2.fill" : "mountain.2",
                            label: "Relief",
                            isActive: hillshadeEnabled
                        ) {
                            hillshadeEnabled.toggle()
                        }
                    }
                    .padding(6)
                    .background(Color.cardBackground)
                    .clipShape(Capsule())
                    .shadow(radius: 3)

                    Spacer()

                    // Boussole Apple, toujours visible, calée à droite
                    MapCompass()
                        .padding(6)
                        .background(Color.cardBackground)
                        .clipShape(Circle())
                        .shadow(radius: 3)
                }

                // (StrataFilterBar moved to bottom overlay)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Bottom overlay: strata filter bar
            VStack {
                Spacer()
                if let draft = editingDraft {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Edition: \(draft.commonName)")
                            .font(.subheadline.weight(.semibold))
                        Text("Canopée: \(formattedCanopyLength(draft.canopyDiameterMeters))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Slider(
                            value: Binding(
                                get: {
                                    let size = editingDraft?.canopyDiameterMeters ?? draft.canopyDiameterMeters
                                    return logarithmicUnitValue(for: size)
                                },
                                set: { newValue in
                                    editingDraft?.canopyDiameterMeters = canopySizeFromLogarithmicUnit(newValue)
                                }
                            ),
                            in: 0...1
                        )

                        HStack(spacing: 10) {
                            Button("Annuler", role: .cancel) {
                                editingDraft = nil
                            }
                            .buttonStyle(.bordered)

                            Button("Enregistrer") {
                                saveCurrentPlantEdit()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(12)
                    .background(Color.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(radius: 3)
                    .padding(.bottom, 10)
                }
                HStack {
                    StrataFilterBar(selected: $selectedStrataFilter)
                        .padding(8)
                        .background(Color.cardBackground)
                        .clipShape(Capsule())
                        .shadow(radius: 3)
                }
                .padding(.bottom, 20)
            }
            .padding(.horizontal)
        }
        .sheet(item: $sheetPin) { pin in
            if let plant = store.plants.first(where: { $0.id == pin.id }) {
                PlantDetailView(plant: plant)
            } else {
                Text("Plante introuvable")
            }
        }
        .confirmationDialog(
            "Action sur l'arbre",
            isPresented: Binding(
                get: { pendingLongPressPin != nil },
                set: { if !$0 { pendingLongPressPin = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Ouvrir la fiche") {
                if let pin = pendingLongPressPin {
                    sheetPin = pin
                }
                pendingLongPressPin = nil
            }
            Button("Modifier position et taille") {
                if let pin = pendingLongPressPin {
                    beginEditing(pin)
                }
                pendingLongPressPin = nil
            }
            Button("Annuler", role: .cancel) {
                pendingLongPressPin = nil
            }
        } message: {
            Text("Choisis l'action à effectuer sur cet individu.")
        }
        .onAppear {
            // Centre initial : arbre de la sagesse (référence commune)
            let wisdomTreeCoordinate = CLLocationCoordinate2D(
                latitude: 45.348828976987036,
                longitude: 4.0740432545957255
            )

            // Centre souhaité pour la vue globale du jardin sur macOS
            let macInitialCenter = CLLocationCoordinate2D(
                latitude: 45.3488016728169,
                longitude: 4.073794389888802
            )

#if os(macOS)
            // macOS : écran plus large → zoom plus serré et centrage fixe sur le cœur du jardin
            let region = MKCoordinateRegion(
                center: macInitialCenter,
                span: MKCoordinateSpan(
                    latitudeDelta: 0.00035,
                    longitudeDelta: 0.00035
                )
            )
            cameraPosition = .region(region)
#else
            // iOS : comportement précédent (auto en fonction du contenu, centré sur l'arbre de la sagesse)
            let region = regionForCoordinates([wisdomTreeCoordinate])
            cameraPosition = .region(region)
#endif

            didSetInitialCamera = true

            // Puis chargement des overlays et des pins
            loadTerrainOverlay()
            loadIlotsOverlay()
            reloadPins()
        }
        .navigationTitle("Carte du jardin")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    private func beginEditing(_ pin: PlantPin) {
        selectedPin = pin
        editingDraft = PlantEditDraft(
            id: pin.id,
            commonName: pin.commonName,
            coordinate: pin.coordinate,
            canopyDiameterMeters: max(
                canopyMinMeters,
                min(canopyMaxMeters, pin.canopyDiameterMeters ?? CanopyMarkerStyle.fallbackDiameterMeters(for: pin.strata))
            )
        )
    }

    private func saveCurrentPlantEdit() {
        guard let draft = editingDraft else { return }
        store.updatePlantGeometry(
            plantID: draft.id,
            latitude: draft.coordinate.latitude,
            longitude: draft.coordinate.longitude,
            canopyDiameterMeters: max(canopyMinMeters, min(canopyMaxMeters, draft.canopyDiameterMeters))
        )
        editingDraft = nil
        reloadPins()
    }

    private func logarithmicUnitValue(for sizeMeters: Double) -> Double {
        let s = max(canopyMinMeters, min(canopyMaxMeters, sizeMeters))
        return log(s / canopyMinMeters) / log(canopyMaxMeters / canopyMinMeters)
    }

    private func canopySizeFromLogarithmicUnit(_ t: Double) -> Double {
        let u = min(max(t, 0), 1)
        return canopyMinMeters * pow(canopyMaxMeters / canopyMinMeters, u)
    }

    private func formattedCanopyLength(_ meters: Double) -> String {
        if meters < 1 {
            return String(format: "%.0f cm", meters * 100.0)
        }
        return String(format: "%.2f m", meters)
    }
    

    // MARK: - Chargement du GeoJSON ilots.geojson

    private func loadIlotsOverlay() {
        guard let url = Bundle.main.url(forResource: "ilots_wgs84", withExtension: "geojson") else {
            AppLog.warning("ilots_wgs84.geojson introuvable dans le bundle", category: .map)
            return
        }

        do {
            let data = try Data(contentsOf: url)
            AppLog.debug("ilots.geojson charge (\(data.count) octets)", category: .map)

            let decoder = MKGeoJSONDecoder()
            let objects = try decoder.decode(data)
            AppLog.debug("MKGeoJSONDecoder ilots: \(objects.count) objets", category: .map)

            var polys: [[CLLocationCoordinate2D]] = []

            for object in objects {
                guard let feature = object as? MKGeoJSONFeature else { continue }

                for geom in feature.geometry {

                    if let multi = geom as? MKMultiPolygon {
                        AppLog.debug("[ilots] MultiPolygon: \(multi.polygons.count) polygones", category: .map)
                        for poly in multi.polygons {
                            let coords = poly.coordinatesArray
                            AppLog.debug("[ilots] polygon: \(coords.count) points", category: .map)
                            if !coords.isEmpty {
                                polys.append(coords)
                            }
                        }
                        continue
                    }

                    if let poly = geom as? MKPolygon {
                        let coords = poly.coordinatesArray
                        AppLog.debug("[ilots] Polygon: \(coords.count) points", category: .map)
                        if !coords.isEmpty {
                            polys.append(coords)
                        }
                        continue
                    }

                    if let line = geom as? MKPolyline {
                        let coords = line.coordinatesArray
                        AppLog.debug("[ilots] Polyline: \(coords.count) points", category: .map)
                        if !coords.isEmpty {
                            polys.append(coords)
                        }
                        continue
                    }
                }
            }

            AppLog.info("[ilots] polygones/segments extraits: \(polys.count)", category: .map)
            if let first = polys.first, let firstCoord = first.first {
                AppLog.debug("[ilots] premier point: lat=\(firstCoord.latitude), lon=\(firstCoord.longitude)", category: .map)
            }

            ilotPolygons = polys

        } catch {
            AppLog.warning("Erreur de decodage ilots.geojson: \(error)", category: .map)
        }
    }
    // MARK: - Extracted map layers (compiler-friendly)
    @MapContentBuilder
    private var layers: some MapContent {
        terrainLayer
        ilotLayer
        pinsLayer
        poiLayer
        userLocationLayer
    }

    @MapContentBuilder
    private var userLocationLayer: some MapContent {
        // Utilise l'instance injectée via @EnvironmentObject
        if let loc = locationManager.location {
            let coord = loc.coordinate
            let heading = locationManager.heading?.trueHeading ?? 0

            Annotation("", coordinate: coord) {
                ZStack {
                    // halo bleu translucide
                    Circle()
                        .fill(Color.blue.opacity(0.25))
                        .frame(width: 40, height: 40)

                    // point bleu Apple
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle().stroke(Color.white, lineWidth: 2)
                        )

                    // direction (petit cône)
                    Triangle()
                        .fill(Color.blue)
                        .frame(width: 10, height: 14)
                        .offset(y: -18)
                        .rotationEffect(Angle.degrees(heading))
                }
            }
        }
    }
    // MARK: - Terrain polygons
    @MapContentBuilder
    private var terrainLayer: some MapContent {
        ForEach(Array(terrainPolygons.enumerated()), id: \.offset) { pair in
            let coords = pair.element

            if selectedMapBaseStyle == .photo {
                // Sur photo aérienne : polygone totalement transparent, seuls les contours apparaissent
                MapPolygon(coordinates: coords)
                    .foregroundStyle(Color.clear)
                    .stroke(
                        (colorScheme == .dark ? Color.white : Color.black)
                            .opacity(0.9),
                        lineWidth: 2
                    )
            } else {
                // Mode "plan noir & blanc" :
                // - en clair : blanc légèrement transparent pour laisser lire le fond
                // - en sombre : noir quasi plein pour garder le contraste
                let fillColor: Color = (colorScheme == .dark)
                    ? .black
                    : Color.white.opacity(0.8)

                let strokeColor: Color = (colorScheme == .dark)
                    ? Color.white.opacity(0.8)
                    : Color.black.opacity(0.7)

                MapPolygon(coordinates: coords)
                    .foregroundStyle(fillColor)
                    .stroke(strokeColor, lineWidth: 2)
            }
        }
    }

    // MARK: - Îlots polygons + labels
    @MapContentBuilder
    private var ilotLayer: some MapContent {
        ForEach(Array(ilotPolygons.enumerated()), id: \.offset) { pair in
            let idx = pair.offset
            let coords = pair.element
            let fillColor = ilotFillColors[idx % ilotFillColors.count]
            let outlineBase = (colorScheme == .dark) ? Color.white : Color.black
            let outlineColor = outlineBase.opacity(0.18)
            let name = "A\(idx + 1)"
            let showLabel = isWisdomTreeZoomedIn(currentRegion)

            MapPolygon(coordinates: coords)
                .foregroundStyle(fillColor.opacity(0.22))
                .stroke(outlineColor, lineWidth: 0.7)

            if showLabel, let centroid = polygonCentroid(of: coords) {
                Annotation("", coordinate: centroid) {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(outlineBase.opacity(0.8))
                }
            }
        }
    }

    // MARK: - Pins des plantes
    @MapContentBuilder
    private var pinsLayer: some MapContent {
        let visiblePins = pins.filter { pin in
            selectedStrataFilter.matches(pin.strata)
        }

        // Ordre de rendu : strates basses d'abord, strates hautes ensuite (au-dessus)
        let sortedPins = visiblePins.sorted { a, b in
            strataRank(a.strata) < strataRank(b.strata)
        }

        ForEach(sortedPins) { item in
            let isSelected = (selectedPin?.id == item.id)
            let canopyColor = canopyCrownColor(strata: item.strata, isSelected: isSelected)
            let strataOpacity = strataVisibilityOpacity(for: item.strata, region: currentRegion)

            // Rayon PHYSIQUE (en mètres) basé sur la strate, converti en points selon le zoom
            let radiusMeters = canopyRadiusMeters(for: item.strata) * 0.25
            let radiusPoints = canopyRadiusPoints(
                radiusMeters: radiusMeters,
                region: currentRegion,
                viewportWidth: mapViewportSize.width
            )

            let labelText = canopyAbbrev(for: item.commonName)

            Annotation("", coordinate: item.coordinate) {
                let plant = store.plants.first(where: { $0.id == item.id })

                ZStack {
                    // Couronne : ne doit pas capturer les gestes (zoom/pan) de la carte
                    Group {
                        // Couronne "arbre vu de dessus" (couleur SwiftUI → évite le bug MapCircle noir)
                        Circle()
                            .fill(canopyColor.opacity((isSelected ? 0.50 : 0.40) * strataOpacity))
                            .blur(radius: 0.15)

                        // Contour net
                        Circle()
                            .stroke(
                                canopyColor.opacity((isSelected ? 0.86 : 0.70) * strataOpacity),
                                lineWidth: isSelected ? 2.4 : 1.8
                            )

                        // Second contour doux (effet feuillage)
                        Circle()
                            .stroke(
                                canopyColor.opacity((isSelected ? 0.46 : 0.38) * strataOpacity),
                                lineWidth: isSelected ? 7.0 : 5.0
                            )
                            .blur(radius: 0.30)

                        // Label central (abréviation espèce) écrit directement sur la couronne
                        Text(labelText)
                            .font(.system(size: max(8, radiusPoints * 0.42), weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.35)
                            .allowsTightening(true)
                            .frame(
                                width: max(6, radiusPoints * 1.55),
                                height: max(6, radiusPoints * 1.55)
                            )
                            .clipShape(Circle())
                            .foregroundStyle(
                                Color.primary.opacity((selectedMapBaseStyle == .photo ? 0.92 : 0.85) * strataOpacity)
                            )
                            // Légère ombre pour rester lisible sur la photo sans "capsule"
                            .shadow(
                                color: Color.black.opacity(selectedMapBaseStyle == .photo ? 0.30 : 0.12),
                                radius: 1.1,
                                x: 0,
                                y: 0.6
                            )
                    }
                    .allowsHitTesting(false)

                    // Cartel (au-dessus de la couronne, uniquement si sélection)
                    if isSelected, let plant = plant {
                        HStack(spacing: 8) {

                            // Image miniature
                            if let url = resolvedPlantImageURL(local: plant.imageLocal, remote: plant.speciesImageURL) {
                                CachedAsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    Color.gray.opacity(0.15)
                                }
                                .frame(width: 38, height: 38)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }

                            // Texte
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plant.commonName)
                                    .font(.caption)
                                    .foregroundStyle(Color.primary)

                                if let v = plant.varietyName, !v.isEmpty {
                                    Text(v)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.cardBackground)
                                .shadow(radius: 3)
                        )
                        .offset(y: -(radiusPoints + 22))
                        // (tap handler removed)
                    }
                }
                .frame(width: max(8, radiusPoints * 2), height: max(8, radiusPoints * 2))
                // Les annotations ne doivent jamais capturer les gestes (zoom/pan)
                .allowsHitTesting(false)
            }
        }
    }
    // MARK: - Sélection par tap sur la carte

    private func selectNearestPin(to coordinate: CLLocationCoordinate2D) {
        guard !pins.isEmpty else {
            selectedPin = nil
            return
        }

        // Seuil de sélection en mètres : proportionnel à la largeur courante de la vue
        // (plus on est zoomé-in, plus le seuil diminue).
        let thresholdMeters: CLLocationDistance = {
            guard let region = currentRegion, mapViewportSize.width > 0 else { return 8 }
            let lat = region.center.latitude
            let metersPerDegreeLon = 111_320.0 * cos(lat * .pi / 180.0)
            let metersAcross = Double(region.span.longitudeDelta) * metersPerDegreeLon
            // 2% de la largeur visible (borné)
            return min(14, max(2.5, metersAcross * 0.02))
        }()

        let tapLoc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        var best: (pin: PlantPin, d: CLLocationDistance)? = nil
        for p in pins {
            let d = tapLoc.distance(from: CLLocation(latitude: p.coordinate.latitude, longitude: p.coordinate.longitude))
            if best == nil || d < best!.d { best = (p, d) }
        }

        guard let bestHit = best, bestHit.d <= thresholdMeters else {
            selectedPin = nil
            return
        }

        // 1er tap: sélection. 2e tap sur le même: ouvre la fiche.
        if selectedPin?.id == bestHit.pin.id {
            sheetPin = bestHit.pin
        } else {
            selectedPin = bestHit.pin
        }
    }

    // MARK: - Chargement des pins depuis la base

    // MARK: - Points d'intérêt fixes (POI)
    @MapContentBuilder
    private var poiLayer: some MapContent {

        // Arbre de la sagesse
        let wisdomTreeCoordinate = CLLocationCoordinate2D(
            latitude: 45.348828976987036,
            longitude: 4.0740432545957255
        )
        let showWisdomLabel = showWisdomTreeLabel || isWisdomTreeZoomedIn(currentRegion)
        Annotation("", coordinate: wisdomTreeCoordinate) {
            MapPOI(
                systemName: "tree.fill",
                color: .green,
                label: showWisdomLabel ? "Arbre de la sagesse" : nil
            )
            .onTapGesture { showWisdomTreeLabel.toggle() }
        }

        // Tipi
        let tipiCoordinate = CLLocationCoordinate2D(
            latitude: 45.34888497165765,
            longitude: 4.074250606565962
        )
        Annotation("", coordinate: tipiCoordinate) {
            MapPOI(
                systemName: "tent.fill",
                color: .orange,
                label: isWisdomTreeZoomedIn(currentRegion) ? "Tipi" : nil
            )
        }

        // Coin repas
        let picnicCoordinate = CLLocationCoordinate2D(
            latitude: 45.34879496167833,
            longitude: 4.074389410876265
        )
        Annotation("", coordinate: picnicCoordinate) {
            VStack(spacing: 0) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.red)
                if isWisdomTreeZoomedIn(currentRegion) {
                    Text("Coin repas")
                        .font(.caption2)
                        .foregroundStyle(Color.primary)
                }
            }
        }

        // Toilettes
        let toiletsCoordinate = CLLocationCoordinate2D(
            latitude: 45.348719895258974,
            longitude: 4.0745217596678405
        )
        Annotation("", coordinate: toiletsCoordinate) {
            MapPOI(
                systemName: "figure.wave",
                color: .blue,
                label: isWisdomTreeZoomedIn(currentRegion) ? "Toilettes" : nil
            )
        }

        // Parking
        let parkingCoordinate = CLLocationCoordinate2D(
            latitude: 45.348767280512625,
            longitude: 4.0731358660542725
        )
        Annotation("", coordinate: parkingCoordinate) {
            MapPOI(
                systemName: "car.fill",
                color: .gray,
                label: isWisdomTreeZoomedIn(currentRegion) ? "Parking" : nil
            )
        }

        // Caravane
        let caravanCoordinate = CLLocationCoordinate2D(
            latitude: 45.348839241168726,
            longitude: 4.073245520938274
        )
        Annotation("", coordinate: caravanCoordinate) {
            MapPOI(
                systemName: "shippingbox.fill",
                color: .brown,
                label: isWisdomTreeZoomedIn(currentRegion) ? "Caravane" : nil
            )
        }

        // Cabane
        let cabaneCoordinate = CLLocationCoordinate2D(
            latitude: 45.34884689655228,
            longitude: 4.073327580553453
        )
        Annotation("", coordinate: cabaneCoordinate) {
            MapPOI(
                systemName: "house.fill",
                color: .green,
                label: isWisdomTreeZoomedIn(currentRegion) ? "Cabane" : nil
            )
        }
    }


    // MARK: - Chargement des pins depuis la base

    private func reloadPins() {
        let plants = store.plants

        let geoPlants = plants.compactMap { plant -> PlantPin? in
            guard let lat = plant.lat,
                  let lon = plant.lon else {
                return nil
            }
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)

            // On récupère la strate depuis le modèle (champ `strata` de la plante)
            let strata = plant.strata?.lowercased()

            // Priorité métier:
            // 1) envergure observée de l'individu
            // 2) envergure espèce
            // 3) fallback hauteur (individu puis espèce)
            let rawSpread = plant.spreadCurrent ?? plant.speciesSpreadMax ?? plant.speciesSpreadMin
            let spreadMeters: Double? = {
                guard let s = rawSpread, s > 0 else { return nil }
                // Certaines saisies historiques sont en cm.
                return s > 40 ? (s / 100.0) : s
            }()
            let speciesBaseHeight = plant.speciesHeightMax ?? plant.speciesHeightMin
            let observedIndividualHeight = plant.heightCurrent
            let rawHeight = observedIndividualHeight ?? speciesBaseHeight
            let heightMeters: Double? = {
                guard let h = rawHeight, h > 0 else { return nil }
                return h > 20 ? (h / 100.0) : h
            }()
            let canopyDiameter: Double? = {
                if let spreadMeters {
                    return max(canopyMinMeters, min(canopyMaxMeters, spreadMeters))
                }
                if let h = heightMeters {
                    return max(canopyMinMeters, min(canopyMaxMeters, h * 0.95))
                }
                return nil
            }()

            return PlantPin(
                id: plant.id,
                commonName: plant.commonName,
                varietyName: plant.varietyName,
                zone: plant.zone,
                strata: strata,
                canopyDiameterMeters: canopyDiameter,
                coordinate: coord
            )
        }

        pins = geoPlants

        // Si on a des plantes et que la caméra n’est pas encore réglée,
        // on centre sur elles.
        if !didSetInitialCamera, !geoPlants.isEmpty {
            let coords = geoPlants.map { $0.coordinate }
            let region = regionForCoordinates(coords)
            cameraPosition = .region(region)
            didSetInitialCamera = true
        }
    }

    // MARK: - Chargement du GeoJSON terrain.geojson

    private func loadTerrainOverlay() {
        guard let url = Bundle.main.url(forResource: "terrain", withExtension: "geojson") else {
            AppLog.warning("terrain.geojson introuvable dans le bundle", category: .map)
            return
        }

        do {
            let data = try Data(contentsOf: url)
            AppLog.debug("terrain.geojson charge (\(data.count) octets)", category: .map)

            let decoder = MKGeoJSONDecoder()
            let objects = try decoder.decode(data)
            AppLog.debug("MKGeoJSONDecoder terrain: \(objects.count) objets", category: .map)

            // On construit TOUT dans polys, puis on assigne terrainPolygons UNE FOIS
            var polys: [[CLLocationCoordinate2D]] = []

            for object in objects {
                guard let feature = object as? MKGeoJSONFeature else { continue }

                for geom in feature.geometry {

                    // ---- MultiPolygon ----
                    if let multi = geom as? MKMultiPolygon {
                        AppLog.debug("terrain MultiPolygon: \(multi.polygons.count) polygones", category: .map)
                        for poly in multi.polygons {
                            let coords = poly.coordinatesArray
                            AppLog.debug("terrain polygon: \(coords.count) points", category: .map)
                            if !coords.isEmpty {
                                polys.append(coords)
                            }
                        }
                        continue
                    }

                    // ---- Polygon ----
                    if let poly = geom as? MKPolygon {
                        let coords = poly.coordinatesArray
                        AppLog.debug("terrain Polygon: \(coords.count) points", category: .map)
                        if !coords.isEmpty {
                            polys.append(coords)
                        }
                        continue
                    }

                    // ---- Polyline ----
                    if let line = geom as? MKPolyline {
                        let coords = line.coordinatesArray
                        AppLog.debug("terrain Polyline: \(coords.count) points", category: .map)
                        if !coords.isEmpty {
                            polys.append(coords)
                        }
                        continue
                    }
                }
            }

            AppLog.info("terrain polygones/segments extraits: \(polys.count)", category: .map)
            if let first = polys.first, let firstCoord = first.first {
                AppLog.debug("terrain premier point: lat=\(firstCoord.latitude), lon=\(firstCoord.longitude)", category: .map)
            }

            // On assigne une seule fois au state SwiftUI
            terrainPolygons = polys

            // Réglage de la caméra si elle ne l’a pas encore été
            if !didSetInitialCamera {
                if !pins.isEmpty {
                    // On a déjà des plantes : priorité à leur nuage de points
                    let coords = pins.map { $0.coordinate }
                    cameraPosition = .region(regionForCoordinates(coords))
                    didSetInitialCamera = true
                } else if let firstPoly = polys.first {
                    // Sinon, on centre sur le premier polygone de terrain
                    let region = regionForCoordinates(firstPoly)
                    cameraPosition = .region(region)
                    didSetInitialCamera = true
                }
            }

        } catch {
            AppLog.warning("Erreur de decodage terrain.geojson: \(error)", category: .map)
        }
    }

    // MARK: - Types internes

    /// Ordre de rendu des strates : plus le rang est grand, plus c'est AU-DESSUS.
    /// (Dessiné plus tard = au-dessus.)
    private func strataRank(_ strata: String?) -> Int {
        let s = (strata ?? "").lowercased()
        switch s {
        case "couvre-sol": return 1
        case "herbacée":   return 2
        case "liane":      return 3
        case "arbuste":    return 4
        case "sous-étage": return 5
        case "canopée":    return 6
        default:           return 0
        }
    }

    /// Couleur pastel (style aquarelle) dépendant de la strate.
    /// On évite l'accent color pour ne pas subir les rendus MapKit.
    private func canopyCrownColor(strata: String?, isSelected: Bool) -> Color {
        let rgb = canopyBaseRGB(for: strata)

        // Légère correction selon thème + sélection
        let adjusted: (r: Double, g: Double, b: Double)
        if colorScheme == .dark {
            // En sombre, on éclaircit légèrement pour éviter un rendu "boueux".
            adjusted = lighten(rgb, amount: isSelected ? 0.14 : 0.08)
        } else {
            adjusted = rgb
        }

        return Color(red: adjusted.r, green: adjusted.g, blue: adjusted.b)
    }

    /// Palette pastel par strate (non saturée) en RGB.
    private func canopyBaseRGB(for strata: String?) -> (r: Double, g: Double, b: Double) {
        let s = (strata ?? "").lowercased()
        switch s {
        case "canopée":
            // vert
            return (0.36, 0.64, 0.40)
        case "sous-étage":
            // bleu-vert
            return (0.34, 0.62, 0.58)
        case "arbuste":
            // violet
            return (0.60, 0.50, 0.72)
        case "herbacée":
            // jaune
            return (0.80, 0.74, 0.42)
        case "couvre-sol":
            // pêche
            return (0.84, 0.62, 0.52)
        case "liane":
            // bleu
            return (0.46, 0.58, 0.80)
        default:
            // neutre
            return (0.55, 0.60, 0.62)
        }
    }

    /// Éclaircit une couleur RGB en mélangeant avec du blanc (amount ∈ [0,1]).
    private func lighten(
        _ rgb: (r: Double, g: Double, b: Double),
        amount: Double
    ) -> (r: Double, g: Double, b: Double) {
        let a = min(max(amount, 0.0), 1.0)
        return (
            r: rgb.r + (1.0 - rgb.r) * a,
            g: rgb.g + (1.0 - rgb.g) * a,
            b: rgb.b + (1.0 - rgb.b) * a
        )
    }

    /// Abréviation courte au centre de la couronne (ex: Noy, Pom, Poi, Châ...).
    private func canopyAbbrev(for commonName: String) -> String {
        SpeciesAbbreviation.forCommonName(commonName)
    }

    /// Opacité "intelligente" en fonction du zoom :
    /// en zoomant IN, on fait disparaître progressivement les strates supérieures (canopée, sous-étage)
    /// afin de privilégier arbustes/herbacées/couvre-sol.
    private func strataVisibilityOpacity(for strata: String?, region: MKCoordinateRegion?) -> Double {
        guard let region = region else { return 1.0 }

        let s = (strata ?? "").lowercased()

        // Seuils de zoom (à ajuster à ton feeling)
        // - au-delà de startDelta : pas de fade (opacité ~1)
        // - en-dessous de endDelta : opacité minimale atteinte
        // Fade plus tard et sur une plage de zoom plus profonde
        let startDelta: Double = 0.00090
        let endDelta: Double = 0.00020

        // x = 1 quand on est peu zoomé (delta grand), x = 0 quand on est très zoomé (delta petit)
        let d = Double(region.span.latitudeDelta)
        let x = clamp01((d - endDelta) / (startDelta - endDelta))
        let t = smoothstep(x)

        // Opacité minimale par strate
        let minOpacity: Double
        switch s {
        case "canopée":
            minOpacity = 0.10
        case "sous-étage":
            minOpacity = 0.22
        // L'arbuste peut rester bien visible, mais on le baisse un poil si besoin
        case "arbuste":
            minOpacity = 0.55
        default:
            // herbacée / couvre-sol / liane / inconnue : toujours visibles
            return 1.0
        }

        // Interpolation douce : minOpacity (zoom in) → 1 (zoom out)
        return minOpacity + (1.0 - minOpacity) * t
    }

    private func clamp01(_ v: Double) -> Double {
        min(max(v, 0.0), 1.0)
    }

    /// Smoothstep classique (C1) : 3x^2 - 2x^3
    private func smoothstep(_ x: Double) -> Double {
        x * x * (3.0 - 2.0 * x)
    }

    /// Convertit un rayon en mètres en rayon en points (SwiftUI) selon le zoom de la carte.
    /// Ainsi, la couronne garde une taille "physique" cohérente avec le fond de carte (ratio constant au zoom).
    private func canopyRadiusPoints(
        radiusMeters: CLLocationDistance,
        region: MKCoordinateRegion?,
        viewportWidth: CGFloat
    ) -> CGFloat {
        guard let region = region, viewportWidth > 1 else {
            return 14 // fallback tant que la caméra n'a pas fourni de région
        }

        // Conversion approx : degrés de longitude -> mètres, dépend de la latitude
        let lat = region.center.latitude
        let metersPerDegreeLon = 111_320.0 * cos(lat * .pi / 180.0)
        let metersAcross = Double(region.span.longitudeDelta) * metersPerDegreeLon
        let metersPerPoint = metersAcross / Double(viewportWidth)

        // Si MapKit renvoie un span quasi nul pendant une frame, on évite un ratio explosif.
        guard metersPerPoint.isFinite, metersPerPoint > 0.000001 else { return 12 }

        let r = CGFloat(radiusMeters / metersPerPoint)

        // On garde le ratio "physique" avec la carte, mais on évite les valeurs absurdes dues aux frames transitoires.
        return min(max(r, 4), 5000)
    }

    /// Rayon d'envergure (en mètres) en fonction de la strate.
    /// Valeurs volontairement simples et "visuelles" ; ajuste librement selon ton terrain.
    private func canopyRadiusMeters(for strata: String?) -> CLLocationDistance {
        let s = (strata ?? "").lowercased()
        switch s {
        case "canopée":
            return 6.0
        case "sous-étage":
            return 4.0
        case "arbuste":
            return 2.5
        case "herbacée":
            return 0.9
        case "couvre-sol":
            return 0.5
        case "liane":
            return 1.5
        default:
            return 2.0
        }
    }

    struct PlantPin: Identifiable {
        let id: Int
        let commonName: String
        let varietyName: String?
        let zone: String?
        let strata: String?            // valeur brute de la base (champ `strata`, en minuscule idéalement)
        let canopyDiameterMeters: Double?
        let coordinate: CLLocationCoordinate2D
    }


    struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            // Pointe vers le haut, base en bas
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }

    struct MapPlaceholderView: View {
        var body: some View {
            ZStack {
                LinearGradient(
                    colors: [
                        Color.gray.opacity(0.20),
                        Color.gray.opacity(0.35)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(spacing: 8) {
                    Image(systemName: "map")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))

                    Text("Aucun individu géolocalisé")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
        }
    }
}

// MARK: - Helpers géométriques

/// Calcule un `MKCoordinateRegion` englobant une liste de coordonnées.
private func regionForCoordinates(_ coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
    guard let first = coords.first else {
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 45.0, longitude: 4.0),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    }

    var minLat = first.latitude
    var maxLat = first.latitude
    var minLon = first.longitude
    var maxLon = first.longitude

    for c in coords.dropFirst() {
        minLat = min(minLat, c.latitude)
        maxLat = max(maxLat, c.latitude)
        minLon = min(minLon, c.longitude)
        maxLon = max(maxLon, c.longitude)
    }

    let center = CLLocationCoordinate2D(
        latitude: (minLat + maxLat) / 2.0,
        longitude: (minLon + maxLon) / 2.0
    )

    // Zoom un peu plus serré, en particulier pour un seul point
       let baseLatDelta = (maxLat - minLat) * 1.3
       let baseLonDelta = (maxLon - minLon) * 1.3
       let latDelta = max(baseLatDelta, 0.0005)
       let lonDelta = max(baseLonDelta, 0.0005)

    return MKCoordinateRegion(
        center: center,
        span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
    )
}

/// Centroïde approximatif d'un polygone défini par une liste de coordonnées.
/// Ici on utilise simplement la moyenne des latitudes et longitudes, ce qui est suffisant
/// pour un polygone relativement petit comme un îlot de jardin.
private func polygonCentroid(of coords: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
    guard !coords.isEmpty else { return nil }

    var sumLat: CLLocationDegrees = 0
    var sumLon: CLLocationDegrees = 0

    for c in coords {
        sumLat += c.latitude
        sumLon += c.longitude
    }

    let count = Double(coords.count)
    return CLLocationCoordinate2D(latitude: sumLat / count,
                                  longitude: sumLon / count)
}

/// Indique si on est suffisamment zoomé pour afficher automatiquement
/// le label de l'arbre de la sagesse.
private func isWisdomTreeZoomedIn(_ region: MKCoordinateRegion?) -> Bool {
    guard let region = region else { return false }
    // Plus la latitudeDelta est petite, plus on est zoomé.
    // Seuil à ajuster en fonction de ton ressenti.
    return region.span.latitudeDelta < 0.0008
}

// MARK: - Extensions pour extraire les coordonnées des MKShape

private extension MKPolygon {
    var coordinatesArray: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid,
                                             count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}

private extension MKPolyline {
    var coordinatesArray: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid,
                                             count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}

extension MapStyle {
    static var mutedStandard: MapStyle {
        .standard(elevation: .flat, emphasis: .muted)
    }
}

struct StrataFilterBar: View {
    @Binding var selected: GardenMapView.StrataFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GardenMapView.StrataFilter.allCases) { filter in
                    let isSelected = (filter == selected)
                    Button {
                        selected = filter
                    } label: {
                        Text(filter.label)
                            .font(.caption2)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(isSelected ? Color.accentPrimary : Color.cardBackground)
                            )
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .overlay(
                                Capsule()
                                    .stroke(
                                        Color.accentPrimary.opacity(isSelected ? 0.0 : 0.4),
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
#if os(macOS)
private struct GardenMapUIKitView: NSViewRepresentable {
    let pins: [GardenMapView.PlantPin]
    let selectedStrataFilter: GardenMapView.StrataFilter
    let terrainPolygons: [[CLLocationCoordinate2D]]
    let ilotPolygons: [[CLLocationCoordinate2D]]
    let mapBaseStyle: GardenMapView.MapBaseStyle
    let hillshadeEnabled: Bool
    let hillshadeOpacity: Double
    let colorScheme: ColorScheme
    let editingDraft: GardenMapView.PlantEditDraft?
    let onPinTap: (GardenMapView.PlantPin) -> Void
    let onPinLongPress: (GardenMapView.PlantPin) -> Void
    let onPinDrag: (GardenMapView.PlantPin, CLLocationCoordinate2D) -> Void
    let onRegionChange: (MKCoordinateRegion) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPinTap: onPinTap, onPinLongPress: onPinLongPress, onRegionChange: onRegionChange)
    }

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsCompass = false
        mapView.showsUserLocation = true
        mapView.pointOfInterestFilter = .excludingAll
        mapView.isPitchEnabled = false
        context.coordinator.mapView = mapView
        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        context.coordinator.hillshadeOpacity = hillshadeOpacity
        applyBaseStyle(to: mapView)
        syncOverlays(on: mapView)
        syncPins(on: mapView, context: context)

        if !context.coordinator.didSetInitialRegion {
            let defaultCenter = CLLocationCoordinate2D(latitude: 45.348828976987036, longitude: 4.0740432545957255)
            let coords = pins.map(\.coordinate)
            let region = coords.isEmpty
                ? MKCoordinateRegion(center: defaultCenter, span: MKCoordinateSpan(latitudeDelta: 0.0007, longitudeDelta: 0.0007))
                : regionForCoordinates(coords)
            mapView.setRegion(region, animated: false)
            context.coordinator.didSetInitialRegion = true
        }
    }

    private func applyBaseStyle(to mapView: MKMapView) {
        switch mapBaseStyle {
        case .photo: mapView.mapType = .hybrid
        case .planNB, .ignPlan: mapView.mapType = .mutedStandard
        }
    }

    private func syncPins(on mapView: MKMapView, context: Context) {
        let filtered = pins.filter { selectedStrataFilter.matches($0.strata) }
        let effectivePins: [GardenMapView.PlantPin] = filtered.map { pin in
            guard let draft = editingDraft, draft.id == pin.id else { return pin }
            return GardenMapView.PlantPin(
                id: pin.id,
                commonName: pin.commonName,
                varietyName: pin.varietyName,
                zone: pin.zone,
                strata: pin.strata,
                canopyDiameterMeters: draft.canopyDiameterMeters,
                coordinate: draft.coordinate
            )
        }
        let signature = effectivePins
            .map { "\($0.id)-\($0.coordinate.latitude)-\($0.coordinate.longitude)-\($0.strata ?? "")" }
            .joined(separator: "|")
        if signature == context.coordinator.lastPinsSignature { return }
        context.coordinator.lastPinsSignature = signature

        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
        let annotations = effectivePins.map { pin -> MacPlantPointAnnotation in
            let a = MacPlantPointAnnotation(pin: pin)
            a.coordinate = pin.coordinate
            a.title = pin.commonName
            a.subtitle = pin.varietyName
            return a
        }
        mapView.addAnnotations(annotations)
    }

    private func syncOverlays(on mapView: MKMapView) {
        let signature = "\(terrainPolygons.count)-\(ilotPolygons.count)-\(hillshadeEnabled)-\(mapBaseStyle.signatureKey)"
        if let coordinator = mapView.delegate as? Coordinator,
           coordinator.lastOverlaysSignature == signature {
            return
        }
        (mapView.delegate as? Coordinator)?.lastOverlaysSignature = signature

        mapView.removeOverlays(mapView.overlays)

        let terrainOverlays: [MKPolygon] = terrainPolygons.compactMap { coords in
            guard let normalized = normalizePolygonCoordinates(coords) else { return nil }
            let p = MKPolygon(coordinates: normalized, count: normalized.count)
            p.title = "terrain"
            return p
        }
        let ilotOverlays: [MKPolygon] = ilotPolygons.enumerated().compactMap { idx, coords in
            guard let normalized = normalizePolygonCoordinates(coords) else { return nil }
            let p = MKPolygon(coordinates: normalized, count: normalized.count)
            p.title = "ilot-\(idx)"
            return p
        }

        if let baseOverlay = makeBaseTileOverlay(for: mapBaseStyle) {
            mapView.addOverlay(baseOverlay, level: .aboveRoads)
        }
        mapView.addOverlays(terrainOverlays)
        mapView.addOverlays(ilotOverlays)

        if hillshadeEnabled {
            // macOS: relief via WMTS global shadow layer (MapKit pur, sans pipeline iOS-specific).
            let relief = MacReliefTileOverlay(urlTemplate:
                "https://data.geopf.fr/wmts?SERVICE=WMTS&VERSION=1.0.0&REQUEST=GetTile&LAYER=IGNF_ELEVATION.ELEVATIONGRIDCOVERAGE.SHADOW&STYLE=normal&TILEMATRIXSET=PM&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/png"
            )
            relief.canReplaceMapContent = false
            relief.minimumZ = 0
            relief.maximumZ = 22
            mapView.addOverlay(relief, level: .aboveRoads)
        }
    }

    private func makeBaseTileOverlay(for style: GardenMapView.MapBaseStyle) -> MKTileOverlay? {
        switch style {
        case .photo, .planNB:
            return nil
        case .ignPlan:
            let overlay = MacBaseTileOverlay(urlTemplate:
                "https://data.geopf.fr/wmts?SERVICE=WMTS&VERSION=1.0.0&REQUEST=GetTile&LAYER=GEOGRAPHICALGRIDSYSTEMS.MAPS&STYLE=normal&TILEMATRIXSET=PM&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/png"
            )
            overlay.minimumZ = 0
            overlay.maximumZ = 22
            overlay.canReplaceMapContent = true
            return overlay
        }
    }

    private func normalizePolygonCoordinates(_ coords: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D]? {
        let valid = coords.filter { CLLocationCoordinate2DIsValid($0) }
        guard valid.count >= 3 else { return nil }
        var ring = valid
        if let first = ring.first, let last = ring.last {
            let same = abs(first.latitude - last.latitude) < 0.0000001 && abs(first.longitude - last.longitude) < 0.0000001
            if !same { ring.append(first) }
        }
        return ring.count >= 4 ? ring : nil
    }

    private func regionForCoordinates(_ coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard let first = coordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 45.348828976987036, longitude: 4.0740432545957255),
                span: MKCoordinateSpan(latitudeDelta: 0.0009, longitudeDelta: 0.0009)
            )
        }
        var minLat = first.latitude, maxLat = first.latitude, minLon = first.longitude, maxLon = first.longitude
        for c in coordinates {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) * 0.5, longitude: (minLon + maxLon) * 0.5)
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.8, 0.00025), longitudeDelta: max((maxLon - minLon) * 1.8, 0.00025))
        return MKCoordinateRegion(center: center, span: span)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        weak var mapView: MKMapView?
        let onPinTap: (GardenMapView.PlantPin) -> Void
        let onPinLongPress: (GardenMapView.PlantPin) -> Void
        let onRegionChange: (MKCoordinateRegion) -> Void
        var didSetInitialRegion = false
        var hillshadeOpacity: Double = 0.35
        var lastPinsSignature = ""
        var lastOverlaysSignature = ""

        init(onPinTap: @escaping (GardenMapView.PlantPin) -> Void,
             onPinLongPress: @escaping (GardenMapView.PlantPin) -> Void,
             onRegionChange: @escaping (MKCoordinateRegion) -> Void) {
            self.onPinTap = onPinTap
            self.onPinLongPress = onPinLongPress
            self.onRegionChange = onRegionChange
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation as? MacPlantPointAnnotation else { return }
            onPinTap(annotation.pin)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            onRegionChange(mapView.region)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let base = overlay as? MacBaseTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: base)
                renderer.alpha = 1.0
                return renderer
            }
            if let tileOverlay = overlay as? MacReliefTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: tileOverlay)
                renderer.alpha = CGFloat(hillshadeOpacity)
                return renderer
            }
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                if polygon.title == "terrain" {
                    renderer.fillColor = NSColor.clear
                    renderer.strokeColor = NSColor.labelColor.withAlphaComponent(0.85)
                    renderer.lineWidth = 2
                } else if let title = polygon.title, title.hasPrefix("ilot-") {
                    renderer.fillColor = NSColor.systemTeal.withAlphaComponent(0.18)
                    renderer.strokeColor = NSColor.labelColor.withAlphaComponent(0.18)
                    renderer.lineWidth = 0.7
                }
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            guard let plantAnnotation = annotation as? MacPlantPointAnnotation else { return nil }
            let identifier = "PlantMacMarker"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.canShowCallout = false
            view.displayPriority = .required
            view.markerTintColor = NSColor.systemGreen
            view.glyphText = String(SpeciesAbbreviation.forCommonName(plantAnnotation.pin.commonName).prefix(3))
            return view
        }
    }
}

private final class MacBaseTileOverlay: MKTileOverlay {}
private final class MacReliefTileOverlay: MKTileOverlay {}

private final class MacPlantPointAnnotation: MKPointAnnotation {
    let pin: GardenMapView.PlantPin
    init(pin: GardenMapView.PlantPin) {
        self.pin = pin
        super.init()
    }
}

private enum CanopyMarkerStyle {
    static func fallbackDiameterMeters(for strata: String?) -> CLLocationDistance {
        switch (strata ?? "").lowercased() {
        case "canopée": return 12.0
        case "sous-étage": return 8.0
        case "arbuste": return 4.0
        case "herbacée": return 1.8
        case "couvre-sol": return 1.0
        case "liane": return 2.5
        default: return 3.0
        }
    }
}

private enum SpeciesAbbreviation {
    static func forCommonName(_ commonName: String) -> String {
        let n = commonName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = n.lowercased()
        if lower.isEmpty { return "" }
        let firstWord = lower.split(separator: " ").first.map(String.init) ?? lower
        let prefix3 = String(firstWord.prefix(3))
        guard !prefix3.isEmpty else { return "" }
        return prefix3.prefix(1).uppercased() + prefix3.dropFirst()
    }
}
#endif
#if os(iOS)
private struct GardenMapUIKitView: UIViewRepresentable {
    let pins: [GardenMapView.PlantPin]
    let selectedStrataFilter: GardenMapView.StrataFilter
    let terrainPolygons: [[CLLocationCoordinate2D]]
    let ilotPolygons: [[CLLocationCoordinate2D]]
    let mapBaseStyle: GardenMapView.MapBaseStyle
    let hillshadeEnabled: Bool
    let hillshadeOpacity: Double
    let colorScheme: ColorScheme
    let editingDraft: GardenMapView.PlantEditDraft?
    let onPinTap: (GardenMapView.PlantPin) -> Void
    let onPinLongPress: (GardenMapView.PlantPin) -> Void
    let onPinDrag: (GardenMapView.PlantPin, CLLocationCoordinate2D) -> Void
    let onRegionChange: (MKCoordinateRegion) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onPinTap: onPinTap,
            onPinLongPress: onPinLongPress,
            onPinDrag: onPinDrag,
            onRegionChange: onRegionChange
        )
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsCompass = false
        mapView.showsUserLocation = true
        mapView.pointOfInterestFilter = .excludingAll
        mapView.isPitchEnabled = false
        if #available(iOS 13.0, *) {
            // Zoom profond (échelle terrain/plante), utile pour des déplacements fins.
            mapView.cameraZoomRange = MKMapView.CameraZoomRange(
                minCenterCoordinateDistance: 1.5,
                maxCenterCoordinateDistance: 30_000_000
            )
        }
        context.coordinator.mapView = mapView
        context.coordinator.attachMapLongPressRecognizer(to: mapView)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let previousOpacity = context.coordinator.hillshadeOpacity
        context.coordinator.hillshadeOpacity = hillshadeOpacity
        context.coordinator.hillshadeEnabled = hillshadeEnabled
        applyBaseStyle(to: mapView)
        syncOverlays(on: mapView)
        syncPins(on: mapView, context: context)

        if abs(previousOpacity - hillshadeOpacity) > 0.001 {
            if let overlay = mapView.overlays.first(where: { $0 is CompositeReliefTileOverlay }),
               let renderer = mapView.renderer(for: overlay) as? MKTileOverlayRenderer {
                renderer.alpha = hillshadeOpacity
                renderer.setNeedsDisplay()
            }
        }

        if !context.coordinator.didSetInitialRegion {
            let defaultCenter = CLLocationCoordinate2D(
                latitude: 45.348828976987036,
                longitude: 4.0740432545957255
            )
            let coords = pins.map(\.coordinate)
            let region = coords.isEmpty
                ? MKCoordinateRegion(
                    center: defaultCenter,
                    span: MKCoordinateSpan(latitudeDelta: 0.0007, longitudeDelta: 0.0007)
                )
                : regionForCoordinates(coords)
            mapView.setRegion(region, animated: false)
            context.coordinator.didSetInitialRegion = true
        }
    }

    private func applyBaseStyle(to mapView: MKMapView) {
        switch mapBaseStyle {
        case .photo:
            mapView.mapType = .hybrid
        case .planNB:
            mapView.mapType = .mutedStandard
        case .ignPlan:
            // Le fond sera remplacé par une couche de tuiles IGN.
            mapView.mapType = .mutedStandard
        }
    }

    private func syncPins(on mapView: MKMapView, context: Context) {
        let filteredPins = pins.filter { selectedStrataFilter.matches($0.strata) }
        context.coordinator.updateEditingState(editingDraft?.id)
        let effectivePins: [GardenMapView.PlantPin] = filteredPins.map { pin in
            guard let draft = editingDraft, draft.id == pin.id else { return pin }
            return GardenMapView.PlantPin(
                id: pin.id,
                commonName: pin.commonName,
                varietyName: pin.varietyName,
                zone: pin.zone,
                strata: pin.strata,
                canopyDiameterMeters: draft.canopyDiameterMeters,
                coordinate: draft.coordinate
            )
        }
        let signature = filteredPins
            .map { "\($0.id)-\($0.coordinate.latitude)-\($0.coordinate.longitude)-\($0.strata ?? "")" }
            .joined(separator: "|")
        let editSig: String = {
            guard let draft = editingDraft else { return "no-edit" }
            return "edit-\(draft.id)-\(draft.coordinate.latitude)-\(draft.coordinate.longitude)-\(draft.canopyDiameterMeters)"
        }()
        let fullSignature = "\(signature)|\(editSig)"
        if fullSignature == context.coordinator.lastPinsSignature {
            return
        }
        context.coordinator.lastPinsSignature = fullSignature

        let existing = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(existing)

        let annotations: [PlantPointAnnotation] = effectivePins.map { pin in
            let annotation = PlantPointAnnotation(pin: pin)
            annotation.coordinate = pin.coordinate
            annotation.title = pin.commonName
            annotation.subtitle = pin.varietyName
            return annotation
        }
        mapView.addAnnotations(annotations)
        context.coordinator.refreshCanopyAnnotationSizes(on: mapView)
    }

    private func syncOverlays(on mapView: MKMapView) {
        let overlaySignature = "\(terrainPolygons.count)-\(ilotPolygons.count)-\(hillshadeEnabled)-\(mapBaseStyle.signatureKey)"
        if let existingSignature = mapView.accessibilityIdentifier,
           existingSignature == overlaySignature {
            return
        }
        mapView.accessibilityIdentifier = overlaySignature

        mapView.removeOverlays(mapView.overlays)

        let terrainOverlays: [MKPolygon] = terrainPolygons.compactMap { coords in
            guard let normalized = normalizePolygonCoordinates(coords) else { return nil }
            let polygon = MKPolygon(coordinates: normalized, count: normalized.count)
            polygon.title = "terrain"
            return polygon
        }

        let ilotOverlays: [MKPolygon] = ilotPolygons.enumerated().compactMap { idx, coords in
            guard let normalized = normalizePolygonCoordinates(coords) else { return nil }
            let polygon = MKPolygon(coordinates: normalized, count: normalized.count)
            polygon.title = "ilot-\(idx)"
            return polygon
        }

        // Fond custom IGN (remplace le fond Apple) quand demandé.
        if let baseOverlay = makeBaseTileOverlay(for: mapBaseStyle) {
            mapView.addOverlay(baseOverlay, level: .aboveRoads)
        }

        mapView.addOverlays(terrainOverlays)
        mapView.addOverlays(ilotOverlays)

        if hillshadeEnabled {
            // Relief composite: tente LiDAR HD, puis fallback global sur chaque tuile absente.
            let lidarTemplate = "https://data.geopf.fr/wmts?SERVICE=WMTS&VERSION=1.0.0&REQUEST=GetTile&LAYER=IGNF_LIDAR-HD_MNT_ELEVATION.ELEVATIONGRIDCOVERAGE.SHADOW&STYLE=normal&TILEMATRIXSET=PM&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/png"
            let fallbackTemplate = "https://data.geopf.fr/wmts?SERVICE=WMTS&VERSION=1.0.0&REQUEST=GetTile&LAYER=IGNF_ELEVATION.ELEVATIONGRIDCOVERAGE.SHADOW&STYLE=normal&TILEMATRIXSET=PM&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/png"
            let reliefOverlay = CompositeReliefTileOverlay(
                lidarTemplate: lidarTemplate,
                fallbackTemplate: fallbackTemplate
            )
            reliefOverlay.canReplaceMapContent = false
            reliefOverlay.minimumZ = 0
            // Zoom fort autorisé: les niveaux > 18 seront reconstruits
            // à partir de tuiles ancêtres (pixelisées mais continues).
            reliefOverlay.maximumZ = 22
            mapView.addOverlay(reliefOverlay, level: .aboveRoads)
        }
    }

    private func makeBaseTileOverlay(for style: GardenMapView.MapBaseStyle) -> BaseTileOverlay? {
        switch style {
        case .photo, .planNB:
            return nil
        case .ignPlan:
            let overlay = BaseTileOverlay(
                kind: .ignPlan,
                // Fond IGN sans couche parcellaire (stable en zoom fort).
                urlTemplate: "https://data.geopf.fr/wmts?SERVICE=WMTS&VERSION=1.0.0&REQUEST=GetTile&LAYER=GEOGRAPHICALGRIDSYSTEMS.MAPS&STYLE=normal&TILEMATRIXSET=PM&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/png"
            )
            overlay.minimumZ = 0
            // Profondeur max comme sur le web IGN.
            overlay.maximumZ = 22
            overlay.canReplaceMapContent = true
            return overlay
        }
    }

    private func normalizePolygonCoordinates(_ coords: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D]? {
        let valid = coords.filter { CLLocationCoordinate2DIsValid($0) }
        guard valid.count >= 3 else { return nil }

        var ring = valid
        if let first = ring.first, let last = ring.last {
            let samePoint = abs(first.latitude - last.latitude) < 0.0000001 &&
                abs(first.longitude - last.longitude) < 0.0000001
            if !samePoint {
                ring.append(first)
            }
        }
        return ring.count >= 4 ? ring : nil
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        weak var mapView: MKMapView?
        let onPinTap: (GardenMapView.PlantPin) -> Void
        let onPinLongPress: (GardenMapView.PlantPin) -> Void
        let onPinDrag: (GardenMapView.PlantPin, CLLocationCoordinate2D) -> Void
        let onRegionChange: (MKCoordinateRegion) -> Void
        var didSetInitialRegion = false
        var hillshadeOpacity: Double = 0.35
        var hillshadeEnabled: Bool = false
        var lastPinsSignature: String = ""
        var editingPinID: Int? = nil
        private var didDisableMapScrollForDrag = false
        private lazy var mapLongPressRecognizer: UILongPressGestureRecognizer = {
            let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleMapLongPress(_:)))
            gesture.minimumPressDuration = 0.45
            gesture.allowableMovement = 16
            gesture.cancelsTouchesInView = false
            gesture.delegate = self
            return gesture
        }()
        private lazy var mapEditPanRecognizer: UIPanGestureRecognizer = {
            let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleMapEditPan(_:)))
            gesture.maximumNumberOfTouches = 1
            gesture.cancelsTouchesInView = false
            gesture.delegate = self
            gesture.isEnabled = false
            return gesture
        }()
        private var activeDraggedPin: GardenMapView.PlantPin?

        init(
            onPinTap: @escaping (GardenMapView.PlantPin) -> Void,
            onPinLongPress: @escaping (GardenMapView.PlantPin) -> Void,
            onPinDrag: @escaping (GardenMapView.PlantPin, CLLocationCoordinate2D) -> Void,
            onRegionChange: @escaping (MKCoordinateRegion) -> Void
        ) {
            self.onPinTap = onPinTap
            self.onPinLongPress = onPinLongPress
            self.onPinDrag = onPinDrag
            self.onRegionChange = onRegionChange
        }

        func attachMapLongPressRecognizer(to mapView: MKMapView) {
            let alreadyAttached = mapView.gestureRecognizers?.contains(where: { $0 === mapLongPressRecognizer }) == true
            if !alreadyAttached {
                mapView.addGestureRecognizer(mapLongPressRecognizer)
            }
            let editPanAttached = mapView.gestureRecognizers?.contains(where: { $0 === mapEditPanRecognizer }) == true
            if !editPanAttached {
                mapView.addGestureRecognizer(mapEditPanRecognizer)
            }
        }

        func updateEditingState(_ editingPinID: Int?) {
            self.editingPinID = editingPinID
            activeDraggedPin = nil
            mapEditPanRecognizer.isEnabled = (editingPinID != nil)
            if let mapView {
                if editingPinID == nil {
                    if didDisableMapScrollForDrag {
                        didDisableMapScrollForDrag = false
                    }
                    mapView.isScrollEnabled = true
                } else {
                    mapView.isScrollEnabled = false
                }
            }
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation as? PlantPointAnnotation else { return }
            onPinTap(annotation.pin)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            onRegionChange(mapView.region)
            refreshCanopyAnnotationSizes(on: mapView)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            // Mise à jour continue pendant pinch/zoom pour rester cohérent avec IGN.
            refreshCanopyAnnotationSizes(on: mapView)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let base = overlay as? BaseTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: base)
                renderer.alpha = 1.0
                return renderer
            }

            if let tileOverlay = overlay as? CompositeReliefTileOverlay {
                let renderer = SoftReliefTileOverlayRenderer(tileOverlay: tileOverlay)
                renderer.reliefOpacity = hillshadeOpacity
                renderer.reliefBlendMode = .softLight
                return renderer
            }

            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                if polygon.title == "terrain" {
                    if mapView.mapType == .hybrid {
                        renderer.fillColor = UIColor.clear
                        renderer.strokeColor = UIColor.label.withAlphaComponent(0.9)
                    } else {
                        // Relief actif: pas de remplissage pour garder l'estompage visible partout.
                        let alpha = hillshadeEnabled ? 0.0 : 0.78
                        renderer.fillColor = UIColor.systemBackground.withAlphaComponent(alpha)
                        renderer.strokeColor = UIColor.label.withAlphaComponent(0.7)
                    }
                    renderer.lineWidth = 2
                } else if let title = polygon.title, title.hasPrefix("ilot-") {
                    renderer.fillColor = UIColor.systemTeal.withAlphaComponent(0.18)
                    renderer.strokeColor = UIColor.label.withAlphaComponent(0.18)
                    renderer.lineWidth = 0.7
                }
                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }
            guard let plantAnnotation = annotation as? PlantPointAnnotation else {
                return nil
            }

            let identifier = "PlantCanopyAnnotation"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? CanopyAnnotationView
                ?? CanopyAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.canShowCallout = false
            view.displayPriority = .required
            view.isEditingEnabled = (editingPinID == plantAnnotation.pin.id)
            view.onPan = { [weak self, weak mapView, weak view] gesture in
                guard
                    let self,
                    let mapView,
                    let view,
                    self.editingPinID == plantAnnotation.pin.id
                else { return }

                switch gesture.state {
                case .began:
                    if !self.didDisableMapScrollForDrag {
                        self.didDisableMapScrollForDrag = true
                        mapView.isScrollEnabled = false
                    }
                case .changed, .ended:
                    let point = gesture.location(in: mapView)
                    let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
                    plantAnnotation.coordinate = coordinate
                    view.center = point
                    self.onPinDrag(plantAnnotation.pin, coordinate)
                case .cancelled, .failed:
                    break
                default:
                    break
                }

                if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                    if self.didDisableMapScrollForDrag {
                        self.didDisableMapScrollForDrag = false
                        mapView.isScrollEnabled = true
                    }
                }
            }
            let diameterMeters = plantAnnotation.pin.canopyDiameterMeters
                ?? CanopyMarkerStyle.fallbackDiameterMeters(for: plantAnnotation.pin.strata)
            let diameterPoints = CanopyMarkerStyle.diameterPoints(
                at: plantAnnotation.coordinate,
                diameterMeters: diameterMeters
            ) { coord in
                mapView.convert(coord, toPointTo: mapView)
            }
            let color = CanopyMarkerStyle.color(for: plantAnnotation.pin.strata)
            view.apply(
                diameter: diameterPoints,
                fillColor: color.withAlphaComponent(0.34),
                strokeColor: color.withAlphaComponent(0.92),
                labelText: CanopyMarkerStyle.abbrev(for: plantAnnotation.pin.commonName)
            )
            return view
        }

        func refreshCanopyAnnotationSizes(on mapView: MKMapView) {
            for annotation in mapView.annotations {
                guard
                    let plantAnnotation = annotation as? PlantPointAnnotation,
                    let view = mapView.view(for: plantAnnotation) as? CanopyAnnotationView
                else { continue }
                let diameterMeters = plantAnnotation.pin.canopyDiameterMeters
                    ?? CanopyMarkerStyle.fallbackDiameterMeters(for: plantAnnotation.pin.strata)
                let diameterPoints = CanopyMarkerStyle.diameterPoints(
                    at: plantAnnotation.coordinate,
                    diameterMeters: diameterMeters
                ) { coord in
                    mapView.convert(coord, toPointTo: mapView)
                }
                let color = CanopyMarkerStyle.color(for: plantAnnotation.pin.strata)
                view.apply(
                    diameter: diameterPoints,
                    fillColor: color.withAlphaComponent(0.34),
                    strokeColor: color.withAlphaComponent(0.92),
                    labelText: CanopyMarkerStyle.abbrev(for: plantAnnotation.pin.commonName)
                )
            }
        }

        @objc
        private func handleMapLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let mapView else { return }

            let point = gesture.location(in: mapView)
            let candidateAnnotations = mapView.annotations.compactMap { $0 as? PlantPointAnnotation }
            guard !candidateAnnotations.isEmpty else { return }

            let nearest = candidateAnnotations.min { lhs, rhs in
                let lp = mapView.convert(lhs.coordinate, toPointTo: mapView)
                let rp = mapView.convert(rhs.coordinate, toPointTo: mapView)
                let ld = hypot(lp.x - point.x, lp.y - point.y)
                let rd = hypot(rp.x - point.x, rp.y - point.y)
                return ld < rd
            }

            guard let nearest else { return }
            let nearestPoint = mapView.convert(nearest.coordinate, toPointTo: mapView)
            let distance = hypot(nearestPoint.x - point.x, nearestPoint.y - point.y)
            let markerRadius: CGFloat = {
                if let view = mapView.view(for: nearest) {
                    return max(14, view.bounds.width * 0.5)
                }
                return 14
            }()
            let hitThreshold = max(markerRadius + 40, 90)
            if distance <= hitThreshold {
                onPinLongPress(nearest.pin)
            }
        }

        @objc
        private func handleMapEditPan(_ gesture: UIPanGestureRecognizer) {
            guard let mapView, let editingPinID else { return }
            let point = gesture.location(in: mapView)

            switch gesture.state {
            case .began:
                let candidate = mapView.annotations
                    .compactMap { $0 as? PlantPointAnnotation }
                    .first(where: { $0.pin.id == editingPinID })
                guard let candidate else { return }
                let candidatePoint = mapView.convert(candidate.coordinate, toPointTo: mapView)
                let markerRadius: CGFloat = {
                    if let view = mapView.view(for: candidate) {
                        return max(14, view.bounds.width * 0.5)
                    }
                    return 14
                }()
                let distance = hypot(candidatePoint.x - point.x, candidatePoint.y - point.y)
                if distance <= markerRadius + 26 {
                    activeDraggedPin = candidate.pin
                } else {
                    activeDraggedPin = nil
                }
            case .changed, .ended:
                guard let pin = activeDraggedPin else { return }
                let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
                if let annotation = mapView.annotations
                    .compactMap({ $0 as? PlantPointAnnotation })
                    .first(where: { $0.pin.id == pin.id }) {
                    annotation.coordinate = coordinate
                }
                // On commit la coordonnée seulement à la fin du geste pour éviter les resyncs saccadés.
                if gesture.state == .ended {
                    onPinDrag(pin, coordinate)
                    activeDraggedPin = nil
                }
            case .cancelled, .failed:
                activeDraggedPin = nil
            default:
                break
            }
        }
    }
}

extension GardenMapUIKitView.Coordinator: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

private final class PlantPointAnnotation: MKPointAnnotation {
    let pin: GardenMapView.PlantPin

    init(pin: GardenMapView.PlantPin) {
        self.pin = pin
        super.init()
    }
}

private final class CanopyAnnotationView: MKAnnotationView {
    private let textLabel = UILabel()
    var onPan: ((UIPanGestureRecognizer) -> Void)?
    var isEditingEnabled: Bool = false {
        didSet {
            panRecognizer.isEnabled = isEditingEnabled
        }
    }
    private lazy var panRecognizer: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        gesture.maximumNumberOfTouches = 1
        return gesture
    }()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        configureLabel()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLabel()
    }

    private func configureLabel() {
        clipsToBounds = true
        addGestureRecognizer(panRecognizer)
        panRecognizer.isEnabled = false
        textLabel.textAlignment = .center
        textLabel.adjustsFontSizeToFitWidth = true
        textLabel.minimumScaleFactor = 0.35
        textLabel.numberOfLines = 1
        textLabel.baselineAdjustment = .alignCenters
        textLabel.textColor = UIColor.label.withAlphaComponent(0.88)
        textLabel.layer.shadowColor = UIColor.black.withAlphaComponent(0.30).cgColor
        textLabel.layer.shadowOpacity = 1
        textLabel.layer.shadowRadius = 1
        textLabel.layer.shadowOffset = CGSize(width: 0, height: 0.5)
        addSubview(textLabel)
    }

    @objc
    private func handlePan(_ gesture: UIPanGestureRecognizer) {
        onPan?(gesture)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = max(2, bounds.width * 0.12)
        textLabel.frame = bounds.insetBy(dx: inset, dy: inset)
    }

    func apply(diameter: CGFloat, fillColor: UIColor, strokeColor: UIColor, labelText: String) {
        let d = max(2, min(5000, diameter))
        bounds = CGRect(x: 0, y: 0, width: d, height: d)
        layer.cornerRadius = d * 0.5
        layer.backgroundColor = fillColor.cgColor
        layer.borderColor = strokeColor.cgColor
        layer.borderWidth = max(1.1, d * 0.055)
        layer.shadowColor = strokeColor.withAlphaComponent(0.35).cgColor
        layer.shadowOpacity = 1
        layer.shadowRadius = 1.2
        layer.shadowOffset = .zero
        textLabel.text = labelText
        textLabel.font = UIFont.systemFont(ofSize: max(8, d * 0.33), weight: .semibold)
        setNeedsLayout()
    }
}

enum CanopyMarkerStyle {
    static func abbrev(for commonName: String) -> String {
        SpeciesAbbreviation.forCommonName(commonName)
    }

    static func fallbackDiameterMeters(for strata: String?) -> Double {
        switch (strata ?? "").lowercased() {
        case "canopée": return 12.0
        case "sous-étage": return 8.0
        case "arbuste": return 4.0
        case "herbacée": return 1.8
        case "couvre-sol": return 1.0
        case "liane": return 2.5
        default: return 3.0
        }
    }

    static func color(for strata: String?) -> UIColor {
        switch (strata ?? "").lowercased() {
        case "canopée": return UIColor(red: 0.36, green: 0.64, blue: 0.40, alpha: 1)
        case "sous-étage": return UIColor(red: 0.34, green: 0.62, blue: 0.58, alpha: 1)
        case "arbuste": return UIColor(red: 0.60, green: 0.50, blue: 0.72, alpha: 1)
        case "herbacée": return UIColor(red: 0.80, green: 0.74, blue: 0.42, alpha: 1)
        case "couvre-sol": return UIColor(red: 0.84, green: 0.62, blue: 0.52, alpha: 1)
        case "liane": return UIColor(red: 0.46, green: 0.58, blue: 0.80, alpha: 1)
        default: return UIColor(red: 0.55, green: 0.60, blue: 0.62, alpha: 1)
        }
    }

    static func diameterPoints(
        at coordinate: CLLocationCoordinate2D,
        diameterMeters: Double,
        convertPoint: (CLLocationCoordinate2D) -> CGPoint
    ) -> CGFloat {
        let metersPerDegreeLon = max(1.0, 111_320.0 * cos(coordinate.latitude * .pi / 180.0))
        let deltaLon = diameterMeters / metersPerDegreeLon
        let offset = CLLocationCoordinate2D(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude + deltaLon
        )
        let p1 = convertPoint(coordinate)
        let p2 = convertPoint(offset)
        return max(2, hypot(p2.x - p1.x, p2.y - p1.y))
    }
}

enum SpeciesAbbreviation {
    static func forCommonName(_ commonName: String) -> String {
        let n = commonName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = n.lowercased()
        if lower.isEmpty { return "" }

        let mapping: [(String, String)] = [
            ("noyer", "Noy"),
            ("pommier", "Pom"),
            ("poirier", "Poi"),
            ("châtaignier", "Châ"),
            ("chataignier", "Châ"),
            ("prunier", "Pru"),
            ("cerisier", "Cer"),
            ("abricotier", "Abr"),
            ("pêcher", "Pêc"),
            ("pecher", "Pêc"),
            ("amandier", "Ama"),
            ("figuier", "Fig"),
            ("cognassier", "Cog"),
            ("néflier", "Néf"),
            ("neflier", "Néf"),
            ("noisetier", "Noi"),
            ("chêne", "Chê"),
            ("chene", "Chê"),
            ("érable", "Éra"),
            ("erable", "Éra"),
            ("tilleul", "Til")
        ]
        for (key, abbr) in mapping where lower.contains(key) {
            return abbr
        }

        let firstWord = lower.split(separator: " ").first.map(String.init) ?? lower
        let prefix3 = String(firstWord.prefix(3))
        guard !prefix3.isEmpty else { return "" }
        return prefix3.prefix(1).uppercased() + prefix3.dropFirst()
    }
}

private final class BaseTileOverlay: MKTileOverlay {
    enum Kind {
        case ignPlan
    }
    let kind: Kind

    init(kind: Kind, urlTemplate: String) {
        self.kind = kind
        super.init(urlTemplate: urlTemplate)
        tileSize = CGSize(width: 256, height: 256)
    }
}

private final class CompositeReliefTileOverlay: MKTileOverlay {
    private let lidarTemplate: String
    private let fallbackTemplate: String

    init(lidarTemplate: String, fallbackTemplate: String) {
        self.lidarTemplate = lidarTemplate
        self.fallbackTemplate = fallbackTemplate
        super.init(urlTemplate: nil)
        tileSize = CGSize(width: 256, height: 256)
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        // Unused (loadTile override handles both sources).
        URL(string: "about:blank")!
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let effectivePath = clampedPath(path)
        let lidarURL = makeURL(from: lidarTemplate, path: effectivePath)
        let fallbackURL = makeURL(from: fallbackTemplate, path: effectivePath)
        fetchImageData(from: lidarURL) { lidarData in
            if let lidarData {
                self.returnTile(data: lidarData, originalPath: path, effectivePath: effectivePath, result: result)
                return
            }
            self.fetchImageData(from: fallbackURL) { fallbackData in
                guard let fallbackData else {
                    result(nil, nil)
                    return
                }
                self.returnTile(data: fallbackData, originalPath: path, effectivePath: effectivePath, result: result)
            }
        }
    }

    private func makeURL(from template: String, path: MKTileOverlayPath) -> URL {
        let urlString = template
            .replacingOccurrences(of: "{z}", with: "\(path.z)")
            .replacingOccurrences(of: "{x}", with: "\(path.x)")
            .replacingOccurrences(of: "{y}", with: "\(path.y)")
        return URL(string: urlString)!
    }

    private func clampedPath(_ path: MKTileOverlayPath) -> MKTileOverlayPath {
        guard path.z > 18 else { return path }
        let shift = path.z - 18
        return MKTileOverlayPath(
            x: path.x >> shift,
            y: path.y >> shift,
            z: 18,
            contentScaleFactor: path.contentScaleFactor
        )
    }

    private func returnTile(
        data: Data,
        originalPath: MKTileOverlayPath,
        effectivePath: MKTileOverlayPath,
        result: @escaping (Data?, Error?) -> Void
    ) {
        guard originalPath.z > effectivePath.z else {
            result(data, nil)
            return
        }

        guard
            let image = UIImage(data: data),
            let upscaled = upscaleFromAncestor(image: image, originalPath: originalPath, ancestorPath: effectivePath),
            let png = upscaled.pngData()
        else {
            result(data, nil)
            return
        }
        result(png, nil)
    }

    private func upscaleFromAncestor(
        image: UIImage,
        originalPath: MKTileOverlayPath,
        ancestorPath: MKTileOverlayPath
    ) -> UIImage? {
        let levels = originalPath.z - ancestorPath.z
        guard levels > 0 else { return image }

        let divisor = 1 << levels
        let relX = originalPath.x % divisor
        let relY = originalPath.y % divisor

        let tileSize = image.size.width
        let cropSize = tileSize / CGFloat(divisor)
        let cropRect = CGRect(
            x: CGFloat(relX) * cropSize,
            y: CGFloat(relY) * cropSize,
            width: cropSize,
            height: cropSize
        ).integral

        guard
            let cgImage = image.cgImage,
            let cropped = cgImage.cropping(to: cropRect)
        else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: tileSize, height: tileSize), format: format)
        return renderer.image { _ in
            UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
                .draw(in: CGRect(x: 0, y: 0, width: tileSize, height: tileSize))
        }
    }

    private func fetchImageData(from url: URL, completion: @escaping (Data?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, response, _ in
            guard
                let data,
                !data.isEmpty,
                let http = response as? HTTPURLResponse,
                (200...299).contains(http.statusCode),
                let mime = response?.mimeType?.lowercased(),
                mime.hasPrefix("image/")
            else {
                completion(nil)
                return
            }
            completion(data)
        }.resume()
    }
}

private final class SoftReliefTileOverlayRenderer: MKTileOverlayRenderer {
    var reliefOpacity: Double = 0.35
    var reliefBlendMode: CGBlendMode = .softLight
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        context.saveGState()
        context.setBlendMode(reliefBlendMode)
        context.setAlpha(CGFloat(reliefOpacity))
        super.draw(mapRect, zoomScale: zoomScale, in: context)
        context.restoreGState()
    }
}
#endif
