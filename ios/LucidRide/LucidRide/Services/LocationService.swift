import Foundation
import CoreLocation
import CoreMotion

/// Wraps `CLLocationManager` (GPS) + `CMAltimeter` (barometric altitude) for
/// ride telemetry recording. Publishes the latest fix so
/// `RideTelemetryRecorder` can fold it into per-second waypoints.
///
/// Background-capable WhenInUse: we enable `allowsBackgroundLocationUpdates`
/// + the blue background indicator, so location keeps flowing (and the 1 Hz
/// recorder timers keep firing) even when the screen locks, music takes over,
/// or the phone goes in a pocket. Without this the app suspended mid-ride and
/// logged ZERO waypoints (Fabi, 2026-06-04). No "Always" permission needed —
/// "While Using" + background updates + visible indicator is enough for a
/// session that starts in the foreground. CLLocationManager dispatches
/// delegate callbacks on the queue that created it — we instantiate on main
/// so all delegate updates land on main.
final class LocationService: NSObject, ObservableObject {

    static let shared = LocationService()

    @Published private(set) var lastLocation: CLLocation?
    @Published private(set) var baroAltitude: Double?   // meters, anchored to GPS
    @Published private(set) var authorized: Bool = false

    /// True compass bearing in degrees (0-360). Updated via `startUpdatingHeading()`
    /// — works at standstill, unlike `CLLocation.course` which drops out below ~5 km/h.
    /// nil until the user moves the phone (compass calibration) or accuracy goes
    /// negative (interference).
    @Published private(set) var compassHeading: Double?
    @Published private(set) var compassAccuracy: Double?

    private let manager = CLLocationManager()
    private let altimeter = CMAltimeter()
    private var altimeterStarted = false
    private var baseAltitude_m: Double?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone   // continuous 1 Hz fixes → reliable Doppler speed
        manager.activityType = .otherNavigation
        manager.headingFilter = 2.0          // only fire on 2°+ heading change
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true   // keep recording when locked / music / pocket
        manager.showsBackgroundLocationIndicator = true  // honest blue pill while a ride records
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            // Updates start in `locationManagerDidChangeAuthorization` once granted.
        case .authorizedAlways, .authorizedWhenInUse:
            authorized = true
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                manager.startUpdatingHeading()
            }
            startAltimeterIfPossible()
        default:
            authorized = false
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.stopUpdatingHeading()
        }
        if altimeterStarted {
            altimeter.stopRelativeAltitudeUpdates()
            altimeterStarted = false
        }
        baseAltitude_m = nil
        compassHeading = nil
        compassAccuracy = nil
    }

    /// Best-available bearing: compass at standstill / low-speed, GPS course
    /// at speed. `CLLocation.course` is invalid below ~5 km/h.
    var displayHeading: Double? {
        let speed = lastLocation?.speed ?? -1
        if speed < (5.0 / 3.6) {
            return compassHeading
        }
        if let course = lastLocation?.course, course >= 0 {
            return course
        }
        return compassHeading
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
            if CLLocationManager.headingAvailable() {
                manager.startUpdatingHeading()
            }
            startAltimeterIfPossible()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        lastLocation = last
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Negative accuracy = invalid (magnetic interference, uncalibrated).
        guard newHeading.headingAccuracy >= 0 else {
            compassHeading = nil
            compassAccuracy = nil
            return
        }
        compassHeading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        compassAccuracy = newHeading.headingAccuracy
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Degraded but not fatal — recorder writes nil fields for that tick.
    }
}
