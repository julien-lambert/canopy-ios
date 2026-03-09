//
//  HiveDetailView.swift
//  JardinForet
//
//  Created by Julien Lambert on 17/11/2025.
//

import SwiftUI

struct HiveDetailView: View {
    let hiveID: Int
    @EnvironmentObject var store: GardenStore

    var body: some View {
        if let hive = store.fetchHive(id: hiveID) {
            VStack(alignment: .leading, spacing: 12) {
                Text(hive.name)
                    .font(.title)

                if let breed = hive.beeBreed {
                    Text("Race : \(breed)")
                }

                if let year = hive.queenYear {
                    Text("Reine née en \(year)")
                }

                if let origin = hive.origin {
                    Text("Origine de l’essaim : \(origin)")
                }
            }
            .padding()
            .navigationTitle("Détail ruche")
        } else {
            Text("Ruche introuvable")
        }
    }
}
