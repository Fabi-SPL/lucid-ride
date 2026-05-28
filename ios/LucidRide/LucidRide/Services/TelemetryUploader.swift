import Foundation
import BackgroundTasks

/// Resilient late-flush for telemetry that didn't make it to Supabase before
/// the ride ended in a no-signal area (mountain pass, tunnel, rural ride).
///
/// When the recorder's `flush()` fails with a network error, it serializes
/// the batch to disk under `Application Support/lucidride/pending/<uuid>.json`.
/// On END RIDE we submit a `BGProcessingTaskRequest` so the system schedules
/// a CPU slot when the device has signal — without requiring the app to be
/// foregrounded. Handler retries each pending batch and deletes on success.
///
/// Safe to call from anywhere. Best-effort throughout — disk write failures,
/// network failures, BG-budget exhaustion all degrade gracefully.
final class TelemetryUploader {

    static let shared = TelemetryUploader()
    static let taskIdentifier = "com.fabi.lucidride.telemetry-flush"

    private init() {}

    private var pendingDir: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("lucidride/pending", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var hasPendingBatches: Bool {
        guard let dir = pendingDir,
              let contents = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return false
        }
        return !contents.isEmpty
    }

    /// Persist a failed batch to disk so the background task can retry it.
    /// Body is the array-of-dicts that was about to POST to /rest/v1/ride_telemetry.
    func stashFailedBatch(_ body: [[String: Any]]) {
        guard let dir = pendingDir else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        let file = dir.appendingPathComponent("\(UUID().uuidString).json")
        try? data.write(to: file, options: .atomic)
    }

    /// Submit a BGProcessingTaskRequest. The system schedules it when the
    /// device has signal + power (we don't require power). Idempotent — call
    /// freely from the recorder's stop() path.
    func scheduleFlushIfNeeded() {
        guard hasPendingBatches else { return }
        let req = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        req.requiresNetworkConnectivity = true
        req.requiresExternalPower = false
        req.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        try? BGTaskScheduler.shared.submit(req)
    }

    /// Register the task handler. Call once from App.init or .task.
    func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false); return
            }
            Task { await self.runFlush(task: processingTask) }
        }
    }

    /// Foreground flush — called automatically when the app re-enters
    /// foreground with pending batches on disk. Cheaper than waiting for
    /// the system to schedule the BG task.
    func flushPendingNow() async {
        await runFlush(task: nil)
    }

    // MARK: - Internals

    private func runFlush(task: BGProcessingTask?) async {
        let deadline = Date().addingTimeInterval(25)  // BG slot is ~30s; bail at 25s
        guard let dir = pendingDir else {
            task?.setTaskCompleted(success: true); return
        }

        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            if Date() > deadline { break }
            if task?.expirationHandler != nil { /* expiration registered */ }

            guard let data = try? Data(contentsOf: file),
                  let body = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let req = buildBatchRequest(body: body) else {
                try? FileManager.default.removeItem(at: file) // corrupt file — drop
                continue
            }
            do {
                let (_, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    try? FileManager.default.removeItem(at: file)
                }
                // 4xx/5xx → leave file in place; next attempt will retry
            } catch {
                // Network failure — leave file, retry later
            }
        }
        task?.setTaskCompleted(success: true)

        // If anything still pending, reschedule (system permitting).
        if hasPendingBatches { scheduleFlushIfNeeded() }
    }

    private func buildBatchRequest(body: [[String: Any]]) -> URLRequest? {
        let supabase = SupabaseClient.shared
        guard let url = URL(string: "\(supabase.baseURL)/rest/v1/ride_telemetry") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(supabase.anonKey,             forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(supabase.anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json",           forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }
}
