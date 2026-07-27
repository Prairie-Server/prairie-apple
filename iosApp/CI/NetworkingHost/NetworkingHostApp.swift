import SwiftUI

/// Minimal `@main` host for Networking-scoped CI tests.
///
/// Built without FFmpeg/Nuke so the coverage gate does not pay for the full
/// Prairie.app link. Product module name is `Prairie` so existing
/// `@testable import Prairie` test sources work unchanged.
@main
struct NetworkingHostApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Prairie Networking CI Host")
                .padding()
        }
    }
}
