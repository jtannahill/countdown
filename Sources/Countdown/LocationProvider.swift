import Foundation
import CoreLocation

/// App-wide location source for sunset mode. Precedence: live CoreLocation fix →
/// manually-entered coordinates (persisted) → none. The live wrapper is not unit
/// tested; `isValid` and the manual setters are simple/pure.
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationProvider()

    struct Coordinate: Equatable { let latitude: Double; let longitude: Double }

    @Published private(set) var coordinate: Coordinate?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private var liveCoordinate: Coordinate? { didSet { recompute() } }

    private let latKey = "manualLat", lonKey = "manualLon"

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorizationStatus = manager.authorizationStatus
        recompute()
    }

    static func isValid(latitude: Double, longitude: Double) -> Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    // Reads the @Published status so SwiftUI refreshes when authorization changes
    // even if `coordinate` stays nil (e.g. denied before any fix).
    var authorizationDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    /// Lazily request authorization + a one-shot location fix. Safe to call repeatedly.
    func requestAccessIfNeeded() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    func setManualCoordinate(latitude: Double, longitude: Double) {
        guard Self.isValid(latitude: latitude, longitude: longitude) else { return }
        UserDefaults.standard.set(latitude, forKey: latKey)
        UserDefaults.standard.set(longitude, forKey: lonKey)
        recompute()
    }

    func clearManualCoordinate() {
        UserDefaults.standard.removeObject(forKey: latKey)
        UserDefaults.standard.removeObject(forKey: lonKey)
        recompute()
    }

    var manualCoordinate: Coordinate? {
        let d = UserDefaults.standard
        guard d.object(forKey: latKey) != nil, d.object(forKey: lonKey) != nil else { return nil }
        let lat = d.double(forKey: latKey), lon = d.double(forKey: lonKey)
        return Self.isValid(latitude: lat, longitude: lon) ? Coordinate(latitude: lat, longitude: lon) : nil
    }

    private func recompute() {
        let next = liveCoordinate ?? manualCoordinate
        // CLLocationManager delegate callbacks aren't guaranteed on the main thread
        // on macOS; coordinate drives SwiftUI, so publish it on the main thread.
        let apply = { if next != self.coordinate { self.coordinate = next } }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
    }

    // MARK: CLLocationManagerDelegate
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        // @Published write drives SwiftUI — keep it on the main thread.
        let apply = {
            self.authorizationStatus = status
            if status == .authorized || status == .authorizedAlways { manager.requestLocation() }
        }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
        recompute()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        liveCoordinate = Coordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        recompute()   // fall back to manual
    }
}
