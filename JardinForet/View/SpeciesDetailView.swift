import SwiftUI

struct SpeciesDetailView: View {
    @EnvironmentObject var store: CanopyStore
    @Environment(\.dismiss) private var dismiss

    /// Identifiant espèce passé depuis la liste (prioritaire)
    let speciesId: Int?
    /// Fallback legacy par nom latin
    let latinName: String?

    /// Données complètes espèce + cultivars + individus
    @State private var detail: GardenTaxonDetailData?
    @State private var showingDeleteAlert = false
    @State private var deleteErrorMessage: String?
    @State private var currentSpeciesID: Int?
    @State private var swipeDirection: Edge = .trailing

    init(speciesId: Int) {
        self.speciesId = speciesId
        self.latinName = nil
    }

    init(latinName: String) {
        self.speciesId = nil
        self.latinName = latinName
    }

    var body: some View {
        Group {
            if let detail = detail {
                ZStack {
                    ScrollView {
                        #if os(macOS)
                        VStack(alignment: .leading, spacing: 16) {
                            headerSection(detail.base)

                            HStack(alignment: .top, spacing: 16) {
                                VStack(alignment: .leading, spacing: 16) {
                                    identitySection(detail.base)
                                    cultivarsSection(detail.cultivars)
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)

                                VStack(alignment: .leading, spacing: 16) {
                                    ecologySection(detail.base)
                                    SpeciesPlantsMapSection(plants: detail.plants)
                                    plantsSection(detail.plants)
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                        }
                        .padding(16)
                        #else
                        VStack(alignment: .leading, spacing: 16) {
                            headerSection(detail.base)
                                .id("hero-\(detail.base.id)")
                            identitySection(detail.base)
                            ecologySection(detail.base)
                            cultivarsSection(detail.cultivars)
                            SpeciesPlantsMapSection(plants: detail.plants)
                            plantsSection(detail.plants)
                        }
                        .padding()
                        #endif
                    }
                    .id("page-\(detail.base.id)")
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: swipeDirection),
                            removal: .move(edge: swipeDirection == .trailing ? .leading : .trailing)
                        )
                    )
                }
                .background(Color.appBackground.ignoresSafeArea())
                .navigationTitle(detail.base.commonName)
                .animation(.easeInOut(duration: 0.28), value: detail.base.id)
#if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if store.canMutateSpeciesAndIndividuals {
                        ToolbarItemGroup(placement: .primaryAction) {
                            NavigationLink {
                                SpeciesFormView(existingSpecies: detail.base, cultivars: detail.cultivars)
                            } label: {
                                Image(systemName: "square.and.pencil")
                            }

                            if canDeleteSpecies(detail) {
                                CanopyToolbarIconButton(systemImage: "trash", role: .destructive) {
                                    showingDeleteAlert = true
                                }
                            }
                        }
                    }
                }
                .alert("Supprimer cette espèce ?", isPresented: $showingDeleteAlert) {
                    Button("Annuler", role: .cancel) { }
                    Button("Supprimer", role: .destructive) {
                        handleDeleteSpecies(detail)
                    }
                } message: {
                    Text("Cette action marquera l’espèce comme supprimée et sera synchronisée.")
                }
                .alert("Suppression impossible", isPresented: Binding(
                    get: { deleteErrorMessage != nil },
                    set: { if !$0 { deleteErrorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) { deleteErrorMessage = nil }
                } message: {
                    Text(deleteErrorMessage ?? "")
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 24)
                        .onEnded { value in
                            handleSwipe(value)
                        }
                )
#endif
            } else {
                // État de chargement ou espèce introuvable
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Chargement de la fiche espèce…")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground.ignoresSafeArea())
            }
        }
        .onAppear {
            loadInitialSpeciesIfNeeded()
        }
    }

    private func canDeleteSpecies(_ detail: GardenTaxonDetailData) -> Bool {
        detail.cultivars.isEmpty && detail.plants.isEmpty
    }

    private func handleDeleteSpecies(_ detail: GardenTaxonDetailData) {
        let result = store.deleteSpecies(id: detail.base.id)
        switch result {
        case .success:
            dismiss()
        case .linkedToCultivars:
            deleteErrorMessage = "Cette espèce possède des cultivars actifs."
        case .linkedToPlants:
            deleteErrorMessage = "Cette espèce possède des individus actifs."
        case .failure:
            deleteErrorMessage = "La suppression a échoué."
        }
    }

    private var orderedSpeciesIDs: [Int] {
        store.fetchSpeciesBase().map(\.id)
    }

    private func loadInitialSpeciesIfNeeded() {
        if currentSpeciesID == nil {
            if let speciesId {
                currentSpeciesID = speciesId
            } else if let latinName,
                      let resolved = store.fetchSpeciesBase().first(where: { $0.latinName == latinName }) {
                currentSpeciesID = resolved.id
            }
        }

        if let id = currentSpeciesID {
            detail = store.fetchSpeciesDetail(speciesId: Int32(id))
        } else if let latinName {
            detail = store.fetchSpeciesDetail(latinName: latinName)
        } else {
            detail = nil
        }
    }

    private func handleSwipe(_ value: DragGesture.Value) {
        let dx = value.translation.width
        let dy = value.translation.height
        guard abs(dx) > 50, abs(dx) > abs(dy) else { return }
        guard let currentID = currentSpeciesID,
              let idx = orderedSpeciesIDs.firstIndex(of: currentID) else { return }

        if dx < 0, idx + 1 < orderedSpeciesIDs.count {
            swipeDirection = .trailing
            withAnimation(.easeInOut(duration: 0.28)) {
                currentSpeciesID = orderedSpeciesIDs[idx + 1]
                detail = store.fetchSpeciesDetail(speciesId: Int32(orderedSpeciesIDs[idx + 1]))
            }
        } else if dx > 0, idx > 0 {
            swipeDirection = .leading
            withAnimation(.easeInOut(duration: 0.28)) {
                currentSpeciesID = orderedSpeciesIDs[idx - 1]
                detail = store.fetchSpeciesDetail(speciesId: Int32(orderedSpeciesIDs[idx - 1]))
            }
        }
    }

    // MARK: - Sections

    /// En-tête avec image, nom vernaculaire, latin, famille / genre
    private func headerSection(_ base: GardenTaxon) -> some View {
        HStack(alignment: .center, spacing: 16) {

            // Avatar image espèce
            SpeciesAvatar(urlString: base.imageURL,
                          fallbackText: base.commonName)

            VStack(alignment: .leading, spacing: 4) {
                Text(base.commonName)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(base.latinName)
                    .italic()
                    .foregroundColor(.secondary)

                if let fam = base.family, !fam.isEmpty {
                    Text(fam)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if let gen = base.genus, !gen.isEmpty {
                    Text(gen)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
    }

    /// Carte identité botanique
    private func identitySection(_ base: GardenTaxon) -> some View {
        SectionCard(title: "Identité botanique") {
            KeyValueRow(label: "Nom latin", value: base.latinName)
            KeyValueRow(label: "Nom vernaculaire", value: base.commonName)

            if let fam = base.family, !fam.isEmpty {
                KeyValueRow(label: "Famille", value: fam)
            }
            if let gen = base.genus, !gen.isEmpty {
                KeyValueRow(label: "Genre", value: gen)
            }
            if let strata = base.strata, !strata.isEmpty {
                KeyValueRow(label: "Strate", value: strata)
            }
            if let origin = base.origin, !origin.isEmpty {
                KeyValueRow(label: "Origine", value: origin)
            }
            if let plantType = base.plantType, !plantType.isEmpty {
                KeyValueRow(label: "Type", value: plantType)
            }

            if base.lifespanMin != nil || base.lifespanMax != nil {
                let min = base.lifespanMin.map { "\($0)" } ?? "?"
                let max = base.lifespanMax.map { "\($0)" } ?? "?"
                KeyValueRow(label: "Longévité", value: "\(min) – \(max) ans")
            }

            if base.heightMin != nil || base.heightMax != nil {
                let minH = base.heightMin.map { String(format: "%.1f", $0) } ?? "?"
                let maxH = base.heightMax.map { String(format: "%.1f", $0) } ?? "?"
                KeyValueRow(label: "Hauteur adulte", value: "\(minH) – \(maxH) m")
            }

            if let flowering = base.floweringPeriod, !flowering.isEmpty {
                KeyValueRow(label: "Floraison", value: flowering)
            }

            if let fruiting = base.fruitingPeriod, !fruiting.isEmpty {
                KeyValueRow(label: "Fructification", value: fruiting)
            }

            if let mell = base.melliferousLevel, !mell.isEmpty {
                KeyValueRow(label: "Mellifère", value: mell)
            }

            if let orn = base.ornamentalInterest, !orn.isEmpty {
                KeyValueRow(label: "Intérêt ornemental", value: orn)
            }

            if let tags = base.tags, !tags.isEmpty {
                TagCapsuleRow(label: "Tags espèce", tagsString: tags)
            }
        }
    }

    /// Carte écologie / culture / usages
    private func ecologySection(_ base: GardenTaxon) -> some View {
        SectionCard(title: "Écologie, culture, usages") {
            if let morph = base.morphology, !morph.isEmpty {
                TextBlock(label: "Morphologie", text: morph)
            }
            if let cult = base.culture, !cult.isEmpty {
                TextBlock(label: "Culture", text: cult)
            }
            if let uses = base.uses, !uses.isEmpty {
                TextBlock(label: "Usages", text: uses)
            }
            if let notes = base.notes, !notes.isEmpty {
                TextBlock(label: "Notes", text: notes)
            }
        }
    }

    /// Carte des cultivars
    private func cultivarsSection(_ cultivars: [GardenTaxon]) -> some View {
        SectionCard(title: "Cultivars présents") {
            if cultivars.isEmpty {
                Text("Aucun cultivar distinct recensé dans le jardin pour cette espèce.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(cultivars) { cv in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(cv.varietyName)
                                .font(.headline)
                            Spacer()
                            Text("\(cv.plantCount) individu(s)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let tags = cv.tags, !tags.isEmpty {
                            TagCapsuleRow(label: "Tags", tagsString: tags)
                        }

                        if let origin = cv.origin, !origin.isEmpty {
                            KeyValueRow(label: "Origine", value: origin)
                        }
                        if let type = cv.plantType, !type.isEmpty {
                            KeyValueRow(label: "Type", value: type)
                        }
                        if let flowering = cv.floweringPeriod, !flowering.isEmpty {
                            KeyValueRow(label: "Floraison", value: flowering)
                        }
                        if let fruiting = cv.fruitingPeriod, !fruiting.isEmpty {
                            KeyValueRow(label: "Fructification", value: fruiting)
                        }

                        if let notes = cv.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)

                    if cv.id != cultivars.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    /// Carte des individus du jardin
    private func plantsSection(_ plants: [GardenPlant]) -> some View {
        SectionCard(title: "Individus dans le jardin") {
            if plants.isEmpty {
                Text("Aucun individu de cette espèce n’est encore enregistré dans le jardin.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(plants, id: \.id) { p in
                    NavigationLink(
                        destination: PlantDetailView(plant: p)
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(p.label ?? "#\(p.id)")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                if let v = p.varietyName, !v.isEmpty {
                                    Text("– \(v)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }

                            if let zone = p.zone, !zone.isEmpty {
                                Text("Zone \(zone)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if let status = p.status, !status.isEmpty {
                                Text(status)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 3)

                    if p.id != plants.last?.id {
                        Divider()
                    }
                }
            }
        }
    }
}

fileprivate struct SpeciesPlantsMapSection: View {
    let plants: [GardenPlant]

    private struct GeoPlant: Identifiable {
        let id: Int
        let latitude: Double
        let longitude: Double
    }

    private let geoPlants: [GeoPlant]
    private let bounds: CoordinateBounds?

    init(plants: [GardenPlant]) {
        self.plants = plants
        let coords = plants.compactMap { plant -> GeoPlant? in
            guard let lat = plant.lat, let lon = plant.lon else { return nil }
            return GeoPlant(id: plant.id, latitude: lat, longitude: lon)
        }
        self.geoPlants = coords
        self.bounds = CoordinateBounds(points: coords)
    }

    var body: some View {
        SectionCard(title: "Carte des individus") {
            if geoPlants.isEmpty {
                SpeciesMapPlaceholderView()
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ZStack(alignment: .topTrailing) {
                    StaticSpeciesMap(points: geoPlants, bounds: bounds)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text("\(geoPlants.count) position\(geoPlants.count > 1 ? "s" : "")")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.primary.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(12)
                }
            }
        }
    }

    private struct CoordinateBounds {
        let minLatitude: Double
        let maxLatitude: Double
        let minLongitude: Double
        let maxLongitude: Double

        init?(points: [GeoPlant]) {
            guard let first = points.first else { return nil }
            var minLat = first.latitude
            var maxLat = first.latitude
            var minLon = first.longitude
            var maxLon = first.longitude

            for point in points.dropFirst() {
                minLat = min(minLat, point.latitude)
                maxLat = max(maxLat, point.latitude)
                minLon = min(minLon, point.longitude)
                maxLon = max(maxLon, point.longitude)
            }

            let latPadding = max((maxLat - minLat) * 0.2, 0.0002)
            let lonPadding = max((maxLon - minLon) * 0.2, 0.0002)

            self.minLatitude = minLat - latPadding
            self.maxLatitude = maxLat + latPadding
            self.minLongitude = minLon - lonPadding
            self.maxLongitude = maxLon + lonPadding
        }
    }

    private struct StaticSpeciesMap: View {
        let points: [GeoPlant]
        let bounds: CoordinateBounds?

        var body: some View {
            GeometryReader { proxy in
                ZStack {
                    LinearGradient(
                        colors: [
                            Color.accentSecondary.opacity(0.08),
                            Color.accentPrimary.opacity(0.14),
                            Color.black.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    SpeciesCoordinateGrid()
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)

                    ForEach(points) { point in
                        SpeciesPulsatingMarker()
                            .position(position(for: point, in: proxy.size))
                    }
                }
            }
        }

        private func position(for point: GeoPlant, in size: CGSize) -> CGPoint {
            guard let bounds else {
                return CGPoint(x: size.width / 2, y: size.height / 2)
            }

            let lonRange = max(bounds.maxLongitude - bounds.minLongitude, 0.000001)
            let latRange = max(bounds.maxLatitude - bounds.minLatitude, 0.000001)
            let xRatio = (point.longitude - bounds.minLongitude) / lonRange
            let yRatio = 1 - ((point.latitude - bounds.minLatitude) / latRange)
            let inset: CGFloat = 20
            let usableWidth = max(size.width - inset * 2, 1)
            let usableHeight = max(size.height - inset * 2, 1)

            return CGPoint(
                x: inset + usableWidth * CGFloat(xRatio),
                y: inset + usableHeight * CGFloat(yRatio)
            )
        }
    }

    private struct SpeciesCoordinateGrid: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let columns = 5
            let rows = 4

            for index in 1..<columns {
                let x = rect.minX + rect.width * CGFloat(index) / CGFloat(columns)
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
            }

            for index in 1..<rows {
                let y = rect.minY + rect.height * CGFloat(index) / CGFloat(rows)
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }

            return path
        }
    }
}

// MARK: - Sous-vues utilitaires

/// Carte générique avec fond arrondi
fileprivate struct SectionCard<Content: View>: View {
    let title: String
    private let contentBuilder: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.contentBuilder = content
    }

    var body: some View {
        CanopyCard(title: title) {
            contentBuilder()
        }
    }
}

/// Ligne “label : valeur”
fileprivate struct KeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
        CanopyInfoLine(label: label, value: value)
    }
}

/// Bloc de texte multi-ligne avec un sous-titre
fileprivate struct TextBlock: View {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(text)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Ligne de tags sous forme de capsules
struct TagCapsuleRow: View {
    let label: String
    let tagsString: String

    var body: some View {
        // 1) Découpe les tags
        let rawTags = tagsString
            .split(whereSeparator: { ",;|".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // 2) Supprime les doublons en conservant l’ordre
        var seen = Set<String>()
        let tags = rawTags.filter { tag in
            let lower = tag.lowercased()
            if seen.contains(lower) {
                return false
            } else {
                seen.insert(lower)
                return true
            }
        }

        guard !tags.isEmpty else {
            return AnyView(EmptyView())
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { t in
                            Text(t)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.accentPrimary.opacity(0.12))
                                )
                                .foregroundColor(.accentPrimary)
                        }
                    }
                }
            }
        )
    }
}

/// Avatar d’espèce : image réseau si possible, sinon initiales
fileprivate struct SpeciesAvatar: View {
    let urlString: String?
    let fallbackText: String

    var body: some View {
        ZStack {
            if let url = resolvedImageURL(from: urlString) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: 80, height: 80)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        let initials = fallbackText
            .split(separator: " ")
            .compactMap { $0.first }
            .prefix(2)
        let title = String(initials)

        return Circle()
            .fill(Color.accentPrimary.opacity(0.15))
            .overlay(
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentPrimary)
            )
    }
}

fileprivate struct SpeciesPulsatingMarker: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentPrimary.opacity(0.28))
                .frame(width: 60, height: 60)
                .scaleEffect(animate ? 1.4 : 0.8)
                .opacity(animate ? 0.0 : 1.0)

            Circle()
                .fill(Color.accentPrimary.opacity(0.9))
                .frame(width: 16, height: 16)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
        }
        .onAppear {
            withAnimation(
                Animation.easeOut(duration: 1.4)
                    .repeatForever(autoreverses: false)
            ) {
                animate = true
            }
        }
    }
}

fileprivate struct SpeciesMapPlaceholderView: View {
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

                Text("Aucun individu de cette espèce n’est géolocalisé")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.9))
            }
        }
    }
}
