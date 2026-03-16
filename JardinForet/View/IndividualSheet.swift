import SwiftUI

struct IndividualSheet: View {
    enum Mode {
        case detail(plantID: Int)
        case edit(plantID: Int)
        case create(prefill: PlantFormPrefill? = nil)
    }

    @EnvironmentObject private var store: CanopyStore
    @Environment(\.dismiss) private var dismiss

    @State private var currentMode: Mode

    private let onRequestMove: ((Int) -> Void)?

    init(mode: Mode, onRequestMove: ((Int) -> Void)? = nil) {
        _currentMode = State(initialValue: mode)
        self.onRequestMove = onRequestMove
    }

    var body: some View {
        NavigationStack {
            content
                .background(Color.appBackground.ignoresSafeArea())
                .safeAreaInset(edge: .bottom) {
                    if case .detail(let plantID) = currentMode,
                       store.canMutateSpeciesAndIndividuals,
                       activePlant(for: plantID) != nil {
                        detailActions(for: plantID)
                            .background(.ultraThinMaterial)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
        switch currentMode {
        case .detail(let plantID):
            if let plant = activePlant(for: plantID) {
                PlantDetailView(plant: plant)
            } else {
                missingPlantState
            }

        case .edit(let plantID):
            if let plant = activePlant(for: plantID) {
                PlantFormView(mode: .edit(plant: plant))
            } else {
                missingPlantState
            }

        case .create(let prefill):
            PlantFormView(mode: .create, prefill: prefill)
        }
    }

    private func activePlant(for plantID: Int) -> GardenPlant? {
        store.plants.first(where: { $0.id == plantID })
    }

    private var missingPlantState: some View {
        CanopyEmptyState(
            title: "Individu introuvable",
            message: "La fiche ne peut pas être ouverte pour le moment.",
            systemImage: "leaf.arrow.triangle.circlepath"
        )
        .padding()
    }

    private func detailActions(for plantID: Int) -> some View {
        HStack(spacing: 10) {
            Button("Fermer") {
                dismiss()
            }
            .canopySecondaryActionStyle()

            if onRequestMove != nil {
                Button("Déplacer") {
                    dismiss()
                    onRequestMove?(plantID)
                }
                .canopySecondaryActionStyle()
            }

            Button("Modifier") {
                currentMode = .edit(plantID: plantID)
            }
            .canopyPrimaryActionStyle()
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }
}
