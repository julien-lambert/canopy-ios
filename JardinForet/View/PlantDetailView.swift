import SwiftUI

struct PlantDetailView: View {
    @EnvironmentObject var store: CanopyStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingPlantForm = false
    @State private var showingDeleteAlert = false
    @State private var currentPlantID: Int?
    @State private var swipeDirection: Edge = .trailing
    let plant: GardenPlant

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 16) {

                    // Bandeau haut
                    headerHero
                        .id("hero-\(activePlant.id)")

                    PlantDetailContent(
                        plant: activePlant,
                        siteIlot: activePlantIlot
                    )
                        .padding(.horizontal)
                }
                .padding(.bottom, 24)
            }
            .id("page-\(activePlant.id)")
            .transition(
                .asymmetric(
                    insertion: .move(edge: swipeDirection),
                    removal: .move(edge: swipeDirection == .trailing ? .leading : .trailing)
                )
            )
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle(activePlant.commonName)   // un titre commun aux deux plateformes
        .animation(.easeInOut(duration: 0.28), value: activePlant.id)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.canMutateSpeciesAndIndividuals {
                ToolbarItemGroup(placement: .primaryAction) {
                    CanopyToolbarIconButton(systemImage: "square.and.pencil") {
                        showingPlantForm = true
                    }

                    CanopyToolbarIconButton(systemImage: "trash", role: .destructive) {
                        showingDeleteAlert = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingPlantForm) {
            IndividualSheet(mode: .edit(plantID: activePlant.id))
                .environmentObject(store)
        }
        .alert("Supprimer cet individu ?", isPresented: $showingDeleteAlert) {
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                store.deletePlant(activePlant)
                dismiss()
            }
        } message: {
            Text("Cette action marquera cet individu comme supprimé et la modification sera synchronisée avec la base distante.")
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    handleSwipe(value)
                }
        )
        #endif
        .onAppear {
            if currentPlantID == nil {
                currentPlantID = plant.id
            }
        }
    }

    private var headerHero: some View {
        let imageURL = resolvedPlantImageURL(local: activePlant.imageLocal, remote: activePlant.speciesImageURL)

        return ZStack {
            if let url = imageURL {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    // fallback / loading
                    ZStack {
                        Color.black.opacity(0.15)
                        Image(systemName: "leaf")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }

            } else {
                // aucun visuel disponible → bandeau neutre
                ZStack {
                    LinearGradient(
                        colors: [
                            Color.gray.opacity(0.25),
                            Color.gray.opacity(0.35)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "leaf")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
        }
        .frame(height: 160)                // hauteur du bandeau
        .clipped()                         // recadrage type "aspectFill"
    }

    private var activePlantIlot: GardenSiteIlot? {
        guard let ilotID = activePlant.siteIlotID else { return nil }
        return store.siteIlots.first(where: { $0.id == ilotID })
    }

    private var activePlant: GardenPlant {
        if let id = currentPlantID,
           let found = store.plants.first(where: { $0.id == id }) {
            return found
        }
        return plant
    }

    private var orderedPlantIDs: [Int] {
        store.plants
            .sorted { a, b in
                if a.commonName.caseInsensitiveCompare(b.commonName) != .orderedSame {
                    return a.commonName.localizedCaseInsensitiveCompare(b.commonName) == .orderedAscending
                }
                if a.latinName.caseInsensitiveCompare(b.latinName) != .orderedSame {
                    return a.latinName.localizedCaseInsensitiveCompare(b.latinName) == .orderedAscending
                }
                return a.id < b.id
            }
            .map(\.id)
    }

    private func handleSwipe(_ value: DragGesture.Value) {
        let dx = value.translation.width
        let dy = value.translation.height
        guard abs(dx) > 50, abs(dx) > abs(dy) else { return }
        guard let currentID = currentPlantID,
              let idx = orderedPlantIDs.firstIndex(of: currentID) else { return }

        if dx < 0, idx + 1 < orderedPlantIDs.count {
            swipeDirection = .trailing
            withAnimation(.easeInOut(duration: 0.28)) {
                currentPlantID = orderedPlantIDs[idx + 1]
            }
        } else if dx > 0, idx > 0 {
            swipeDirection = .leading
            withAnimation(.easeInOut(duration: 0.28)) {
                currentPlantID = orderedPlantIDs[idx - 1]
            }
        }
    }
}

fileprivate struct PlantDetailContent: View {
    let plant: GardenPlant
    let siteIlot: GardenSiteIlot?

    var body: some View {
        #if os(macOS)
        macLayout
        #else
        iosLayout
        #endif
    }

    // MARK: - Layout iOS : une seule colonne

    private var iosLayout: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 1. En-tête (nom, cultivar, latin, label)
            headerSection

            // 2. Carte identité
            identityCard
            
            botanicalCard          // ← ajout ici

            // 4. Carte plantation (date)
            plantingCard

            // 3. Carte localisation / coordonnées
            locationCard
            

            // 5. Carte notes
            notesCard
        }
    }

    // MARK: - Layout macOS : deux colonnes

       private var macLayout: some View {
        VStack(alignment: .leading, spacing: 16) {

            headerSection

            HStack(alignment: .top, spacing: 16) {

                VStack(alignment: .leading, spacing: 16) {
                    identityCard
                    botanicalCard      // ← ajout colonne gauche
                    plantingCard
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 16) {
                    locationCard
                    notesCard
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    fileprivate struct PlantLocationMap: View {
        let latitude: Double
        let longitude: Double

        var body: some View {
            ZStack {
                LinearGradient(
                    colors: [
                        Color.accentPrimary.opacity(0.14),
                        Color.accentSecondary.opacity(0.10),
                        Color.black.opacity(0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                CoordinateGrid()
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)

                VStack(spacing: 12) {
                    Spacer(minLength: 0)

                    StaticMarker()

                    Spacer(minLength: 0)

                    Text(String(format: "%.6f, %.6f", latitude, longitude))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.primary.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 14)
                }
                .padding(12)
            }
        }

        private struct CoordinateGrid: Shape {
            func path(in rect: CGRect) -> Path {
                var path = Path()
                let verticalSteps = 5
                let horizontalSteps = 4

                for index in 1..<verticalSteps {
                    let x = rect.minX + rect.width * CGFloat(index) / CGFloat(verticalSteps)
                    path.move(to: CGPoint(x: x, y: rect.minY))
                    path.addLine(to: CGPoint(x: x, y: rect.maxY))
                }

                for index in 1..<horizontalSteps {
                    let y = rect.minY + rect.height * CGFloat(index) / CGFloat(horizontalSteps)
                    path.move(to: CGPoint(x: rect.minX, y: y))
                    path.addLine(to: CGPoint(x: rect.maxX, y: y))
                }

                return path
            }
        }

        private struct StaticMarker: View {
            var body: some View {
                ZStack {
                    Circle()
                        .fill(Color.accentPrimary.opacity(0.20))
                        .frame(width: 54, height: 54)

                    Circle()
                        .fill(Color.accentPrimary)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .shadow(color: Color.black.opacity(0.18), radius: 6, y: 2)
                }
            }
        }
    }

    fileprivate struct MapPlaceholderView: View {
        var body: some View {
            ZStack {
                // Fond “carte grisée”
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

                    Text("Aucune coordonnée enregistrée")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
        }
    }
    
    
    // MARK: - Sections (inchangées)

    /// Nom, cultivar, nom latin, label
    /// Identité textuelle sous l’image (nom, cultivar, latin, zone, label…)
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Ligne 1 : nom + capsule code
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(plant.commonName)
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer(minLength: 8)

                if let label = plant.label, !label.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "tag")
                            .font(.caption2)
                        Text(label)
                            .font(.caption)
                            .textCase(.uppercase)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.cardBackground)
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.accentPrimary.opacity(0.35), lineWidth: 0.7)
                    )
                    .foregroundColor(.accentPrimary)
                }
            }

            // Ligne 2 : cultivar
            if let v = plant.varietyName, !v.isEmpty {
                Text(v)
                    .font(.headline)
                    .foregroundColor(.secondary)
            }

            // Ligne 3 : nom latin
            if !plant.latinName.isEmpty {
                Text(plant.latinName)
                    .italic()
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Ligne 4 : capsules de contexte (zone, statut)
            HStack(spacing: 8) {
                if let zone = plant.zone, !zone.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "square.grid.2x2")
                            .font(.caption2)
                        Text("Zone \(zone)")
                            .font(.caption)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.accentPrimary.opacity(0.08))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.accentPrimary.opacity(0.3), lineWidth: 0.6)
                    )
                    .foregroundColor(.accentPrimary)
                }

                if let status = plant.status, !status.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "leaf.fill")
                            .font(.caption2)
                        Text(status)
                            .font(.caption)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.cardBackground)
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.gray.opacity(0.25), lineWidth: 0.6)
                    )
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    /// Carte identité (ID, label, zone)
    private var identityCard: some View {
        DetailCard(title: "Identité") {

            InfoRow(label: "Espèce", value: plant.commonName)

            if let v = plant.varietyName, !v.isEmpty {
                InfoRow(label: "Cultivar", value: v)
            }

            if !plant.latinName.isEmpty {
                InfoRow(label: "Nom latin", value: plant.latinName)
            }

            if let family = plant.family, !family.isEmpty {
                InfoRow(label: "Famille", value: family)
            }

            if let genus = plant.genus, !genus.isEmpty {
                InfoRow(label: "Genre", value: genus)
            }

            if let root = plant.rootstock, !root.isEmpty {
                InfoRow(label: "Porte-greffe", value: root)
            }
            // Strate botanique de l’espèce
            if let strata = plant.strata, !strata.isEmpty {
                InfoRow(label: "Strate", value: strata)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Carte localisation : lat / lon / altitude, micro-site, expo, sol
    /// Carte localisation : lat / lon / altitude, micro-site, expo, sol + mini-carte
    private var locationCard: some View {
        DetailCard(title: "Localisation") {
            
            if let zone = plant.zone, !zone.isEmpty {
                InfoRow(label: "Zone", value: zone)
            }

            if let siteIlot {
                let ilotLabel = [siteIlot.code, siteIlot.name]
                    .compactMap { value in
                        guard let value, !value.isEmpty else { return nil }
                        return value
                    }
                    .joined(separator: " — ")
                if !ilotLabel.isEmpty {
                    InfoRow(label: "Îlot", value: ilotLabel)
                }
                if let area = siteIlot.areaM2 {
                    InfoRow(label: "Surface d'îlot", value: String(format: "%.1f m²", area))
                }
            } else if let siteIlotCode = plant.siteIlotCode, !siteIlotCode.isEmpty {
                let fallbackLabel = [siteIlotCode, plant.siteIlotName]
                    .compactMap { value in
                        guard let value, !value.isEmpty else { return nil }
                        return value
                    }
                    .joined(separator: " — ")
                if !fallbackLabel.isEmpty {
                    InfoRow(label: "Îlot", value: fallbackLabel)
                }
            }

            // Altitude
            if let alt = plant.altitude {
                InfoRow(
                    label: "Altitude",
                    value: String(format: "%.0f m", alt)
                )
            }
            
            // Coordonnées textuelles
            if let lat = plant.lat, let lon = plant.lon {
                InfoRow(
                    label: "Coordonnées",
                    value: String(format: "%.6f, %.6f", lat, lon)
                )

                // Mini-carte si on a des coordonnées
                PlantLocationMap(
                    latitude: lat,
                    longitude: lon
                )
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.top, 4)

            } else {
                InfoRow(label: "Coordonnées", value: "Non renseignées")

                // Carte “fantôme” si pas de coordonnées
                MapPlaceholderView()
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 4)
            }

            // Contexte local
            if let micro = plant.microSite, !micro.isEmpty {
                InfoRow(label: "Micro-site", value: micro)
            }

            if let expo = plant.exposureLocal, !expo.isEmpty {
                InfoRow(label: "Exposition", value: expo)
            }

            if let soil = plant.soilLocal, !soil.isEmpty {
                InfoRow(label: "Sol local", value: soil)
            }

            if let siteIlot {
                if let exposure = siteIlot.sunExposure, !exposure.isEmpty {
                    InfoRow(label: "Ensoleillement", value: exposure)
                }
                if let humidity = siteIlot.humidityProfile, !humidity.isEmpty {
                    InfoRow(label: "Humidité", value: humidity)
                }
                if let pedology = siteIlot.pedology, !pedology.isEmpty {
                    InfoRow(label: "Pédologie", value: pedology)
                }
                if let drainage = siteIlot.drainageProfile, !drainage.isEmpty {
                    InfoRow(label: "Drainage", value: drainage)
                }
                if let frostExposure = siteIlot.frostExposure, !frostExposure.isEmpty {
                    InfoRow(label: "Exposition au gel", value: frostExposure)
                }
                if let windExposure = siteIlot.windExposure, !windExposure.isEmpty {
                    InfoRow(label: "Vent", value: windExposure)
                }
                if let managementIntensity = siteIlot.managementIntensity, !managementIntensity.isEmpty {
                    InfoRow(label: "Gestion", value: managementIntensity)
                }
                if let slopePct = siteIlot.slopePct {
                    InfoRow(label: "Pente", value: String(format: "%.0f %%", slopePct))
                }
                if let aspect = siteIlot.aspect, !aspect.isEmpty {
                    InfoRow(label: "Aspect", value: aspect)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Carte plantation (date, mode d’acquisition, source)
    private var plantingCard: some View {
        DetailCard(title: "Plantation") {
            if let date = plant.plantedAt, !date.isEmpty {
                InfoRow(label: "Planté le", value: date)
            } else {
                InfoRow(label: "Planté le", value: "Non renseigné")
            }

            if let type = plant.acquisitionType, !type.isEmpty {
                InfoRow(label: "Acquisition", value: type)
            }

            if let src = plant.acquisitionSource, !src.isEmpty {
                InfoRow(label: "Source", value: src)
            }

            if let status = plant.status, !status.isEmpty {
                InfoRow(label: "Statut", value: status)
            }

            if let care = plant.careNotes, !care.isEmpty {
                InfoRow(label: "Entretien", value: care)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    /// Propriétés botaniques issues de l’espèce / du cultivar
    private var botanicalCard: some View {
        DetailCard(title: "Propriétés botaniques") {

            // Famille / genre / type
            if let family = plant.family, !family.isEmpty {
                InfoRow(label: "Famille", value: family)
            }

            if let genus = plant.genus, !genus.isEmpty {
                InfoRow(label: "Genre", value: genus)
            }

            if let type = plant.plantType, !type.isEmpty {
                InfoRow(label: "Type", value: type)
            }

            // Origine géographique
            if let origin = plant.origin, !origin.isEmpty {
                InfoRow(label: "Origine", value: origin)
            }

            // Taille adulte de l’espèce
            if let hmin = plant.speciesHeightMin, let hmax = plant.speciesHeightMax {
                InfoRow(
                    label: "Hauteur adulte",
                    value: String(format: "%.1f – %.1f m", hmin, hmax)
                )
            } else if let hmin = plant.speciesHeightMin {
                InfoRow(
                    label: "Hauteur adulte",
                    value: String(format: "≥ %.1f m", hmin)
                )
            }

            // Longévité indicative
            if let lmin = plant.lifespanMin, let lmax = plant.lifespanMax {
                InfoRow(
                    label: "Longévité",
                    value: "\(lmin) – \(lmax) ans"
                )
            } else if let lmin = plant.lifespanMin {
                InfoRow(label: "Longévité", value: "≥ \(lmin) ans")
            }

            // Mellifère / ornemental
            if let mell = plant.melliferousLevel, !mell.isEmpty {
                InfoRow(label: "Mellifère", value: mell)
            }

            if let orn = plant.ornamentalInterest, !orn.isEmpty {
                InfoRow(label: "Intérêt ornemental", value: orn)
            }

            if plant.varietyName?.isEmpty == false {
                Divider().padding(.vertical, 4)
                Text("Spécificités cultivar")
                    .font(.caption).bold()
                    .foregroundColor(.secondary)

                if let origin = plant.cultivarOrigin, !origin.isEmpty {
                    InfoRow(label: "Origine cultivar", value: origin)
                }
                if let type = plant.cultivarPlantType, !type.isEmpty {
                    InfoRow(label: "Type cultivar", value: type)
                }
                if let mell = plant.cultivarMelliferousLevel, !mell.isEmpty {
                    InfoRow(label: "Mellifère cultivar", value: mell)
                }
                if let orn = plant.cultivarOrnamentalInterest, !orn.isEmpty {
                    InfoRow(label: "Ornemental cultivar", value: orn)
                }
                if plant.cultivarLifespanMin != nil || plant.cultivarLifespanMax != nil {
                    let min = plant.cultivarLifespanMin.map(String.init) ?? "?"
                    let max = plant.cultivarLifespanMax.map(String.init) ?? "?"
                    InfoRow(label: "Longévité cultivar", value: "\(min) – \(max) ans")
                }
                if plant.cultivarHeightMin != nil || plant.cultivarHeightMax != nil {
                    let min = plant.cultivarHeightMin.map { String(format: "%.1f", $0) } ?? "?"
                    let max = plant.cultivarHeightMax.map { String(format: "%.1f", $0) } ?? "?"
                    InfoRow(label: "Hauteur cultivar", value: "\(min) – \(max) m")
                }
                if let flowering = plant.cultivarFloweringPeriod, !flowering.isEmpty {
                    InfoRow(label: "Floraison cultivar", value: flowering)
                }
                if let fruiting = plant.cultivarFruitingPeriod, !fruiting.isEmpty {
                    InfoRow(label: "Fructification cultivar", value: fruiting)
                }
            }

            // rivate var notesCardes descriptives d’espèce / cultivar
            if let sNotes = plant.speciesNotes, !sNotes.isEmpty {
                Divider().padding(.vertical, 4)
                Text("Note d’espèce")
                    .font(.caption).bold()
                    .foregroundColor(.secondary)
                Text(sNotes)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let vNotes = plant.varietyNotes, !vNotes.isEmpty {
                Divider().padding(.vertical, 4)
                Text("Note de cultivar")
                    .font(.caption).bold()
                    .foregroundColor(.secondary)
                Text(vNotes)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Morphologie / culture (résumés longs)
            if let morph = plant.morphology, !morph.isEmpty {
                Divider().padding(.vertical, 4)
                Text("Morphologie")
                    .font(.caption).bold()
                    .foregroundColor(.secondary)
                Text(morph)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let cult = plant.culture, !cult.isEmpty {
                Divider().padding(.vertical, 4)
                Text("Culture")
                    .font(.caption).bold()
                    .foregroundColor(.secondary)
                Text(cult)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // Tags fusionnés : espèce + cultivar + individu, sans doublons
    private var mergedTags: [String] {
        var result: [String] = []
        var seen = Set<String>()   // on dédoublonne en ignorant la casse

        func appendTags(from raw: String?) {
            guard let raw = raw else { return }

            let parts = raw
                .split(whereSeparator: { ",;|".contains($0) })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            for t in parts {
                let key = t.lowercased()
                if !seen.contains(key) {
                    seen.insert(key)
                    result.append(t)
                }
            }
        }

        // 1) Tags d'espèce (si tu as un champ speciesTags dans Plant)
        appendTags(from: plant.speciesTags)

        // 2) Tags de cultivar
        appendTags(from: plant.cultivarTags)

        // 3) Tags individu (tagsArray : [String])
        for t in plant.tagsArray {
            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                result.append(trimmed)
            }
        }

        return result
    }

    /// Carte notes générales + tags (même style que SpeciesDetail)
    private var notesCard: some View {
        DetailCard(title: "Notes & usages") {

            // Notes de l’individu
            if let notes = plant.notes, !notes.isEmpty {
                Text(notes)
                    .font(.body)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Aucune note pour cet individu.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            // Usages de l’espèce (même logique de chips que SpeciesDetailView)
            if let uses = plant.uses, !uses.isEmpty {
                let chips = uses
                    .split(whereSeparator: { ",;|".contains($0) })
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                if !chips.isEmpty {
                    Divider().padding(.vertical, 4)
                    Text("Usages")
                        .font(.caption).bold()
                        .foregroundColor(.secondary)

                    WrapChips(chips: chips)
                }
            }

            // Tags fusionnés (espèce + cultivar + individu), sans doublons
            if !mergedTags.isEmpty {
                Divider().padding(.vertical, 4)
                Text("Tags")
                    .font(.caption).bold()
                    .foregroundColor(.secondary)

                WrapChips(chips: mergedTags)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private struct WrapChips: View {
        let chips: [String]

        private let columns = [
            GridItem(.adaptive(minimum: 80), spacing: 6, alignment: .leading)
        ]

        var body: some View {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(Array(chips.enumerated()), id: \.offset) { _, tag in
                    Text(tag)
                        .font(.caption)
                        // plus de lineLimit / truncation → le texte peut aller sur 2–3 lignes
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.accentPrimary.opacity(0.10))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.accentPrimary.opacity(0.35), lineWidth: 0.7)
                        )
                        .foregroundColor(.accentPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        // fixedSize vertical → la capsule s’agrandit en hauteur au lieu de tronquer
                }
            }
        }
    }
}

// MARK: - Sous-vues génériques

fileprivate struct DetailCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        CanopyCard(title: title) {
            content
        }
    }
}

fileprivate struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        CanopyInfoLine(label: label, value: value)
            .padding(.vertical, 2)
    }
}
