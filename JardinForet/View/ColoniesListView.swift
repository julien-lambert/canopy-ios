//
//  Untitled.swift
//  JardinForet
//
//  Created by Julien Lambert on 27/11/2025.
//

import SwiftUI

struct ColoniesListView: View {
    var body: some View {
        CanopyScreen {
            CanopyCard(title: "Colonies en attente", systemImage: "wrench.and.screwdriver") {
                Text("Les colonies seront réintroduites une fois le module apiculture aligné sur Canopy, sans retour au stockage legacy.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("Colonies")
    }
}

#Preview {
    ColoniesListView()
}
