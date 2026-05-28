import Foundation
import CoreLocation
import CoreMotion

/// Wraps `CLLocationManager` (GPS) + `CMAltimeter` (barometric altitude) for
/// ride telemetry recording. Publishes the latest fix so
/// `RideTelemetryRecorder` can fold it into per-second waypoints.
///
/// v1 = foreground WhenInUse only. The app already disables the idle timer
/// during a ride so the screen stays on; that keeps location updates flowing
/// without needing the Always permission dance. CLLocationManager dispatches
/// delegate callbacks on the queue that created it — we instantiate on main
/// so all delegate updates land on main.
final class LocationService: NSObject, ObservableObject {

    static let shared = LocationService()

    @Published private(set) var lastLocation: CLLocation?
    @Published private(set) var baroAltitude: Double?   // meters, anchored to GPS
    @Published private(set) var authorized: Bool = false

    private let manager = CLLocationManager()
    private let altimeter = CMAltimeter()
    private var altimeterStarted = false
    private var baseAltitude_m: Double?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            // Updates start in `locationManagerDidChangeAuthorization` once granted.
        case .authorizedAlways, .authorizedWhenInUse:
            authorized = true
            manager.startUpdatingLocation()
            startAltimeterIfPossible()
        default:
            authorized = false
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        if altimeterStarted {
            altimeter.stopRelativeAltitudeUpdates()
            altimeterStarted = false
        }
        baseAltitude_m = nil
    }

    private func startAltimeterIfPossible() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }
        guard !altimeterStarted else { return }
        altimeterStarted = true
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            // Anchor relative altitude to GPS altitude the first time the
            // altimeter emits, so the published value is meters above sea level.
            if self.baseAltitude_m == nil {
                self.baseAltitude_m = self.lastLocation?.altitude
            }
            let relative = data.relativeAltitude.doubleValue
            self.baroAltitude = (self.baseAltitude_m ?? 0) + relative
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        authorized = (status == .authorizedAlways || status == .authorizedWhenInUse)
        if authorized {
            manager.startUpdatingLocation()
            startAltimeterIfPossible()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        lastLocation = last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Degraded but not fatal — recorder writes nil fields for that tick.
    }
}
