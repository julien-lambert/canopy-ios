import SwiftUI
#if os(iOS)
import UIKit
import Metal
#endif
import CoreText
#if os(iOS)
import ARKit
import RealityKit

/// Petite bibliothèque de matériaux chargés depuis des .usdz
private enum LabelMaterialLibrary {
    private static func loadTexture(candidates: [String]) -> TextureResource? {
        for name in candidates {
            if let tex = try? TextureResource.load(named: name) {
                return tex
            }
        }
        return nil
    }

    static let brushedAluminum: RealityKit.Material = {
        var pbr = PhysicallyBasedMaterial()
        let baseColorCandidates = [
            "metal_basecolor.png",
            "textures/metal_basecolor.png",
            "metal_basecolor.jpg",
            "textures/metal_basecolor.jpg",
            "metal_basecolor"
        ]
        let normalCandidates = [
            "metal_normal_opengl.png",
            "textures/metal_normal_opengl.png",
            "metal_normal_opengl.jpg",
            "textures/metal_normal_opengl.jpg",
            "metal_normal_opengl"
        ]
        let metallicCandidates = [
            "metal_metallic.png",
            "textures/metal_metallic.png",
            "metal_metallic.jpg",
            "textures/metal_metallic.jpg",
            "metal_metallic"
        ]
        let roughnessCandidates = [
            "metal_roughness.png",
            "textures/metal_roughness.png"
        ]

        // Base claire texturée (set PBR réel) + légère teinte pour garder la lisibilité.
        if let baseTex = loadTexture(candidates: baseColorCandidates) {
            pbr.baseColor = .init(
                tint: UIColor(red: 0.985, green: 0.99, blue: 1.0, alpha: 1.0),
                texture: .init(baseTex)
            )
        } else {
            pbr.baseColor = .init(tint: UIColor(red: 0.975, green: 0.98, blue: 0.99, alpha: 1.0))
        }

        if let normalTex = loadTexture(candidates: normalCandidates) {
            pbr.normal = .init(texture: .init(normalTex))
        }

        if let metallicTex = loadTexture(candidates: metallicCandidates) {
            pbr.metallic = .init(texture: .init(metallicTex))
        } else {
            pbr.metallic = 0.55
        }
        if let roughTex = loadTexture(candidates: roughnessCandidates) {
            pbr.roughness = .init(texture: .init(roughTex))
        } else {
            pbr.roughness = 0.31
        }
        pbr.specular = 0.72

        // Anisotropie physique horizontale (alu brossé).
        if #available(iOS 17.0, *) {
            pbr.anisotropyLevel = 1.0
            pbr.anisotropyAngle = 0.0
        }

        return pbr
    }()
}

func makePlantLabelEntity(
    vernacular: String,
    cultivar: String,
    scientific: String,
    family: String,
    genus: String,
    rootstock: String,
    strata: String,
    identifier: String
) -> Entity {
    let root = Entity()
    let vernacularText = vernacular.trimmingCharacters(in: .whitespacesAndNewlines)
    let cultivarText   = cultivar.trimmingCharacters(in: .whitespacesAndNewlines)
    let scientificText = scientific.trimmingCharacters(in: .whitespacesAndNewlines)
    let familyText     = family.trimmingCharacters(in: .whitespacesAndNewlines)
    let genusText      = genus.trimmingCharacters(in: .whitespacesAndNewlines)
    let rootText       = rootstock.trimmingCharacters(in: .whitespacesAndNewlines)
    let strataText     = strata.trimmingCharacters(in: .whitespacesAndNewlines)
    let safeVernacular = vernacularText.isEmpty ? "Plante" : vernacularText
    let cardWidth: Float = 0.22
    let cardHeight: Float = 0.13

    let frameMesh = MeshResource.generatePlane(
        width: cardWidth + 0.012,
        height: cardHeight + 0.012,
        cornerRadius: min(cardWidth, cardHeight) * 0.18
    )
    var frameMat = PhysicallyBasedMaterial()
    frameMat.baseColor = .init(tint: UIColor(white: 0.66, alpha: 1.0))
    frameMat.metallic = 0.86
    frameMat.roughness = 0.18
    let frameEntity = ModelEntity(mesh: frameMesh, materials: [frameMat])
    frameEntity.position.z = 0.0
    root.addChild(frameEntity)

    let panelMesh = MeshResource.generatePlane(
        width: cardWidth,
        height: cardHeight,
        cornerRadius: min(cardWidth, cardHeight) * 0.14
    )
    let panelEntity = ModelEntity(mesh: panelMesh, materials: [LabelMaterialLibrary.brushedAluminum])
    panelEntity.position.z = 0.0009
    root.addChild(panelEntity)

    struct LabelLine {
        let text: String
        let font: UIFont
        let align: CTTextAlignment
        let isTitle: Bool
    }
    let titleFont = UIFont.systemFont(ofSize: 0.030, weight: .bold)
    let bodyFont = UIFont.systemFont(ofSize: 0.022, weight: .semibold)
    let latinFont = UIFont.italicSystemFont(ofSize: 0.020)
    let metaFont = UIFont.systemFont(ofSize: 0.018, weight: .regular)

    var title = safeVernacular.uppercased()
    if title.count > 28 { title = String(title.prefix(25)) + "..." }
    var lines: [LabelLine] = [LabelLine(text: title, font: titleFont, align: .left, isTitle: true)]

    if !cultivarText.isEmpty {
        var cultivarLine = cultivarText
        if cultivarLine.count > 40 { cultivarLine = String(cultivarLine.prefix(37)) + "..." }
        lines.append(LabelLine(text: cultivarLine, font: bodyFont, align: .center, isTitle: false))
    }
    if !scientificText.isEmpty {
        var scientificLine = scientificText
        if scientificLine.count > 40 { scientificLine = String(scientificLine.prefix(37)) + "..." }
        lines.append(LabelLine(text: scientificLine, font: latinFont, align: .left, isTitle: false))
    }

    if !familyText.isEmpty {
        var line = "Famille : \(familyText)"
        if line.count > 42 { line = String(line.prefix(39)) + "..." }
        lines.append(LabelLine(text: line, font: metaFont, align: .left, isTitle: false))
    }
    if !genusText.isEmpty {
        var line = "Genre : \(genusText)"
        if line.count > 42 { line = String(line.prefix(39)) + "..." }
        lines.append(LabelLine(text: line, font: metaFont, align: .left, isTitle: false))
    }
    if !rootText.isEmpty {
        var line = "Porte-greffe : \(rootText)"
        if line.count > 42 { line = String(line.prefix(39)) + "..." }
        lines.append(LabelLine(text: line, font: metaFont, align: .left, isTitle: false))
    }
    if !strataText.isEmpty {
        var line = "Strate : \(strataText)"
        if line.count > 42 { line = String(line.prefix(39)) + "..." }
        lines.append(LabelLine(text: line, font: metaFont, align: .left, isTitle: false))
    }

    let bodyTextMaterial = UnlitMaterial(color: UIColor(red: 0.14, green: 0.16, blue: 0.18, alpha: 1.0))
    var engravedTitleMaterial = PhysicallyBasedMaterial()
    engravedTitleMaterial.baseColor = .init(tint: UIColor(red: 0.22, green: 0.24, blue: 0.27, alpha: 1.0))
    engravedTitleMaterial.metallic = 0.68
    engravedTitleMaterial.roughness = 0.30
    var textEntities: [ModelEntity] = []
    var textSizes: [SIMD3<Float>] = []
    var textCenters: [SIMD3<Float>] = []

    for line in lines {
        let mesh = MeshResource.generateText(
            line.text,
            extrusionDepth: line.isTitle ? 0.00020 : 0.00035,
            font: line.font,
            containerFrame: .zero,
            alignment: line.align,
            lineBreakMode: .byTruncatingTail
        )
        let entity = ModelEntity(mesh: mesh, materials: [line.isTitle ? engravedTitleMaterial : bodyTextMaterial])
        textEntities.append(entity)
        textSizes.append(mesh.bounds.extents)
        textCenters.append(mesh.bounds.center)
    }

    let lineSpacing: Float = 0.006
    let totalTextHeight = textSizes.reduce(0) { $0 + $1.y } + Float(max(0, textEntities.count - 1)) * lineSpacing
    let maxTextWidth = textSizes.map(\.x).max() ?? 0.0
    let availableWidth: Float = cardWidth * 0.74
    let availableHeight: Float = cardHeight * 0.66
    let widthScale = availableWidth / max(maxTextWidth, 0.0001)
    let heightScale = availableHeight / max(totalTextHeight, 0.0001)
    let fitScale = min(1.0, min(widthScale, heightScale))
    let invScale = 1.0 / max(fitScale, 0.0001)

    // On layout le texte dans un conteneur local centré, puis on scale globalement le bloc.
    let textContainer = Entity()
    var runningTop = totalTextHeight / 2
    let textStartZ: Float = 0.00145
    let leftMargin: Float = -cardWidth * 0.34

    for i in 0..<textEntities.count {
        let entity = textEntities[i]
        let size = textSizes[i]
        let center = textCenters[i]
        let lineCenterY = runningTop - size.y / 2
        let leftEdge = center.x - size.x / 2
        let xPosition: Float
        if i == 0 || (i == 1 && !cultivarText.isEmpty) {
            // Nom principal + cultivar centrés.
            xPosition = -center.x
        } else {
            // Les autres lignes justifiées à gauche.
            xPosition = (leftMargin * invScale) - leftEdge
        }
        entity.position = [
            xPosition,
            lineCenterY - center.y,
            textStartZ + (i == 0 ? -0.00008 : 0.00018)
        ]
        runningTop -= size.y + lineSpacing
        textContainer.addChild(entity)
    }

    textContainer.scale = [fitScale, fitScale, 1.0]

    // Centre explicitement le bloc texte sur le panneau.
    textContainer.position = [0, 0, 0]
    root.addChild(textContainer)

    // Badge d'identification en bas à droite.
    var idText = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
    if idText.isEmpty { idText = safeVernacular }
    if idText.count > 14 {
        idText = String(idText.prefix(11)) + "..."
    }

    let idFont = UIFont.systemFont(ofSize: 0.0095, weight: .semibold)
    let idMesh = MeshResource.generateText(
        idText,
        extrusionDepth: 0.00014,
        font: idFont,
        containerFrame: .zero,
        alignment: .right,
        lineBreakMode: .byTruncatingTail
    )
    let idMaterial = UnlitMaterial(color: UIColor(red: 0.18, green: 0.20, blue: 0.22, alpha: 1.0))
    let idEntity = ModelEntity(mesh: idMesh, materials: [idMaterial])
    let idCenter = idMesh.bounds.center
    let idExtents = idMesh.bounds.extents
    let rightAnchor: Float = cardWidth * 0.39
    let bottomAnchor: Float = -cardHeight * 0.36
    let rightEdge = idCenter.x + idExtents.x / 2
    let bottomEdge = idCenter.y - idExtents.y / 2
    idEntity.position = [
        rightAnchor - rightEdge,
        bottomAnchor - bottomEdge,
        textStartZ + 0.00024
    ]
    root.addChild(idEntity)

    // Billboard vers la caméra.
    root.components[BillboardComponent.self] = BillboardComponent()
    return root
}
// MARK: - Vue SwiftUI

struct VRView: View {
    @EnvironmentObject var store: CanopyStore
    @State private var selectedPlantIndex: Int = 0
    @State private var resetToggle: Bool = false

    private func displayName(for plant: GardenPlant) -> String {
        let label = plant.label ?? ""
        let common = plant.commonName

        if !label.isEmpty {
            return label
        } else if !common.isEmpty {
            return common
        } else {
            return "Plante #\(plant.id)"
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ARContainer(store: store, selectedPlantIndex: $selectedPlantIndex, resetToggle: $resetToggle)
                .edgesIgnoringSafeArea(.all)

            if store.plants.isEmpty {
                Text("Aucune plante dans la base")
                    .font(.callout)
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .padding(.top, 40)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.plants.indices, id: \.self) { index in
                            let plant = store.plants[index]
                            let name = displayName(for: plant)

                            Button(action: {
                                selectedPlantIndex = index
                            }) {
                                Text(name)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        selectedPlantIndex == index
                                        ? Color.green.opacity(0.8)
                                        : Color.black.opacity(0.6)
                                    )
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                    .accessibilityLabel(Text("Sélectionner \(name)"))
                                    .accessibilityHint(Text("Place une étiquette pour cette plante en AR"))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .background(Color.black.opacity(0.25).blur(radius: 4))
                .padding(.top, 40)
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: { resetToggle.toggle() }) {
                        Text("Reset")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .accessibilityLabel(Text("Réinitialiser la scène AR"))
                            .accessibilityHint(Text("Supprime toutes les étiquettes placées"))
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Conteneur ARKit / RealityKit (iOS)

struct ARContainer: UIViewRepresentable {
    typealias UIViewType = ARView

    let store: CanopyStore
    @Binding var selectedPlantIndex: Int
    @Binding var resetToggle: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject {
        let parent: ARContainer
        var lastResetValue: Bool = false

        init(parent: ARContainer) {
            self.parent = parent
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let arView = recognizer.view as? ARView else { return }

            let tapLocation = recognizer.location(in: arView)

            // Raycast d'abord sur des plans existants pour plus de stabilité, puis fallback estimé
            let primary = arView.raycast(from: tapLocation, allowing: .existingPlaneGeometry, alignment: .any)
            let results = primary.isEmpty ? arView.raycast(from: tapLocation, allowing: .estimatedPlane, alignment: .any) : primary
            guard let firstResult = results.first else { return }

            // Création d'une ancre au point d'impact
            let anchor = AnchorEntity(world: firstResult.worldTransform)

            // Choix de la plante sélectionnée (toutes données de la carte identité)
            let plants = parent.store.plants

            var vernacular = "Plante"
            var cultivar   = ""
            var scientific = ""
            var family     = ""
            var genus      = ""
            var rootstock  = ""
            var strata     = ""
            var identifier = ""

            if plants.indices.contains(parent.selectedPlantIndex) {
                let p = plants[parent.selectedPlantIndex]

                // Vernaculaire ou label en fallback
                let label = p.label ?? ""
                identifier = label
                let common = p.commonName
                if !common.isEmpty {
                    vernacular = common
                } else if !label.isEmpty {
                    vernacular = label
                } else {
                    vernacular = "Plante #\(p.id)"
                }

                // Cultivar
                if let v = p.varietyName, !v.isEmpty {
                    cultivar = v
                }

                // Nom latin
                if !p.latinName.isEmpty {
                    scientific = p.latinName
                }

                // Famille
                if let fam = p.family, !fam.isEmpty {
                    family = fam
                }

                // Genre
                if let g = p.genus, !g.isEmpty {
                    genus = g
                }

                // Porte-greffe
                if let r = p.rootstock, !r.isEmpty {
                    rootstock = r
                }

                // Strate
                if let s = p.strata, !s.isEmpty {
                    strata = s
                }
            }

            AppLog.debug("[VR] Ajout etiquette: \(vernacular)", category: .ar)
            let labelEntity = makePlantLabelEntity(
                vernacular: vernacular,
                cultivar: cultivar,
                scientific: scientific,
                family: family,
                genus: genus,
                rootstock: rootstock,
                strata: strata,
                identifier: identifier
            )

            // On place l'étiquette légèrement au-dessus du point
            labelEntity.position.y += 0.15

            anchor.addChild(labelEntity)
            arView.scene.addAnchor(anchor)
        }
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // On gère la session nous-même pour garder le contrôle
        arView.automaticallyConfigureSession = false

        // S'assurer que l'éclairage ARKit n'est pas désactivé
        arView.renderOptions.remove(.disableAREnvironmentLighting)

        // Occlusion par mesh (LiDAR / profondeur) pour que le réel masque bien les objets virtuels
        if #available(iOS 13.4, *) {
            arView.environment.sceneUnderstanding.options.insert(.occlusion)
        }

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]

        // Estimation de la lumière de la scène réelle
        config.isLightEstimationEnabled = true

        // Génération de la cubemap d'environnement à partir de la caméra
        config.environmentTexturing = .automatic

        // Reconstruction de scène pour obtenir un mesh 3D du réel
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }

        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        // Gestes : appui du doigt pour positionner une étiquette
        let tapGesture = UITapGestureRecognizer(target: context.coordinator,
                                                action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        if context.coordinator.lastResetValue != resetToggle {
            context.coordinator.lastResetValue = resetToggle
            uiView.scene.anchors.removeAll()
        }
        // Pour l'instant, rien à mettre à jour dynamiquement à chaque changement d'état SwiftUI.
        // Les nouveaux taps utiliseront simplement la valeur à jour de selectedPlantIndex.
    }
}
#endif
