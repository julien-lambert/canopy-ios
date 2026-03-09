import SwiftUI

struct SpeciesListView: View {
    @EnvironmentObject var store: GardenStore
    /// Texte de recherche global (barre latérale macOS). Par défaut vide (iOS).
    var searchQuery: String = ""
    /// Texte de recherche local à la vue (champ `.searchable` intégré).
    @State private var searchText = ""
    @State private var showingCreateSpeciesForm = false

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
        let species: [GardenTaxon] = store.fetchSpeciesBase()

        #if os(macOS)
        let families = groupedFamilies(from: species, query: effectiveSearchText)
        let items = flattenedGridItems(from: families)
        return SpeciesGridMacOS(
            items: items,
            searchText: $searchText
        )
        .navigationTitle("Espèces")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showingCreateSpeciesForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Ajouter une espèce")
            }
        }
        .sheet(isPresented: $showingCreateSpeciesForm) {
            NavigationStack {
                SpeciesFormView()
                    .environmentObject(store)
            }
        }
        #else
        let families = groupedFamilies(from: species, query: effectiveSearchText)
        return SpeciesListContentView(
            families: families,
            searchText: $searchText
        )
        .navigationTitle("Espèces")
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingCreateSpeciesForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Ajouter une espèce")
            }
#else
            ToolbarItem(placement: .automatic) {
                Button {
                    showingCreateSpeciesForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Ajouter une espèce")
            }
#endif
        }
        .sheet(isPresented: $showingCreateSpeciesForm) {
            NavigationStack {
                SpeciesFormView()
                    .environmentObject(store)
            }
        }
        #endif
    }
}

private struct SpeciesListContentView: View {
    let families: [FamilyGroup]
    @Binding var searchText: String

    var body: some View {
        List {
            ForEach(families) { family in
                Section(header: FamilyHeaderView(name: family.name)) {
                    ForEach(family.genera) { genus in
                        GenusBlockView(genus: genus)
                            .listRowBackground(Color.appBackground)
                            .listRowSeparator(.hidden)
                    }
                }
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #else
        .listStyle(.plain)
        #endif
        .background(Color.appBackground)
        .searchable(text: $searchText, prompt: "Rechercher une espèce")
    }

    // Sous-vue pour l'en-tête de famille
    struct FamilyHeaderView: View {
        let name: String

        var body: some View {
            Text(name.uppercased())
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.textSecondary)
                .padding(.vertical, 4)
        }
    }

    // Sous-vue pour le bloc d'un genre (nom de genre + espèces)
    struct GenusBlockView: View {
        let genus: GenusGroup

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                if !genus.name.isEmpty && genus.name != "Genre non renseigné" {
                    Text(genus.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }

                ForEach(genus.species) { sp in
                    NavigationLink {
                        SpeciesDetailView(speciesId: sp.id)
                    } label: {
                        SpeciesRow(species: sp)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Filtrage et groupement

fileprivate func groupedFamilies(from all: [GardenTaxon], query: String) -> [FamilyGroup] {
    let filtered = filterSpecies(all, query: query)
    return groupSpecies(filtered)
}

fileprivate func filterSpecies(_ all: [GardenTaxon], query: String) -> [GardenTaxon] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !q.isEmpty else { return all }

    return all.filter { sp in
        sp.commonName.lowercased().contains(q)
        || sp.latinName.lowercased().contains(q)
        || (sp.family?.lowercased().contains(q) ?? false)
        || (sp.genus?.lowercased().contains(q) ?? false)
        || (sp.tags?.lowercased().contains(q) ?? false)
    }
}

fileprivate func groupSpecies(_ filtered: [GardenTaxon]) -> [FamilyGroup] {
    // Tri logique : famille, genre, latin
    let sorted = filtered.sorted { a, b in
        let fa = a.family ?? "?"
        let fb = b.family ?? "?"
        if fa != fb { return fa < fb }

        let ga = a.genus ?? "?"
        let gb = b.genus ?? "?"
        if ga != gb { return ga < gb }

        return a.latinName < b.latinName
    }

    var families: [FamilyGroup] = []
    var currentFamilyName: String?
    var currentFamily: FamilyGroup?

    func pushCurrentFamily() {
        if let fam = currentFamily {
            families.append(fam)
        }
        currentFamily = nil
    }

    for sp in sorted {
        let famName = (sp.family?.isEmpty == false ? sp.family! : "Famille non renseignée")
        let genusName = (sp.genus?.isEmpty == false ? sp.genus! : "Genre non renseigné")

        // Changement de famille
        if famName != currentFamilyName {
            pushCurrentFamily()
            currentFamilyName = famName
            currentFamily = FamilyGroup(name: famName, genera: [])
        }

        if currentFamily == nil {
            currentFamily = FamilyGroup(name: famName, genera: [])
        }

        var family = currentFamily!

        // Ajout / récupération du bloc de genre
        if let idx = family.genera.firstIndex(where: { $0.name == genusName }) {
            var g = family.genera[idx]
            g.species.append(sp)
            family.genera[idx] = g
        } else {
            let g = GenusGroup(name: genusName, species: [sp])
            family.genera.append(g)
        }

        currentFamily = family
    }

    // pousser la dernière famille
    pushCurrentFamily()
    return families
}

// MARK: - Structures de regroupement

fileprivate struct FamilyGroup: Identifiable {
    let id = UUID()
    let name: String
    var genera: [GenusGroup]
}

fileprivate struct GenusGroup: Identifiable {
    let id = UUID()
    let name: String
    var species: [GardenTaxon]
}

#if os(macOS)

/// Élément aplati pour la grille macOS :
/// chaque carte connaît sa famille, son genre, et sait si elle est
/// la première carte de sa famille / de son genre.
private struct SpeciesGridItem: Identifiable {
    var id: Int { species.id }
    let familyName: String
    let genusName: String
    let species: GardenTaxon
    let isFirstOfFamily: Bool
    let isFirstOfGenus: Bool
}

/// À partir de la hiérarchie Famille → Genre → Espèce,
/// on construit une liste d'items à afficher dans une seule LazyVGrid adaptative.
/// Cela permet de "concaténer" naturellement les familles :
/// si une famille a peu d'espèces, la famille suivante vient occuper
/// la place disponible sur la droite.
private func flattenedGridItems(from families: [FamilyGroup]) -> [SpeciesGridItem] {
    var items: [SpeciesGridItem] = []

    for family in families {
        var isFirstFamilyCard = true

        for genus in family.genera {
            var isFirstCardInGenus = true

            for sp in genus.species {
                let item = SpeciesGridItem(
                    familyName: family.name,
                    genusName: genus.name,
                    species: sp,
                    isFirstOfFamily: isFirstFamilyCard,
                    isFirstOfGenus: isFirstCardInGenus
                )
                items.append(item)

                isFirstFamilyCard = false
                isFirstCardInGenus = false
            }
        }
    }

    return items
}

/// Vue macOS : grille dense par familles et genres, mais en une seule grille adaptative
/// pour éviter les grandes zones vides quand une famille a peu d'espèces.
private struct SpeciesGridMacOS: View {
    let items: [SpeciesGridItem]
    @Binding var searchText: String

    // Cartes un peu plus compactes
    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 260, maximum: 300), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                ForEach(items) { item in
                    NavigationLink {
                        SpeciesDetailView(speciesId: item.species.id)
                    } label: {
                        SpeciesCardMacOS(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .searchable(text: $searchText, prompt: "Rechercher une espèce")
    }
}

/// Carte d'une espèce en version macOS (grid)
/// - Barre verticale à gauche pour marquer le début d'une nouvelle famille
///   (elle descend jusqu'au bas de la carte)
/// - Nom de famille au-dessus de la première carte de la famille
/// - Nom de genre en sous-titre au-dessus de la première carte du genre
/// - Avatar à gauche, cartes compactes et de hauteur homogène
private struct SpeciesCardMacOS: View {
    let item: SpeciesGridItem

    private let headerLineHeight: CGFloat = 18
    private let cardHeight: CGFloat = 150

    private var species: GardenTaxon { item.species }

    private var title: String {
        if !species.commonName.isEmpty && species.commonName != "—" {
            return species.commonName
        }
        return species.latinName
    }

    private var subtitle: String {
        if !species.latinName.isEmpty {
            return species.latinName
        }
        return ""
    }

    private var plantCountText: String {
        switch species.plantCount {
        case 0:  return "0 individu"
        case 1:  return "1 individu"
        default: return "\(species.plantCount) individus"
        }
    }

    private var avatarView: some View {
        AvatarCircle(
            title: title,
            imageURL: species.imageURL
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            // Ligne réservée au nom de la famille (hauteur fixe)
            ZStack(alignment: .leading) {
                if item.isFirstOfFamily {
                    Text(item.familyName.uppercased())
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .tracking(1.1)
                }
            }
            .frame(height: headerLineHeight, alignment: .leading)

            // Ligne réservée au nom du genre (hauteur fixe)
            ZStack(alignment: .leading) {
                if !item.genusName.isEmpty,
                   item.genusName != "Genre non renseigné",
                   item.isFirstOfGenus {
                    Text(item.genusName)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.textSecondary)
                }
            }
            .frame(height: headerLineHeight, alignment: .leading)
            .padding(.bottom, 2)

            // Carte visuelle arrondie et compacte
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.cardContrastBackground)

                HStack(alignment: .center, spacing: 12) {
                    avatarView
                        .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)

                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundColor(.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer(minLength: 4)

                        HStack {
                            Spacer()
                            AppBadge(text: plantCountText, style: .accent)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
                .padding(12)
            }
            .frame(height: cardHeight, alignment: .center)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.cardContrastStroke, lineWidth: 1)
            )
            .shadow(color: Color.cardContrastShadow, radius: 6, x: 0, y: 3)
        }
        // on pousse le contenu vers la droite pour laisser la place au séparateur
        .padding(.leading, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Barre verticale qui couvre toute la hauteur (famille + genre + carte)
        .overlay(alignment: .leading) {
            if item.isFirstOfFamily {
                Rectangle()
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 3)
                    .padding(.vertical, 2)
            }
        }
    }
}

#endif

// MARK: - Vue d'une ligne d'espèce

fileprivate struct SpeciesRow: View {
    let species: GardenTaxon

    private var title: String {
        if !species.commonName.isEmpty && species.commonName != "—" {
            return species.commonName
        }
        return species.latinName
    }

    private var subtitle: String {
        if !species.latinName.isEmpty {
            return species.latinName
        }
        return ""
    }

    private var strataBadge: String? {
        species.strata?.isEmpty == false ? species.strata : nil
    }

    private var plantCountText: String {
        switch species.plantCount {
        case 0:  return "0 individu"
        case 1:  return "1 individu"
        default: return "\(species.plantCount) individus"
        }
    }

    private var avatarView: some View {
        AvatarCircle(
            title: title,
            imageURL: species.imageURL
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatarView
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                        .italic()
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                HStack {
                    if let strata = strataBadge {
                        AppBadge(text: strata, style: .subtle)
                    }

                    Spacer(minLength: 8)

                    AppBadge(text: plantCountText, style: .accent)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            Spacer()
        }
        .padding(10)
        .liquidGlassCard(cornerRadius: 14)
        .padding(.vertical, 3)
    }
}
