import SwiftUI

@main
struct TarjimonApp: App {
    init() {
        DiagnosticsStore.migrateLegacyFile()
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
