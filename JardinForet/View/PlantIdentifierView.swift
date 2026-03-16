import SwiftUI
import PhotosUI

struct PlantIdentifierView: View {
    private struct PhotoObservation: Identifiable {
        let id = UUID()
        let data: Data
        var organ: PlantNetService.Organ
    }

    @EnvironmentObject private var store: CanopyStore
    @EnvironmentObject private var locationManager: LocationManager

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var observations: [PhotoObservation] = []
    @State private var isShowingCamera = false

    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var response: PlantNetService.IdentifyResponse?
    @State private var selectedResultID: UUID?

    @State private var addGeolocatedPlant = true
    @State private var plantLabel = ""

    private let service = PlantNetService()

    var body: some View {
        CanopyScreen {
            VStack(alignment: .leading, spacing: CanopySpacing.md) {
                CanopySectionHeader(
                    title: "Identification PlantNet",
                    subtitle: "Ajoute plusieurs photos, précise l’organe pour chaque image, puis sélectionne une proposition à importer."
                )
                photosCard
                actionsCard
                resultCard
                importCard
            }
        }
        .navigationTitle("Identifier")
        .task(id: selectedPhotoItems) {
            await loadSelectedPhotos()
        }
        #if os(iOS)
        .sheet(isPresented: $isShowingCamera) {
            CameraImagePicker { imageData in
                appendObservation(imageData)
            }
        }
        #endif
    }

    private var photosCard: some View {
        CanopyCard(title: "Photos", systemImage: "camera.macro") {
            if observations.isEmpty {
                CanopyEmptyState(
                    title: "Aucune photo",
                    message: "Ajoute une ou plusieurs photos pour lancer l’identification.",
                    systemImage: "camera.macro"
                )
            } else {
                ForEach($observations) { $observation in
                    VStack(alignment: .leading, spacing: CanopySpacing.xs) {
                        if let image = makeImage(from: observation.data) {
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .frame(maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: CanopyCornerRadius.sm))
                        }

                        HStack {
                            Picker("Organe", selection: $observation.organ) {
                                ForEach(PlantNetService.Organ.allCases) { organ in
                                    Text(organ.label).tag(organ)
                                }
                            }
                            .pickerStyle(.menu)

                            Spacer()

                            Button(role: .destructive) {
                                observations.removeAll { $0.id == observation.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                    .padding(CanopySpacing.sm)
                    .background(Color.listRowBackground, in: RoundedRectangle(cornerRadius: CanopyCornerRadius.sm))
                }
            }
        }
    }

    private var actionsCard: some View {
        CanopyCard(title: "Action", systemImage: "sparkles") {
            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 10, matching: .images) {
                    Label("Bibliothèque", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .canopySecondaryActionStyle()

                #if os(iOS)
                Button {
                    isShowingCamera = true
                } label: {
                    Label("Caméra", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .canopySecondaryActionStyle()
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                #endif
            }

            Button {
                Task { await identifyPlant() }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                    Text(isLoading ? "Identification en cours..." : "Identifier avec PlantNet")
                }
                .frame(maxWidth: .infinity)
            }
            .canopyPrimaryActionStyle()
            .disabled(isLoading || observations.isEmpty)

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let successMessage, !successMessage.isEmpty {
                Text(successMessage)
                    .font(.footnote)
                    .foregroundColor(.green)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var resultCard: some View {
        if let response {
            CanopyCard(title: "Propositions", systemImage: "leaf") {
                ForEach(response.results.prefix(5)) { item in
                    Button {
                        selectedResultID = item.id
                        successMessage = nil
                    } label: {
                        HStack(alignment: .top, spacing: CanopySpacing.sm) {
                            referencePreview(for: item)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.species.scientificNameWithoutAuthor ?? item.species.scientificName ?? "Nom scientifique inconnu")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)

                                if let common = item.species.commonNames?.first, !common.isEmpty {
                                    Text(common)
                                        .font(.subheadline)
                                        .foregroundColor(.textSecondary)
                                }

                                HStack(spacing: 8) {
                                    if let family = item.species.family?.scientificNameWithoutAuthor ??
                                        item.species.family?.scientificName {
                                        AppBadge(text: family, style: .subtle)
                                    }

                                    Text(String(format: "Confiance %.0f%%", item.score * 100))
                                        .font(.caption)
                                        .foregroundColor(.textSecondary)
                                }

                                Text("Photo de reference PlantNet")
                                    .font(.caption2)
                                    .foregroundColor(.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: CanopyCornerRadius.sm)
                                .fill(Color.listRowBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: CanopyCornerRadius.sm)
                                        .stroke(item.id == selectedResultID ? Color.accentPrimary : Color.clear, lineWidth: 1.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var importCard: some View {
        if let selected = selectedResult {
            CanopyCard(title: "Importer dans ma base", systemImage: "square.and.arrow.down") {
                if referenceImageURL(for: selected) != nil {
                    VStack(alignment: .leading, spacing: CanopySpacing.xs) {
                        referencePreview(for: selected, width: nil, height: 190)

                        Text("Verifie que la photo de reference ressemble bien a ta plante avant d'importer.")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                }

                Text("Espèce: \(selected.species.scientificNameWithoutAuthor ?? selected.species.scientificName ?? "inconnue")")
                    .font(.subheadline)

                Toggle("Créer aussi un individu géolocalisé", isOn: $addGeolocatedPlant)

                if addGeolocatedPlant {
                    TextField("Étiquette individu (optionnel)", text: $plantLabel)
                        .textFieldStyle(.roundedBorder)

                    if let location = locationManager.location {
                        Text(String(format: "GPS: %.6f, %.6f", location.coordinate.latitude, location.coordinate.longitude))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    } else {
                        Text("GPS indisponible. Autorise la localisation pour créer l’individu automatiquement.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                Button {
                    Task { await importSelectedResult() }
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(.circular)
                        }
                        Text(isSaving ? "Import en cours..." : "Ajouter à mes espèces")
                    }
                    .frame(maxWidth: .infinity)
                }
                .canopyPrimaryActionStyle()
                .disabled(isSaving)
            }
        }
    }

    private var selectedResult: PlantNetService.ResultItem? {
        guard let response, let selectedResultID else { return nil }
        return response.results.first(where: { $0.id == selectedResultID })
    }

    private func loadSelectedPhotos() async {
        guard !selectedPhotoItems.isEmpty else { return }

        for item in selectedPhotoItems {
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    appendObservation(data)
                }
            } catch {
                errorMessage = "Impossible de charger une des photos."
            }
        }

        selectedPhotoItems = []
    }

    private func appendObservation(_ data: Data) {
        observations.append(PhotoObservation(data: data, organ: .auto))
        errorMessage = nil
        successMessage = nil
        response = nil
        selectedResultID = nil
    }

    private func identifyPlant() async {
        guard !observations.isEmpty else {
            errorMessage = "Ajoute au moins une photo."
            return
        }

        isLoading = true
        errorMessage = nil
        successMessage = nil
        response = nil
        selectedResultID = nil
        defer { isLoading = false }

        do {
            let payload = observations.map { PlantNetService.Observation(imageData: $0.data, organ: $0.organ) }
            let res = try await service.identify(observations: payload)
            response = res
            selectedResultID = res.results.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importSelectedResult() async {
        guard let selected = selectedResult else {
            errorMessage = "Choisis une proposition à importer."
            return
        }

        let latinName = (selected.species.scientificNameWithoutAuthor ?? selected.species.scientificName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !latinName.isEmpty else {
            errorMessage = "Nom latin manquant dans la proposition choisie."
            return
        }

        isSaving = true
        defer { isSaving = false }

        let commonName = selected.species.commonNames?.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCommon = (commonName?.isEmpty == false) ? commonName! : latinName
        let family = selected.species.family?.scientificNameWithoutAuthor ?? selected.species.family?.scientificName
        let genus = selected.species.genus?.scientificNameWithoutAuthor ?? selected.species.genus?.scientificName
        let imageURL = normalizedURL(selected.bestImageURL)
        let importNote = "Import PlantNet (confiance \(Int(selected.score * 100))%)"

        let existingSpecies = store.species.first { s in
            !s.deleted && s.latinName.caseInsensitiveCompare(latinName) == .orderedSame
        }

        let speciesId: Int
        if let existingSpecies {
            speciesId = existingSpecies.id
            let existingImage = normalizedURL(existingSpecies.imageURL)
            if existingImage == nil, let imageURL {
                store.updateSpeciesCommonFields(
                    latinName: existingSpecies.latinName,
                    speciesId: existingSpecies.id,
                    with: SpeciesCommonWriteInput(
                        commonName: existingSpecies.commonName,
                        family: existingSpecies.family,
                        genus: existingSpecies.genus,
                        strata: existingSpecies.strata,
                        tags: existingSpecies.tags,
                        notes: existingSpecies.notes,
                        imageURL: imageURL,
                        origin: existingSpecies.origin,
                        plantType: existingSpecies.plantType,
                        morphology: existingSpecies.morphology,
                        culture: existingSpecies.culture,
                        uses: existingSpecies.uses,
                        melliferousLevel: existingSpecies.melliferousLevel,
                        ornamentalInterest: existingSpecies.ornamentalInterest,
                        lifespanMin: existingSpecies.lifespanMin,
                        lifespanMax: existingSpecies.lifespanMax,
                        heightMin: existingSpecies.heightMin,
                        heightMax: existingSpecies.heightMax,
                        envergureMin: existingSpecies.spreadMin,
                        envergureMax: existingSpecies.spreadMax,
                        floweringPeriod: existingSpecies.floweringPeriod,
                        fruitingPeriod: existingSpecies.fruitingPeriod
                    )
                )
            }
        } else {
            guard let newId = store.createSpecies(
                SpeciesWriteInput(
                    commonName: resolvedCommon,
                    varietyName: nil,
                    latinName: latinName,
                    family: family,
                    genus: genus,
                    strata: nil,
                    tags: "plantnet,identification",
                    notes: importNote,
                    imageURL: imageURL,
                    origin: nil,
                    plantType: nil,
                    morphology: nil,
                    culture: nil,
                    uses: nil,
                    melliferousLevel: nil,
                    ornamentalInterest: nil,
                    lifespanMin: nil,
                    lifespanMax: nil,
                    heightMin: nil,
                    heightMax: nil,
                    envergureMin: nil,
                    envergureMax: nil,
                    floweringPeriod: nil,
                    fruitingPeriod: nil,
                    varietyNotes: nil
                )
            ) else {
                errorMessage = "Impossible de créer l’espèce."
                return
            }
            speciesId = newId
        }

        if addGeolocatedPlant {
            guard let location = locationManager.location else {
                errorMessage = "Espèce ajoutée, mais GPS indisponible pour créer l’individu."
                successMessage = "Espèce importée: \(latinName)"
                return
            }

            let cleanedLabel = plantLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = cleanedLabel // Label manuel ignoré: store génère l'étiquette automatiquement.
            store.createPlant(
                PlantWriteInput(
                    speciesId: speciesId,
                    varietyId: nil,
                    zone: nil,
                    notes: importNote,
                    status: "vivant",
                    microSite: nil,
                    exposureLocal: nil,
                    soilLocal: nil,
                    acquisitionType: "plantnet",
                    acquisitionSource: "identification",
                    careNotes: nil,
                    heightCurrent: nil,
                    envergureCurrent: nil,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
            )

            successMessage = "Espèce + individu géolocalisé ajoutés."
        } else {
            successMessage = "Espèce ajoutée: \(latinName)"
        }

        errorMessage = nil
    }

    @ViewBuilder
    private func referencePreview(for item: PlantNetService.ResultItem, width: CGFloat? = 92, height: CGFloat = 92) -> some View {
        let referenceURL = referenceImageURL(for: item)

        Group {
            if let referenceURL {
                CachedAsyncImage(url: referenceURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    referencePlaceholder
                }
            } else {
                referencePlaceholder
            }
        }
        .frame(maxWidth: width ?? .infinity, maxHeight: height)
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: CanopyCornerRadius.sm))
    }

    private var referencePlaceholder: some View {
        ZStack {
            Color.accentPrimary.opacity(0.08)

            VStack(spacing: 6) {
                Image(systemName: "photo")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.accentPrimary.opacity(0.9))

                Text("Pas d'image")
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
            }
        }
    }

    private func referenceImageURL(for item: PlantNetService.ResultItem) -> URL? {
        resolvedImageURL(from: normalizedURL(item.bestImageURL))
    }

    private func normalizedURL(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func makeImage(from data: Data) -> Image? {
        #if os(iOS)
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #elseif os(macOS)
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
        #endif
    }
}

#if os(iOS)
import UIKit

private struct CameraImagePicker: UIViewControllerRepresentable {
    let onImagePicked: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraImagePicker

        init(parent: CameraImagePicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.9) {
                parent.onImagePicked(data)
            }
            parent.dismiss()
        }
    }
}
#endif
