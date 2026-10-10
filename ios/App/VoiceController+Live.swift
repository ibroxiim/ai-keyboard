import UIKit

extension VoiceController {
    /// The controller wired to the real microphone, Gemini and the shared state.
    static func live() -> VoiceController {
        let recorder = AVRecorder()
        let controller = VoiceController(
            recorder: recorder,
            transcriber: { try await Translator.transcribe(audio: $0) },
            update: { change in SharedStore.update(change) },
            // The keyboard's ⏹ can arrive with the app in the background; without this iOS may suspend it
            // between the recording ending and the transcript landing.
            runInBackground: { work in
                let task = UIApplication.shared.beginBackgroundTask(withName: "voice-transcribe")
                await work()
                UIApplication.shared.endBackgroundTask(task)
            })
        recorder.onInterruption = { [weak controller] in controller?.stop() }
        return controller
    }
}
