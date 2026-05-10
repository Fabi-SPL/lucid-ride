import Foundation

/// Minimal, crash-proof build identification for LucidRide.
/// Plain string constants — no Info.plist reads, no Bundle lookups.
/// `commitHash` and `buildDate` are overwritten by GitHub Actions before
/// `xcodebuild` runs (see .github/workflows/build-lucidride.yml).
enum BuildInfo {
    static let commitHash: String = "local-dev"
    static let buildDate:  String = "unknown"
    static let codeVersion: String = "v1"
    static let appName: String = "LucidRide"
}
