import SwiftUI

struct PlantsListView: View {
    @EnvironmentObject var store: CanopyStore
    /// Texte de recherche global (sidebar macOS). Par défaut vide pour iOS.
    var searchQuery: String = ""
    /// Texte de recherche local à la vue (champ `.searchable` intégré).
    @State private var searchText = ""
    @State private var showingCreatePlantForm = false

    /// Texte de recherche effectif :
    /// - la recherche locale (champ dans la vue) a priorité
    /// - la recherche globale (barre latérale macOS) est utilisée si le champ local est vide
    private var effectiveSearchText: String {
        let local = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !local.isEmpty {
            return local
        }
        return searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        #if os(macOS)
        macOSBody
        #else
        iOSBody
        #endif
    }

    // MARK: - iOS : liste classique optimisée pour écran étroit

    @ViewBuilder
    private var iOSBody: some View {
        Group {
            if groupedPlants.isEmpty {
                CanopyScreen {
                    CanopyEmptyState(
                        title: "Aucun individu trouvé",
                        message: effectiveSearchText.isEmpty
                            ? "Ajoute un individu pour commencer à documenter le site."
                            : "Aucun individu ne correspond à cette recherche.",
                        systemImage: "leaf.circle"
                    )
                }
            } else {
                List {
                    ForEach(groupedPlants, id: \.strata) { section in
                        Section(header: strataHeader(section.strata)) {
                            ForEach(section.plants) { plant in
                                NavigationLink(
                                    destination: PlantDetailView(plant: plant)
                                ) {
                                    PlantRow(plant: plant)
                                }
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .background(Color.appBackground)
            }
        }
        .searchable(text: $searchText, prompt: "Rechercher un plant")
        .navigationTitle("Plantes")
        .toolbar {
            if store.canMutateSpeciesAndIndividuals {
#if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingCreatePlantForm = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Ajouter un individu")
                }
#else
                ToolbarItem(placement: .automatic) {
                    Button {
                        showingCreatePlantForm = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Ajouter un individu")
                }
#endif
            }
        }
        .sheet(isPresented: $showingCreatePlantForm) {
            NavigationStack {
                PlantFormView(mode: .create)
                    .environmentObject(store)
            }
        }
    }

    // MARK: - macOS : grille “album” (cartes)

    @ViewBuilder
    private var macOSBody: some View {
        Group {
            if groupedPlants.isEmpty {
                CanopyScreen {
                    CanopyEmptyState(
                        title: "Aucun individu trouvé",
                        message: effectiveSearchText.isEmpty
                            ? "Ajoute un individu pour peupler la carte et les fiches."
                            : "Aucun individu ne correspond à cette recherche.",
                        systemImage: "leaf.circle"
                    )
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(groupedPlants, id: \.strata) { section in
                            VStack(alignment: .leading, spacing: 12) {
                                strataHeader(section.strata)
                                    .padding(.horizontal, 4)

                                LazyVGrid(columns: macGridColumns, alignment: .leading, spacing: 16) {
                                    ForEach(section.plants) { plant in
                                        NavigationLink(destination: PlantDetailView(plant: plant)) {
                                            PlantCard(plant: plant)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 16)
                }
            }
        }
        .background(Color.appBackground)
        .searchable(text: $searchText, prompt: "Rechercher un plant")
        .navigationTitle("Plantes")
        .toolbar {
            if store.canMutateSpeciesAndIndividuals {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showingCreatePlantForm = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Ajouter un individu")
                }
            }
        }
        .sheet(isPresented: $showingCreatePlantForm) {
            NavigationStack {
                PlantFormView(mode: .create)
                    .environmentObject(store)
            }
        }
    }

    /// Colonnes adaptatives pour une grille confortable sur grand écran.
    private var macGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 260), spacing: 16, alignment: .top)]
    }

    private var filteredPlants: [GardenPlant] {
        let all = store.plants
        let q = effectiveSearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        // Si aucune recherche : on retourne tout
        guard !q.isEmpty else { return all }

        // 1) Cas particulier : la chaîne correspond exactement à une strate existante
        //    (utilisé par le menu latéral macOS quand tu cliques sur une strate)
        let availableStrata = Set(
            all.compactMap { plant in
                plant.strata?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }
        )

        if availableStrata.contains(q) {
            // On filtre alors uniquement sur cette strate
            return all.filter { plant in
                plant.strata?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == q
            }
        }

        // 2) Sinon : recherche textuelle classique sur les champs usuels
        return all.filter { p in
            p.commonName.lowercased().contains(q)
            || (p.varietyName?.lowercased().contains(q) ?? false)
            || (p.label?.lowercased().contains(q) ?? false)
            || p.latinName.lowercased().contains(q)
        }
    }

    /// Regroupe les plants par strate (canopée, sous-étage, arbuste, etc.)
    private typealias StrataSection = (strata: String, plants: [GardenPlant])

    private var groupedPlants: [StrataSection] {
        let all = filteredPlants

        // On normalise la valeur de strate
        let grouped = Dictionary(grouping: all) { plant in
            let raw = plant.strata?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return raw.isEmpty ? "Autre" : raw
        }

        // Ordre des strates, proche de ce que tu utilises déjà
        let order = [
            "canopée",
            "sous-étage",
            "arbuste",
            "liane",
            "couvre-sol",
            "autre"
        ]

        return grouped
            .map { (strata: $0.key, plants: $0.value) }
            .sorted { a, b in
                let ia = order.firstIndex { $0.caseInsensitiveCompare(a.strata) == .orderedSame } ?? order.count
                let ib = order.firstIndex { $0.caseInsensitiveCompare(b.strata) == .orderedSame } ?? order.count
                if ia != ib { return ia < ib }
                return a.strata.lowercased() < b.strata.lowercased()
            }
    }
}

private func strataHeader(_ name: String) -> some View {
    CanopySectionHeader(title: name.uppercased())
        .padding(.vertical, 4)
}

private struct PlantRow: View {
    let plant: GardenPlant

    // Titre = nom commun + éventuel cultivar
    private var title: String {
        if let variety = plant.varietyName, !variety.isEmpty {
            return "\(plant.commonName) – \(variety)"
        }
        return plant.commonName
    }

    // Sous-titre = nom latin (comme pour les espèces)
    private var subtitle: String {
        plant.latinName.isEmpty ? "" : plant.latinName
    }

    var body: some View {
        CanopyCard {
            HStack(alignment: .top, spacing: 12) {
                avatar

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        Text(title)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .italic()
                    }

                    HStack {
                        if let zone = plant.zone, !zone.isEmpty {
                            AppBadge(text: "Zone \(zone)", style: .subtle)
                        }

                        if let ilotCode = plant.siteIlotCode, !ilotCode.isEmpty {
                            AppBadge(text: "Îlot \(ilotCode)", style: .subtle)
                        }

                        Spacer(minLength: 8)

                        if let label = plant.label, !label.isEmpty {
                            AppBadge(text: label, style: .accent)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }

                Spacer()
            }
        }
        .padding(.vertical, 3)
    }

    // Même helper que côté espèces
    private func initials(from name: String) -> String {
        let comps = name.split(separator: " ")
        let letters = comps.prefix(2).compactMap { $0.first }
        return String(letters)
    }

    @ViewBuilder
    private var avatar: some View {
        AvatarCircle(
            title: plant.commonName,
            imageURL: plant.speciesImageURL,
            localImageURL: plant.imageLocal
        )
    }
}

// MARK: - Carte pour macOS

private struct PlantCard: View {
    let plant: GardenPlant

    private var title: String {
        if let variety = plant.varietyName, !variety.isEmpty {
            return "\(plant.commonName) – \(variety)"
        }
        return plant.commonName
    }

    private var subtitle: String {
        plant.latinName.isEmpty ? "" : plant.latinName
    }

    var body: some View {
        CanopyCard {
            VStack(alignment: .leading, spacing: 10) {
                AvatarCircle(
                    title: plant.commonName,
                    imageURL: plant.speciesImageURL,
                    localImageURL: plant.imageLocal
                )
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: CanopyCornerRadius.md))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .italic()
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                HStack(spacing: 8) {
                    if let zone = plant.zone, !zone.isEmpty {
                        AppBadge(text: "Zone \(zone)", style: .subtle)
                            .frame(maxWidth: 120, alignment: .leading)
                    }

                    if let ilotCode = plant.siteIlotCode, !ilotCode.isEmpty {
                        AppBadge(text: "Îlot \(ilotCode)", style: .subtle)
                            .frame(maxWidth: 120, alignment: .leading)
                    }

                    Spacer(minLength: 4)

                    if let label = plant.label, !label.isEmpty {
                        AppBadge(text: label, style: .accent)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
    }
}
