import WidgetKit
import SwiftUI

/// Widget extension entry point. Currently exposes only the Live Activity
/// (Dynamic Island + Lock Screen ride card). Home-screen widget could be
/// added here later by including additional Widget bodies.
@main
struct LucidRideWidgetBundle: WidgetBundle {
    var body: some Widget {
        RideLiveActivity()
    }
}
