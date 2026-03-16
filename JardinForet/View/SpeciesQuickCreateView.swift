import SwiftUI

struct SpeciesQuickCreateView: View {
    @EnvironmentObject private var store: CanopyStore
    @Environment(\.dismiss) private var dismiss

    let onCreated: (Int) -> Void

    @State private var commonName = ""
    @State private var latinName = ""
    @State private var family = ""
    @State private var genus = ""
    @State private var strata = ""
    @State private var imageURL = ""

    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Essentiel") {
                    TextField("Nom vernaculaire", text: $commonName)
#if os(iOS)
                        .textInputAutocapitalization(.words)
#endif

                    TextField("Nom latin", text: $latinName)
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif

                    Text("Le but est de débloquer la saisie terrain. Les autres champs pourront être enrichis ensuite.")
                        .font(.footnote)
                        .foregroundColor(.textSecondary)
                }

                Section("Compléments utiles") {
                    TextField("Famille", text: $family)
                    TextField("Genre", text: $genus)
                    TextField("Strate", text: $strata)
                    TextField("URL image (optionnel)", text: $imageURL)
#if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
#endif
                }
            }
            .navigationTitle("Espèce rapide")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .canopyEditorToolbar(
                saveTitle: "Créer",
                isSaveDisabled: !isValid,
                onCancel: { dismiss() },
                onSave: { save() }
            )
            .alert("Impossible de créer l’espèce", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private var isValid: Bool {
        !trimmed(commonName).isEmpty && !trimmed(latinName).isEmpty
    }

    private func save() {
        let cleanCommonName = trimmed(commonName)
        let cleanLatinName = trimmed(latinName)

        guard !cleanCommonName.isEmpty, !cleanLatinName.isEmpty else {
            errorMessage = "Le nom vernaculaire et le nom latin sont obligatoires."
            showErrorAlert = true
            return
        }

        let normalizedLatin = normalized(cleanLatinName)
        if store.fetchSpeciesBase().contains(where: { normalized($0.latinName) == normalizedLatin }) {
            errorMessage = "Cette espèce existe déjà dans la base locale."
            showErrorAlert = true
            return
        }

        let input = SpeciesWriteInput(
            commonName: cleanCommonName,
            latinName: cleanLatinName,
            family: trimmedOrNil(family),
            genus: trimmedOrNil(genus),
            strata: trimmedOrNil(strata),
            imageURL: trimmedOrNil(imageURL)
        )

        guard let newID = store.createSpecies(input) else {
            errorMessage = "Échec de création locale. Vérifie la synchronisation."
            showErrorAlert = true
            return
        }

        onCreated(newID)
        dismiss()
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
