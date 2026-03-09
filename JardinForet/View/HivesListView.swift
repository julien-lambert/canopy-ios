//
//  HivesListView.swift
//  JardinForet
//
//  Created by Julien Lambert on 17/11/2025.
//

import SwiftUI

struct HivesListView: View {
    @EnvironmentObject var store: GardenStore

    var body: some View {
        List {
            ForEach(store.fetchHives(), id: \.id) { hive in
                NavigationLink(destination: HiveDetailView(hiveID: hive.id)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hive.name)
                            .font(.headline)

                        if let breed = hive.beeBreed, !breed.isEmpty {
                            Text("Abeilles : \(breed)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        if let year = hive.queenYear {
                            Text("Reine : \(year)")
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .navigationTitle("Ruches")
    }
}
