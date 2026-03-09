import SwiftUI

@main
struct JardinForetApp: App {
    private enum IOSTab: Hashable {
        case home
        case plants
        case species
        case map
        case hives
        case colonies
        case identifier
        case vr
    }

    @StateObject private var store: GardenStore
    @StateObject var locationManager = LocationManager()
    @State private var selectedTab: IOSTab = .home

    init() {
        _store = StateObject(wrappedValue: GardenStore())
    }

    var body: some Scene {
        #if os(iOS)
        WindowGroup {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    HomeView()
                }
                .tag(IOSTab.home)
                .tabItem {
                    Label("Accueil", systemImage: "house")
                }

                NavigationStack {
                    PlantsListView()
                }
                .tag(IOSTab.plants)
                .tabItem {
                    Label("Plantes", systemImage: "leaf")
                }

                NavigationStack {
                    SpeciesListView()
                }
                .tag(IOSTab.species)
                .tabItem {
                    Label("Espèces", systemImage: "tree")
                }

                NavigationStack {
                    if selectedTab == .map {
                        GardenMapView()
                    } else {
                        Color.clear
                    }
                }
                .tag(IOSTab.map)
                .tabItem {
                    Label("Carte", systemImage: "map")
                }

                NavigationStack {
                    HivesListView()
                }
                .tag(IOSTab.hives)
                .tabItem {
                    Label("Ruches", systemImage: "hexagon")
                }

                NavigationStack {
                    ColoniesListView()
                }
                .tag(IOSTab.colonies)
                .tabItem {
                    Label("Colonies", systemImage: "square.grid.2x2")
                }

                NavigationStack {
                    PlantIdentifierView()
                }
                .tag(IOSTab.identifier)
                .tabItem {
                    Label("Identifier", systemImage: "camera.viewfinder")
                }

                NavigationStack {
                    if selectedTab == .vr {
                        VRView()
                    } else {
                        Color.clear
                    }
                }
                .tag(IOSTab.vr)
                .tabItem {
                    Label("VR", systemImage: "cube")
                }
            }
            .environmentObject(store)
            .environmentObject(locationManager)
        }
        #elseif os(macOS)
        WindowGroup {
            JardinForetMacRootView()
                .environmentObject(store)
                .environmentObject(locationManager)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .windowToolbarStyle(UnifiedCompactWindowToolbarStyle())
        .defaultSize(CGSize(width: 1400, height: 900))
        #endif
    }
}

#if os(macOS)

enum SidebarItem: Hashable {
    case home
    case plants
    case plantsStrata(String)      // plant strata name
    case map
    case hives
    case colonies
    case identifier
    case speciesAll
    case speciesFamily(String)        // family name
    case speciesGenus(String, String) // family name, genus name
}

struct JardinForetMacRootView: View {
    @EnvironmentObject var store: GardenStore
    @EnvironmentObject var locationManager: LocationManager

    @State private var selectedSidebar: SidebarItem? = .home
    @State private var sidebarSearchText: String = ""
    @State private var isSpeciesExpanded: Bool = false
    @State private var isPlantsExpanded: Bool = false

    var body: some View {
        NavigationSplitView {
            sidebarView()
        } detail: {
            detailView
        }
        .onChange(of: selectedSidebar) { _, newValue in
            switch newValue {
            case .speciesFamily(let familyName):
                sidebarSearchText = familyName
            case .speciesGenus(_, let genusName):
                sidebarSearchText = genusName
            case .speciesAll:
                break
            case .plantsStrata(let strataName):
                sidebarSearchText = strataName
            default:
                break
            }
        }
    }

    @ViewBuilder
    private func sidebarView() -> some View {
        let stats = store.fetchStats()
        let groups = SpeciesSidebarFamilyGroup.build(from: store.fetchSpeciesBase())

        // Comptage des plants par strate (clé normalisée en lowercased)
        let strataCounts: [String: Int] = {
            let plants = store.plants
            let grouped = Dictionary(grouping: plants) { plant in
                plant.strata?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() ?? ""
            }
            return grouped.mapValues { $0.count }
        }()

        List(selection: $selectedSidebar) {
            // Groupe 1 : Jardin & carte
            Section("Jardin & carte") {
                HStack {
                    Label("Accueil", systemImage: "house")
                    Spacer()
                }
                .tag(SidebarItem.home)

                HStack {
                    Label("Carte", systemImage: "map")
                    Spacer()
                }
                .tag(SidebarItem.map)
            }

            // Groupe 2 : Végétal
            Section("Botanique") {
                // Plantes + strates
                DisclosureGroup(isExpanded: $isPlantsExpanded) {
                    let strataItems: [String] = [
                        "Canopée",
                        "Sous-étage",
                        "Arbuste",
                        "Herbacée",
                        "Couvre-sol",
                        "Lianes",
                    ]

                    ForEach(strataItems, id: \.self) { strata in
                        let key = strata
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .lowercased()

                        HStack {
                            Text(strata)
                                .font(.caption)
                            Spacer()
                            Text("\(strataCounts[key, default: 0])")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 16)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedSidebar = .plantsStrata(strata)
                        }
                        .background(
                            Group {
                                if case .plantsStrata(let name) = selectedSidebar, name == strata {
                                    Color.accentColor.opacity(0.15)
                                } else {
                                    Color.clear
                                }
                            }
                        )
                    }
                } label: {
                    HStack {
                        Label("Plantes", systemImage: "leaf")
                        Spacer()
                        Text("\(stats.plantCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedSidebar = .plants
                        sidebarSearchText = ""
                    }
                    .background(
                        Group {
                            if selectedSidebar == .plants {
                                Color.accentColor.opacity(0.15)
                            } else {
                                Color.clear
                            }
                        }
                    )
                }

                // Espèces avec familles / genres
                DisclosureGroup(isExpanded: $isSpeciesExpanded) {
                    ForEach(groups) { family in
                        VStack(alignment: .leading, spacing: 4) {
                            // Famille
                            HStack {
                                Text(family.familyName.uppercased())
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .padding(.leading, 4)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedSidebar = .speciesFamily(family.familyName)
                            }
                            .background(
                                Group {
                                    if case .speciesFamily(let name) = selectedSidebar, name == family.familyName {
                                        Color.accentColor.opacity(0.15)
                                    } else {
                                        Color.clear
                                    }
                                }
                            )

                            // Genres
                            ForEach(family.genera) { genus in
                                HStack {
                                    Text(genus.genusName)
                                        .font(.caption)
                                    Spacer()
                                    Text("\(genus.speciesCount)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.leading, 16)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedSidebar = .speciesGenus(family.familyName, genus.genusName)
                                }
                                .background(
                                    Group {
                                        if case .speciesGenus(let famName, let genName) = selectedSidebar,
                                           famName == family.familyName,
                                           genName == genus.genusName {
                                            Color.accentColor.opacity(0.15)
                                        } else {
                                            Color.clear
                                        }
                                    }
                                )
                            }
                        }
                    }
                } label: {
                    HStack {
                        Label("Espèces", systemImage: "tree")
                        Spacer()
                        Text("\(stats.speciesCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedSidebar = .speciesAll
                        sidebarSearchText = ""
                    }
                    .background(
                        Group {
                            if selectedSidebar == .speciesAll {
                                Color.accentColor.opacity(0.15)
                            } else {
                                Color.clear
                            }
                        }
                    )
                }
            }

            // Groupe 3 : Apiculture
            Section("Apiculture") {
                HStack {
                    Label("Ruches", systemImage: "hexagon")
                    Spacer()
                    Text("\(stats.hiveCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .tag(SidebarItem.hives)

                HStack {
                    Label("Colonies", systemImage: "square.grid.2x2")
                    Spacer()
                    Text("\(stats.colonyCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .tag(SidebarItem.colonies)
            }

            Section("Outils") {
                HStack {
                    Label("Identifier", systemImage: "camera.viewfinder")
                    Spacer()
                }
                .tag(SidebarItem.identifier)
            }
        }
        .listStyle(.sidebar)
        .searchable(
            text: $sidebarSearchText,
            placement: .sidebar,
            prompt: "Rechercher une plante ou une espèce"
        )
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSidebar ?? .home {
        case .home:
            NavigationStack { HomeView() }
        case .plants:
            NavigationStack { PlantsListView(searchQuery: sidebarSearchText) }
        case .plantsStrata(let strataName):
            NavigationStack { PlantsListView(searchQuery: strataName) }
        case .speciesAll:
            NavigationStack { SpeciesListView(searchQuery: sidebarSearchText) }
        case .speciesFamily(let familyName):
            NavigationStack { SpeciesListView(searchQuery: familyName) }
        case .speciesGenus(_, let genusName):
            NavigationStack { SpeciesListView(searchQuery: genusName) }
        case .map:
            NavigationStack { GardenMapView() }
        case .hives:
            NavigationStack { HivesListView() }
        case .colonies:
            NavigationStack { ColoniesListView() }
        case .identifier:
            NavigationStack { PlantIdentifierView() }
        }
    }
}

private struct SpeciesSidebarFamilyGroup: Identifiable {
    let id = UUID()
    let familyName: String
    var genera: [SpeciesSidebarGenusGroup]

    static func build(from all: [GardenTaxon]) -> [SpeciesSidebarFamilyGroup] {
        // Tri par famille, puis genre, puis nom latin
        let sorted = all.sorted { a, b in
            let fa = a.family ?? "?"
            let fb = b.family ?? "?"
            if fa != fb { return fa < fb }

            let ga = a.genus ?? "?"
            let gb = b.genus ?? "?"
            if ga != gb { return ga < gb }

            return a.latinName < b.latinName
        }

        var result: [SpeciesSidebarFamilyGroup] = []
        var currentFamilyName: String?
        var currentFamily: SpeciesSidebarFamilyGroup?

        func pushCurrentFamily() {
            if let fam = currentFamily {
                result.append(fam)
            }
            currentFamily = nil
        }

        for sp in sorted {
            let famName = (sp.family?.isEmpty == false ? sp.family! : "Famille non renseignée")
            let genusName = (sp.genus?.isEmpty == false ? sp.genus! : "Genre non renseigné")

            if famName != currentFamilyName {
                pushCurrentFamily()
                currentFamilyName = famName
                currentFamily = SpeciesSidebarFamilyGroup(familyName: famName, genera: [])
            }

            if currentFamily == nil {
                currentFamily = SpeciesSidebarFamilyGroup(familyName: famName, genera: [])
            }

            var family = currentFamily!

            if let idx = family.genera.firstIndex(where: { $0.genusName == genusName }) {
                var genus = family.genera[idx]
                genus.speciesCount += 1
                family.genera[idx] = genus
            } else {
                let genus = SpeciesSidebarGenusGroup(genusName: genusName, speciesCount: 1)
                family.genera.append(genus)
            }

            currentFamily = family
        }

        pushCurrentFamily()
        return result
    }
}

private struct SpeciesSidebarGenusGroup: Identifiable {
    let id = UUID()
    let genusName: String
    var speciesCount: Int
}

#endif
