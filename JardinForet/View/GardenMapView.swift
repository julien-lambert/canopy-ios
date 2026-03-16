import SwiftUI
import MapKit

struct GardenMapView: View {
    typealias Mode = GardenMapScreen.Mode
    typealias PlantEditDraft = GardenMapScreen.PlantEditDraft
    typealias StrataFilter = GardenMapScreen.StrataFilter
    typealias PlantPin = GardenMapScreen.PlantPin

    private let mode: Mode

    init(mode: Mode = .view) {
        self.mode = mode
    }

    var body: some View {
        GardenMapScreen(mode: mode)
    }
}
