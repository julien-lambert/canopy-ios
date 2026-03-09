import Foundation
import CoreLocation

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var heading: CLHeading?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest

        // Autorisation
        manager.requestWhenInUseAuthorization()

        // Démarrage des mises à jour
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    // Position GPS
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        DispatchQueue.main.async {
            self.location = last
        }
    }

    // Orientation (boussole)
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        DispatchQueue.main.async {
            self.heading = newHeading
        }
    }

    // Gestion des changements d’autorisation (optionnel mais utile pour debug)
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        AppLog.debug("Status localisation: \(status.rawValue)", category: .ui)
        #if os(iOS)
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
        }
        #else
        if status == .authorized {
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
        }
        #endif
    }
}
