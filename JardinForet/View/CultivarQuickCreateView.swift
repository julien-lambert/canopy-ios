import SwiftUI

struct CultivarQuickCreateView: View {
    @EnvironmentObject private var store: CanopyStore
    @Environment(\.dismiss) private var dismiss

    let species: GardenTaxon
    let onCreated: (String) -> Void

    @State private var name = ""
    @State private var notes = ""

    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Cultivar") {
                    Text(species.commonName)
                        .font(.headline)
                    if !species.latinName.isEmpty {
                        Text(species.latinName)
                            .font(.subheadline)
                            .italic()
                            .foregroundColor(.textSecondary)
                    }

                    TextField("Nom du cultivar", text: $name)
#if os(iOS)
                        .textInputAutocapitalization(.words)
#endif

                    TextField("Note courte", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Cultivar rapide")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .canopyEditorToolbar(
                saveTitle: "Créer",
                isSaveDisabled: trimmed(name).isEmpty,
                onCancel: { dismiss() },
                onSave: { save() }
            )
            .alert("Impossible de créer le cultivar", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func save() {
        let cleanName = trimmed(name)
        guard !cleanName.isEmpty else {
            errorMessage = "Le nom du cultivar est obligatoire."
            showErrorAlert = true
            return
        }

        if isDuplicateCultivarName(cleanName) {
            errorMessage = "Ce cultivar existe déjà pour cette espèce."
            showErrorAlert = true
            return
        }

        let input = CultivarWriteInput(
            name: cleanName,
            notes: trimmedOrNil(notes)
        )

        guard let remoteID = store.createCultivar(speciesId: species.id, input: input) else {
            errorMessage = "Échec de création locale. Vérifie la synchronisation."
            showErrorAlert = true
            return
        }

        onCreated(remoteID)
        dismiss()
    }

    private func isDuplicateCultivarName(_ rawName: String) -> Bool {
        guard let detail = store.fetchSpeciesDetail(speciesId: Int32(species.id)) else {
            return false
        }
        let candidate = normalized(rawName)
        return detail.cultivars.contains { cultivar in
            normalized(cultivar.varietyName) == candidate
        }
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let clean = trimmed(value)
        return clean.isEmpty ? nil : clean
    }

    private func normalized(_ value: String) -> String {
        trimmed(value)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}
