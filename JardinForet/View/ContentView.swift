import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("Accueil", systemImage: "house")
            }

            NavigationStack {
                PlantsListView()
            }
            .tabItem {
                Label("Individus", systemImage: "leaf")
            }

            NavigationStack {
                SpeciesListView()
            }
            .tabItem {
                Label("Espèces", systemImage: "tree")
            }
        }
        .tint(.accentPrimary)
    }
}

#Preview {
    // Préview avec store local
    ContentView()
        .environmentObject(CanopyStore())
}
