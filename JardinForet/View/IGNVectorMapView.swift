#if os(iOS) && canImport(MapLibre)
import SwiftUI
import MapKit
import MapLibre

struct IGNVectorMapView: UIViewRepresentable {
    let pins: [GardenMapView.PlantPin]
    let selectedStrataFilter: GardenMapView.StrataFilter
    let terrainPolygons: [[CLLocationCoordinate2D]]
    let ilotPolygons: [[CLLocationCoordinate2D]]
    let hillshadeEnabled: Bool
    let hillshadeOpacity: Double
    let editingDraft: GardenMapView.PlantEditDraft?
    let onPinTap: (GardenMapView.PlantPin) -> Void
    let onPinLongPress: (GardenMapView.PlantPin) -> Void
    let onPinDrag: (GardenMapView.PlantPin, CLLocationCoordinate2D) -> Void
    let onRegionChange: (MKCoordinateRegion) -> Void

    private let ignStyleURL = URL(string: "https://data.geopf.fr/annexes/ressources/vectorTiles/styles/PLAN.IGN/standard.json")

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onPinTap: onPinTap,
            onPinLongPress: onPinLongPress,
            onPinDrag: onPinDrag,
            onRegionChange: onRegionChange
        )
    }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: ignStyleURL)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.allowsTilting = false
        mapView.minimumZoomLevel = 0
        mapView.maximumZoomLevel = 24
        mapView.attributionButton.isHidden = false
        mapView.logoView.isHidden = true

        let paperTintView = UIView(frame: mapView.bounds)
        paperTintView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        paperTintView.backgroundColor = UIColor(red: 0.995, green: 0.98, blue: 0.93, alpha: 1.0)
        paperTintView.isUserInteractionEnabled = false
        // Keep vegetation colors stable; warm mainly the white/light background.
        paperTintView.layer.compositingFilter = "multiplyBlendMode"
        paperTintView.alpha = 0.16
        mapView.addSubview(paperTintView)

        let reliefMapView = MLNMapView(frame: mapView.bounds, styleURL: ignStyleURL)
        reliefMapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        reliefMapView.backgroundColor = .clear
        reliefMapView.isOpaque = false
        reliefMapView.isUserInteractionEnabled = false
        reliefMapView.showsUserLocation = false
        reliefMapView.allowsTilting = false
        reliefMapView.minimumZoomLevel = 0
        reliefMapView.maximumZoomLevel = 24
        reliefMapView.attributionButton.isHidden = true
        reliefMapView.logoView.isHidden = true
        reliefMapView.delegate = context.coordinator
        reliefMapView.layer.compositingFilter = "multiplyBlendMode"
        mapView.addSubview(reliefMapView)

        let markerOverlay = MarkerPassthroughView(frame: mapView.bounds)
        markerOverlay.backgroundColor = .clear
        markerOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.addSubview(markerOverlay)

        context.coordinator.mapView = mapView
        context.coordinator.paperTintView = paperTintView
        context.coordinator.reliefMapView = reliefMapView
        context.coordinator.markerOverlay = markerOverlay
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        let coordinator = context.coordinator
        let newSize = mapView.bounds.size
        reliefOverlayFrameSync(mapView: mapView, coordinator: coordinator)

        coordinator.filteredPins = pins.filter { selectedStrataFilter.matches($0.strata) }
            .map { pin in
                guard let draft = editingDraft, draft.id == pin.id else { return pin }
                return GardenMapView.PlantPin(
                    id: pin.id,
                    commonName: pin.commonName,
                    varietyName: pin.varietyName,
                    zone: pin.zone,
                    strata: pin.strata,
                    canopyDiameterMeters: draft.canopyDiameterMeters,
                    coordinate: draft.coordinate
                )
            }
        coordinator.editingPinID = editingDraft?.id
        coordinator.terrainPolygons = terrainPolygons
        coordinator.ilotPolygons = ilotPolygons
        coordinator.setRelief(enabled: hillshadeEnabled, opacity: hillshadeOpacity)
        coordinator.refreshContent()

        if coordinator.lastViewportSize != newSize {
            coordinator.lastViewportSize = newSize
            coordinator.handleViewportDidChange()
        }
    }

    private func reliefOverlayFrameSync(mapView: MLNMapView, coordinator: Coordinator) {
        coordinator.paperTintView?.frame = mapView.bounds
        coordinator.reliefMapView?.frame = mapView.bounds
        coordinator.markerOverlay?.frame = mapView.bounds
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        weak var mapView: MLNMapView?
        weak var paperTintView: UIView?
        weak var reliefMapView: MLNMapView?
        weak var markerOverlay: UIView?

        let onPinTap: (GardenMapView.PlantPin) -> Void
        let onPinLongPress: (GardenMapView.PlantPin) -> Void
        let onPinDrag: (GardenMapView.PlantPin, CLLocationCoordinate2D) -> Void
        let onRegionChange: (MKCoordinateRegion) -> Void

        var filteredPins: [GardenMapView.PlantPin] = []
        var terrainPolygons: [[CLLocationCoordinate2D]] = []
        var ilotPolygons: [[CLLocationCoordinate2D]] = []

        private var didSetInitialCamera = false
        var lastViewportSize: CGSize = .zero
        private var markerViewsByID: [Int: CanopyMarkerView] = [:]
        private var pinByID: [Int: GardenMapView.PlantPin] = [:]
        var editingPinID: Int? = nil

        private let terrainSourceID = "jf-terrain-source"
        private let terrainFillLayerID = "jf-terrain-fill-layer"
        private let terrainLineLayerID = "jf-terrain-line-layer"
        private let ilotSourceID = "jf-ilot-source"
        private let ilotFillLayerID = "jf-ilot-fill-layer"
        private let ilotLineLayerID = "jf-ilot-line-layer"
        private let lidarSourceID = "jf-lidar-source"
        private let lidarLayerID = "jf-lidar-layer"
        private var reliefEnabled = true
        private var reliefOpacity = 0.5

        init(
            onPinTap: @escaping (GardenMapView.PlantPin) -> Void,
            onPinLongPress: @escaping (GardenMapView.PlantPin) -> Void,
            onPinDrag: @escaping (GardenMapView.PlantPin, CLLocationCoordinate2D) -> Void,
            onRegionChange: @escaping (MKCoordinateRegion) -> Void
        ) {
            self.onPinTap = onPinTap
            self.onPinLongPress = onPinLongPress
            self.onPinDrag = onPinDrag
            self.onRegionChange = onRegionChange
        }

        func setRelief(enabled: Bool, opacity: Double) {
            reliefEnabled = enabled
            reliefOpacity = max(0, min(1, opacity))
            reliefMapView?.isHidden = !reliefEnabled
            // Fixed "Produit" strategy: reduced strength for better balance.
            reliefMapView?.layer.compositingFilter = "multiplyBlendMode"
            reliefMapView?.alpha = CGFloat(reliefOpacity * 0.72)
            if let style = reliefMapView?.style {
                upsertLidarLayer(on: style)
            }
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            if mapView === reliefMapView {
                configureReliefOnlyStyle(style)
                upsertLidarLayer(on: style)
                syncReliefCameraFromMain()
            } else {
                refreshContent()
                syncReliefCameraFromMain()
            }
        }

        func mapViewRegionIsChanging(_ mapView: MLNMapView) {
            guard mapView === self.mapView else { return }
            updateMarkerPositions()
            syncReliefCameraFromMain()
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            guard mapView === self.mapView else { return }
            if mapView.camera.pitch != 0 {
                mapView.camera.pitch = 0
                mapView.setCamera(mapView.camera, animated: false)
            }
            updateMarkerPositions()
            syncReliefCameraFromMain()

            let bounds = mapView.visibleCoordinateBounds
            let center = CLLocationCoordinate2D(
                latitude: (bounds.ne.latitude + bounds.sw.latitude) * 0.5,
                longitude: (bounds.ne.longitude + bounds.sw.longitude) * 0.5
            )
            let span = MKCoordinateSpan(
                latitudeDelta: abs(bounds.ne.latitude - bounds.sw.latitude),
                longitudeDelta: abs(bounds.ne.longitude - bounds.sw.longitude)
            )
            onRegionChange(MKCoordinateRegion(center: center, span: span))
        }

        func handleViewportDidChange() {
            updateMarkerPositions()
        }

        func refreshContent() {
            guard let mapView else { return }

            if !didSetInitialCamera {
                didSetInitialCamera = true
                let defaultCenter = CLLocationCoordinate2D(latitude: 45.348828976987036, longitude: 4.0740432545957255)
                if let first = filteredPins.first {
                    mapView.setCenter(first.coordinate, zoomLevel: 18, animated: false)
                } else {
                    mapView.setCenter(defaultCenter, zoomLevel: 18, animated: false)
                }
            }

            if let style = mapView.style {
                upsertParcelAndIlotLayers(on: style)
            }

            refreshNativeAppleMarkers()
            updateMarkerPositions()
        }

        private func syncReliefCameraFromMain() {
            guard let mapView, let reliefMapView else { return }
            reliefMapView.setCenter(mapView.centerCoordinate, zoomLevel: mapView.zoomLevel, direction: mapView.direction, animated: false)
            if reliefMapView.camera.pitch != 0 {
                reliefMapView.camera.pitch = 0
                reliefMapView.setCamera(reliefMapView.camera, animated: false)
            }
        }

        private func normalizeRing(_ coords: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
            let valid = coords.filter { CLLocationCoordinate2DIsValid($0) }
            guard valid.count >= 2 else { return valid }
            var out = valid
            if let first = out.first, let last = out.last {
                let closed = abs(first.latitude - last.latitude) < 0.0000001 &&
                    abs(first.longitude - last.longitude) < 0.0000001
                if !closed {
                    out.append(first)
                }
            }
            return out
        }

        private func upsertParcelAndIlotLayers(on style: MLNStyle) {
            suppressContourLines(in: style)

            [terrainLineLayerID, terrainFillLayerID, ilotLineLayerID, ilotFillLayerID].forEach { layerID in
                if let layer = style.layer(withIdentifier: layerID) {
                    style.removeLayer(layer)
                }
            }
            [terrainSourceID, ilotSourceID].forEach { sourceID in
                if let source = style.source(withIdentifier: sourceID) {
                    style.removeSource(source)
                }
            }

            let terrainShapes: [MLNPolygonFeature] = terrainPolygons.compactMap { coords in
                let ring = normalizeRing(coords)
                guard ring.count >= 4 else { return nil }
                var mutable = ring
                return MLNPolygonFeature(coordinates: &mutable, count: UInt(mutable.count))
            }
            if !terrainShapes.isEmpty {
                let terrainCollection = MLNShapeCollectionFeature(shapes: terrainShapes)
                let terrainSource = MLNShapeSource(identifier: terrainSourceID, shape: terrainCollection, options: nil)
                style.addSource(terrainSource)

                let fill = MLNFillStyleLayer(identifier: terrainFillLayerID, source: terrainSource)
                // Neutralize IGN background inside parcel while keeping roads/labels above.
                fill.fillColor = NSExpression(forConstantValue: UIColor(white: 1.0, alpha: 1.0))
                fill.fillOpacity = NSExpression(forConstantValue: 0.92)
                fill.fillOutlineColor = NSExpression(forConstantValue: UIColor.clear)
                insertLayerKeepingRoadsAndLabelsVisible(fill, style: style)

                // No hard parcel border: user wants to remove IGN background effect, not add heavy contour.
                let line = MLNLineStyleLayer(identifier: terrainLineLayerID, source: terrainSource)
                line.lineColor = NSExpression(forConstantValue: UIColor.black)
                line.lineWidth = NSExpression(forConstantValue: 1.8)
                line.lineOpacity = NSExpression(forConstantValue: 1.0)
                insertLayerKeepingRoadsAndLabelsVisible(line, style: style)
            }

            let ilotShapes: [MLNPolygonFeature] = ilotPolygons.compactMap { coords in
                let ring = normalizeRing(coords)
                guard ring.count >= 4 else { return nil }
                var mutable = ring
                return MLNPolygonFeature(coordinates: &mutable, count: UInt(mutable.count))
            }
            if !ilotShapes.isEmpty {
                let ilotCollection = MLNShapeCollectionFeature(shapes: ilotShapes)
                let ilotSource = MLNShapeSource(identifier: ilotSourceID, shape: ilotCollection, options: nil)
                style.addSource(ilotSource)

                let fill = MLNFillStyleLayer(identifier: ilotFillLayerID, source: ilotSource)
                fill.fillColor = NSExpression(forConstantValue: UIColor.systemTeal)
                fill.fillOpacity = NSExpression(forConstantValue: 0.34)
                fill.fillOutlineColor = NSExpression(forConstantValue: UIColor.label.withAlphaComponent(0.30))
                insertLayerKeepingRoadsAndLabelsVisible(fill, style: style)

                let line = MLNLineStyleLayer(identifier: ilotLineLayerID, source: ilotSource)
                line.lineColor = NSExpression(forConstantValue: UIColor.label.withAlphaComponent(0.28))
                line.lineWidth = NSExpression(forConstantValue: 0.9)
                line.lineOpacity = NSExpression(forConstantValue: 0.55)
                insertLayerKeepingRoadsAndLabelsVisible(line, style: style)
            }
        }

        private func insertLayerKeepingRoadsAndLabelsVisible(_ layer: MLNStyleLayer, style: MLNStyle) {
            if let anchor = firstRoadOrLabelLayer(in: style) {
                style.insertLayer(layer, below: anchor)
            } else {
                style.addLayer(layer)
            }
        }

        private func firstRoadOrLabelLayer(in style: MLNStyle) -> MLNStyleLayer? {
            // Find earliest "kept" layer so parcel/ilot fills stay below roads and labels.
            let keepTokens = ["road", "route", "path", "transport", "name", "label", "poi"]
            for layer in style.layers {
                let id = layer.identifier.lowercased()
                let isCandidate = keepTokens.contains { id.contains($0) }
                if isCandidate {
                    return layer
                }
            }
            return nil
        }

        private func suppressContourLines(in style: MLNStyle) {
            // IGN style IDs vary; hide likely contour-line layers by identifier tokens.
            let contourTokens = [
                "courbe", "courbes", "contour", "isoline", "isohyps", "hypsometric", "altimetr", "orography", "relief_line"
            ]
            for layer in style.layers {
                let id = layer.identifier.lowercased()
                if contourTokens.contains(where: { id.contains($0) }) {
                    layer.isVisible = false
                }
            }
        }

        private func configureReliefOnlyStyle(_ style: MLNStyle) {
            for layer in style.layers {
                layer.isVisible = false
            }
        }

        private func upsertLidarLayer(on style: MLNStyle) {
            if let existingLayer = style.layer(withIdentifier: lidarLayerID) {
                style.removeLayer(existingLayer)
            }

            if style.source(withIdentifier: lidarSourceID) == nil {
                let lidarTemplate = "https://data.geopf.fr/wmts?SERVICE=WMTS&VERSION=1.0.0&REQUEST=GetTile&LAYER=IGNF_LIDAR-HD_MNT_ELEVATION.ELEVATIONGRIDCOVERAGE.SHADOW&STYLE=normal&TILEMATRIXSET=PM&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/png"
                let options: [MLNTileSourceOption: Any] = [
                    MLNTileSourceOption.tileSize: 256,
                    MLNTileSourceOption.minimumZoomLevel: 0,
                    MLNTileSourceOption.maximumZoomLevel: 18
                ]
                let source = MLNRasterTileSource(identifier: lidarSourceID, tileURLTemplates: [lidarTemplate], options: options)
                style.addSource(source)
            }

            guard let source = style.source(withIdentifier: lidarSourceID) else { return }
            let layer = MLNRasterStyleLayer(identifier: lidarLayerID, source: source)
            layer.isVisible = reliefEnabled
            layer.rasterOpacity = NSExpression(forConstantValue: reliefOpacity)
            insertLidarLayerForReliefReadability(layer, style: style)
        }

        private func insertLidarLayerForReliefReadability(_ layer: MLNStyleLayer, style: MLNStyle) {
            // LiDAR must sit above parcel/ilot fills so white parcel still shows relief.
            if let terrainLine = style.layer(withIdentifier: terrainLineLayerID) {
                style.insertLayer(layer, below: terrainLine)
                return
            }
            if let ilotLine = style.layer(withIdentifier: ilotLineLayerID) {
                style.insertLayer(layer, below: ilotLine)
                return
            }
            if let ilotFill = style.layer(withIdentifier: ilotFillLayerID) {
                style.insertLayer(layer, above: ilotFill)
                return
            }
            if let terrainFill = style.layer(withIdentifier: terrainFillLayerID) {
                style.insertLayer(layer, above: terrainFill)
                return
            }
            insertLayerKeepingRoadsAndLabelsVisible(layer, style: style)
        }

        private func refreshNativeAppleMarkers() {
            guard let overlay = markerOverlay else { return }

            let incomingIDs = Set(filteredPins.map(\.id))
            let existingIDs = Set(markerViewsByID.keys)

            let removed = existingIDs.subtracting(incomingIDs)
            for id in removed {
                markerViewsByID[id]?.removeFromSuperview()
                markerViewsByID[id] = nil
                pinByID[id] = nil
            }

            for pin in filteredPins {
                pinByID[pin.id] = pin
                let marker = markerViewsByID[pin.id] ?? {
                    let v = CanopyMarkerView(frame: .zero)
                    let tap = UITapGestureRecognizer(target: self, action: #selector(handleMarkerTap(_:)))
                    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleMarkerLongPress(_:)))
                    longPress.minimumPressDuration = 0.45
                    let pan = UIPanGestureRecognizer(target: self, action: #selector(handleMarkerPan(_:)))
                    pan.maximumNumberOfTouches = 1
                    v.addGestureRecognizer(tap)
                    v.addGestureRecognizer(longPress)
                    v.addGestureRecognizer(pan)
                    v.isUserInteractionEnabled = true
                    overlay.addSubview(v)
                    markerViewsByID[pin.id] = v
                    return v
                }()
                marker.tag = pin.id
                marker.isEditable = (editingPinID == pin.id)
                marker.canopyDiameterMeters = pin.canopyDiameterMeters ?? CanopyMarkerStyle.fallbackDiameterMeters(for: pin.strata)
                marker.apply(
                    diameter: 20,
                    fillColor: CanopyMarkerStyle.color(for: pin.strata).withAlphaComponent(0.34),
                    strokeColor: CanopyMarkerStyle.color(for: pin.strata).withAlphaComponent(0.92),
                    labelText: CanopyMarkerStyle.abbrev(for: pin.commonName)
                )
            }
        }

        private func updateMarkerPositions() {
            guard let mapView else { return }
            for (id, marker) in markerViewsByID {
                guard let pin = pinByID[id] else { continue }
                let point = mapView.convert(pin.coordinate, toPointTo: mapView)
                let diameter = markerDiameterPoints(
                    at: pin.coordinate,
                    diameterMeters: marker.canopyDiameterMeters,
                    in: mapView
                )
                marker.apply(
                    diameter: diameter,
                    fillColor: CanopyMarkerStyle.color(for: pin.strata).withAlphaComponent(0.34),
                    strokeColor: CanopyMarkerStyle.color(for: pin.strata).withAlphaComponent(0.92),
                    labelText: CanopyMarkerStyle.abbrev(for: pin.commonName)
                )
                marker.center = point
            }
        }

        @objc
        private func handleMarkerTap(_ gesture: UITapGestureRecognizer) {
            guard
                let marker = gesture.view,
                let pin = pinByID[marker.tag]
            else { return }
            onPinTap(pin)
        }

        @objc
        private func handleMarkerLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard
                gesture.state == .began,
                let marker = gesture.view,
                let pin = pinByID[marker.tag]
            else { return }
            onPinLongPress(pin)
        }

        @objc
        private func handleMarkerPan(_ gesture: UIPanGestureRecognizer) {
            guard
                let mapView,
                let marker = gesture.view as? CanopyMarkerView,
                marker.isEditable,
                let pin = pinByID[marker.tag]
            else { return }

            let point = gesture.location(in: mapView)
            marker.center = point
            if gesture.state == .ended {
                let coord = mapView.convert(point, toCoordinateFrom: mapView)
                // Commit seulement en fin de geste pour éviter les rafraîchissements lourds.
                onPinDrag(pin, coord)
            }
        }

        private func markerDiameterPoints(
            at coordinate: CLLocationCoordinate2D,
            diameterMeters: Double,
            in mapView: MLNMapView
        ) -> CGFloat {
            CanopyMarkerStyle.diameterPoints(at: coordinate, diameterMeters: diameterMeters) { coord in
                mapView.convert(coord, toPointTo: mapView)
            }
        }
    }
}

private final class MarkerPassthroughView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        for subview in subviews where !subview.isHidden && subview.alpha > 0.01 && subview.isUserInteractionEnabled {
            let p = convert(point, to: subview)
            if subview.point(inside: p, with: event) {
                return true
            }
        }
        return false
    }
}

private final class CanopyMarkerView: UIView {
    var canopyDiameterMeters: Double = 3.0
    var isEditable: Bool = false
    private let textLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureLabel()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLabel()
    }

    private func configureLabel() {
        clipsToBounds = true
        textLabel.textAlignment = .center
        textLabel.numberOfLines = 1
        textLabel.minimumScaleFactor = 0.35
        textLabel.adjustsFontSizeToFitWidth = true
        textLabel.baselineAdjustment = .alignCenters
        textLabel.textColor = UIColor.label.withAlphaComponent(0.88)
        textLabel.layer.shadowColor = UIColor.black.withAlphaComponent(0.30).cgColor
        textLabel.layer.shadowOpacity = 1
        textLabel.layer.shadowRadius = 1
        textLabel.layer.shadowOffset = CGSize(width: 0, height: 0.5)
        addSubview(textLabel)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = max(2, bounds.width * 0.12)
        textLabel.frame = bounds.insetBy(dx: inset, dy: inset)
    }

    func apply(diameter: CGFloat, fillColor: UIColor, strokeColor: UIColor, labelText: String) {
        let d = max(2, min(5000, diameter))
        bounds = CGRect(x: 0, y: 0, width: d, height: d)
        layer.cornerRadius = d * 0.5
        layer.backgroundColor = fillColor.cgColor
        layer.borderColor = strokeColor.cgColor
        layer.borderWidth = max(1.1, d * 0.055)
        layer.shadowColor = strokeColor.withAlphaComponent(0.35).cgColor
        layer.shadowOpacity = 1
        layer.shadowRadius = 1.2
        layer.shadowOffset = .zero
        textLabel.text = labelText
        textLabel.font = UIFont.systemFont(ofSize: max(8, d * 0.33), weight: .semibold)
        setNeedsLayout()
    }
}

final class ReliefSoftLightOverlayView: UIView {
    // Deprecated: LiDAR rendering is now handled natively by MapLibre raster layers.
}
#endif
