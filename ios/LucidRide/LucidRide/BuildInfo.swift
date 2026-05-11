import Foundation

/// Minimal, crash-proof build identification for LucidRide.
/// `commitHash` and `buildDate` are overwritten by GitHub Actions before
/// `xcodebuild` runs (see .github/workflows/build-lucidride.yml).
/// `codeVersion` is read live from Info.plist so it always reflects the
/// actually-installed CFBundleShortVersionString / CFBundleVersion.
enum BuildInfo {
    static let commitHash: String = "local-dev"
    static let buildDate:  String = "unknown"
    static let appName: String = "LucidRide"

    static var codeVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(v) (build \(b))"
    }
}
