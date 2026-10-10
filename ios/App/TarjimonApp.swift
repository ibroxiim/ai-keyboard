import SwiftUI

@main
struct TarjimonApp: App {
    @StateObject private var voice = VoiceController.live()
    /// The keyboard's ⏹ arrives as a Darwin notification, also while the app is in the background recording.
    @State private var stopObserver: DarwinObserver?

    init() {
        DiagnosticsStore.migrateLegacyFile()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(voice)
                .onOpenURL { voice.handle(url: $0) }
                .task {
                    stopObserver = DarwinObserver(name: AppGroup.voiceStopRequested) { [weak controller = voice] in
                        controller?.stop()
                    }
                }
        }
    }
}
