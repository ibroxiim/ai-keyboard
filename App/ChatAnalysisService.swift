import UIKit

enum ChatAnalysisService {
    /// Screenshot → Gemini → shared state. The keyboard is told through the Darwin notification
    /// that `SharedStore.update` posts, so it can show "reading…" and then the suggestions.
    @discardableResult
    static func run(imageData: Data, fromShortcut: Bool) async throws -> ChatAnalysis {
        SharedStore.update {
            $0.analyzingSince = Date()
            // A new Back Tap means a new chat — the previous chat's suggestions must not linger.
            $0.context = nil
            $0.contextDate = nil
            // Proof for the setup checklist that the shortcut exists and runs.
            if fromShortcut { $0.shortcutRunDate = Date() }
        }
        do {
            let jpeg = try ScreenshotImage.jpeg(from: imageData)
            let known = SharedStore.load().friends?.map(\.name) ?? []
            let (analysis, partialError) = try await Translator.analyze(jpeg: jpeg, knownFriends: known) { quick in
                // Keyboard shows the translation now; suggestions follow when the second call lands.
                SharedStore.update {
                    $0.context = ChatAnalysis(quick: quick, details: nil)
                    $0.contextDate = Date()
                }
            }
            SharedStore.update {
                $0.context = analysis
                $0.contextDate = Date()
                $0.analyzingSince = nil
                $0.lastError = partialError?.localizedDescription
                $0.lastErrorDate = partialError == nil ? nil : Date()
                $0.remember(analysis)
            }
            return analysis
        } catch {
            SharedStore.update {
                $0.analyzingSince = nil
                $0.lastError = error.localizedDescription
                $0.lastErrorDate = Date()
            }
            throw error
        }
    }
}

enum ScreenshotImage {
    /// 720px wide keeps chat text readable for the model while making the upload ~10x smaller
    /// than a raw 1179px PNG screenshot.
    static func jpeg(from data: Data, maxWidth: CGFloat = 720) throws -> Data {
        guard let image = UIImage(data: data) else { throw AppError(message: "Skrinshotni o'qib bo'lmadi") }
        let scale = min(1, maxWidth / image.size.width)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.7) else {
            throw AppError(message: "Skrinshotni siqib bo'lmadi")
        }
        return jpeg
    }
}
