import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Jardin", systemImage: "leaf")
                }

            PlantsListView()
                .tabItem {
                    Label("Plants", systemImage: "tree")
                }

            // Plus tard : SpeciesListView, HivesView, etc.
        }
    }
}
