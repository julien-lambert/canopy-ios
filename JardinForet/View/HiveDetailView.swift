import SwiftUI

struct HiveDetailView: View {
    let hiveID: Int

    var body: some View {
        CanopyScreen {
            CanopyCard(title: "Fiche ruche indisponible", systemImage: "shippingbox") {
                Text("La fiche ruche détaillée n’est plus reliée à l’ancienne base locale.")
                    .font(.body)
                Text("Identifiant demandé: \(hiveID)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            CanopyCard(title: "Suite prévue", systemImage: "arrow.triangle.2.circlepath") {
                Text("Le module apiculture sera réintroduit quand son schéma local Canopy et sa synchronisation Supabase seront définis proprement.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("Détail ruche")
    }
}
