import SwiftUI

struct HivesListView: View {
    var body: some View {
        CanopyScreen {
            CanopyCard(title: "Module apiculture en migration", systemImage: "wrench.and.screwdriver") {
                Text("Les données ruches ne reposent plus sur l’ancienne base locale. La projection Canopy dédiée n’est pas encore en place, donc le module reste momentanément en lecture indisponible.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CanopyCard(title: "État", systemImage: "shippingbox") {
                VStack(alignment: .leading, spacing: CanopySpacing.sm) {
                    CanopyInfoLine(label: "Backend", value: "Module en refonte")
                    CanopyInfoLine(label: "Base locale", value: "Canopy uniquement")
                    CanopyInfoLine(label: "Module", value: "À remigrer proprement")
                }
            }
        }
        .navigationTitle("Ruches")
    }
}
