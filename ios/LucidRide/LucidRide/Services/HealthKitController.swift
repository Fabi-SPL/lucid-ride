import Foundation
import HealthKit
import CoreLocation

/// Logs each LucidRide ride as a workout in the iOS Health app so the time
/// counts toward Activity rings. Uses HKWorkoutBuilder + HKWorkoutRouteBuilder
/// for the GPS track. Heart rate already lives in HealthKit via the Watch +
/// Health Bridge pipeline so we don't duplicate it here.
///
/// Honest scope: this is best-effort. If the user denies Health permissions
/// or HKHealthStore is unavailable, all methods become no-ops and the rest
/// of the recorder continues working.
final class HealthKitController {

    static let shared = HealthKitController()

    private let store = HKHealthStore()
    private var builder: HKWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var ridePending: Bool = false

    private init() {}

    /// Request authorization. Safe to call multiple times — iOS de-dupes the
    /// system permission prompt. Returns true if Health is available + user
    /// has not explicitly denied; the user's actual grant is opaque to us
    /// (Apple HIG) so we always attempt to write and check the error later.
    func requestAuthorizationIfNeeded() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let writeTypes: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: [])
            return true
        } catch {
            return false
        }
    }

    /// Begin a workout-builder session. Call when startRide succeeds.
    func startWorkout(startedAt: Date) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        ridePending = true

        let config = HKWorkoutConfiguration()
        config.activityType = .cycling   // closest match — Apple has no .motorcycling on iOS
        config.locationType = .outdoor

        let b = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        let rb = HKWorkoutRouteBuilder(healthStore: store, device: .local())
        self.builder = b
        self.routeBuilder = rb

        Task {
            // Request permission lazily — does nothing if already granted.
            _ = await requestAuthorizationIfNeeded()
            do {
                try await b.beginCollection(at: startedAt)
            } catch {
                // Permission denied or system error — stop tracking but don't crash.
                self.builder = nil
                self.routeBuilder = nil
                self.ridePending = false
            }
        }
    }

    /// Push a single GPS fix into the route builder. Called from the recorder's
    /// 1 Hz sampler. iOS automatically aggregates into a series.
    func addLocation(_ loc: CLLocation) {
        guard ridePending, let rb = routeBuilder else { return }
        rb.insertRouteData([loc]) { _, _ in
            // Best-effort — failures are non-fatal.
        }
    }

    /// Finalize the workout, save the route, persist to HealthKit.
    ///
    /// Hard-bounded to 8 s: HealthKit's finish calls can stall (pending
    /// permission, busy store), and this used to run inline on the END path
    /// and freeze the ride teardown. We now stop awaiting after the timeout
    /// and let the (uncancellable) HK work finish on its own; the ride is
    /// already safe in Supabase either way.
    func finishWorkout(endedAt: Date) async {
        guard let b = builder else { return }
        defer {
            self.builder = nil
            self.routeBuilder = nil
            self.ridePending = false
        }
        let rb = routeBuilder
        await withTimeout(8) {
            do {
                try await b.endCollection(at: endedAt)
                let workout = try await b.finishWorkout()
                if let workout, let rb {
                    try? await rb.finishRoute(with: workout, metadata: nil)
                }
            } catch {
                // Best-effort. The ride is still safely recorded in Supabase.
            }
        }
    }

    /// Runs `op`, but stops awaiting after `seconds`. The underlying HealthKit
    /// work isn't cancellable, so it may complete in the background — we just
    /// don't block the caller on it.
    private func withTimeout(_ seconds: Double, _ op: @escaping @Sendable () async -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await op() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            _ = await group.next()   // return as soon as EITHER finishes
            group.cancelAll()
        }
    }
}
