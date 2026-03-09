import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {

            // Onglet Accueil
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("Accueil", systemImage: "house")
            }

            // Onglet Plantes
            NavigationStack {
                PlantsListView()
            }
            .tabItem {
                Label("Plantes", systemImage: "leaf")
            }
            
            // Onglet Especes
            NavigationStack {
                SpeciesListView()
            }
            .tabItem {
                Label("Espece", systemImage: "tree")
            }
        }
        .accentColor(.accentPrimary) // ta couleur si tu veux
    }
}

#Preview {
    // Préview avec store local
    ContentView()
        .environmentObject(GardenStore())
}
