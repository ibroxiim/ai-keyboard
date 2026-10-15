import Foundation

enum Translator {
    /// Two parallel calls on the same screenshot: the short one (translation, ~2s) is handed to
    /// `onQuickRead` as soon as it lands, the longer one (suggestions + transcript, ~3s) completes the result.
    /// One slow call producing everything took ~3.3s before anything could be shown.
    /// Throws only if both fail; a failed half is returned as `partialError`.
    /// `knownFriends` lets the model map a cut-off or misread name ("Christi...", "Christima") onto the
    /// friend it already knows, so each screenshot does not create a new friend card.
    static func analyze(
        jpeg: Data, knownFriends: [String], style: String?, onQuickRead: @escaping (QuickRead) -> Void
    ) async throws -> (analysis: ChatAnalysis, partialError: Error?) {
        let detailsTask = Task {
            try await Signposts.measureAsync("details") {
                try await Gemini.generate(
                    ChatDetails.self, system: Prompts.detailsSystem, parts: [.jpeg(jpeg)], schema: Prompts.detailsSchema)
            }
        }
        var quickParts: [Gemini.Part] = [.jpeg(jpeg)]
        if !knownFriends.isEmpty {
            quickParts.insert(.text("Known friends: " + knownFriends.joined(separator: ", ")), at: 0)
        }
        var quick: QuickRead?
        var quickError: Error?
        do {
            quick = try await Signposts.measureAsync("quickRead") {
                try await Gemini.generate(
                    QuickRead.self, system: Prompts.quickSystem(style: style), parts: quickParts, schema: Prompts.quickSchema)
            }
            onQuickRead(quick!)
        } catch {
            quickError = error
        }
        var details: ChatDetails?
        var detailsError: Error?
        do {
            details = try await detailsTask.value
        } catch {
            detailsError = error
        }
        if quick == nil && details == nil { throw quickError ?? detailsError ?? GeminiError.empty }
        return (ChatAnalysis(quick: quick, details: details), quickError ?? detailsError)
    }

    /// A voice message from an Uzbek speaker → what was said, in Latin script. Throws `VoiceError.noSpeech` when the
    /// model heard none.
    static func transcribe(audio: Data, mimeType: String = "audio/mp4") async throws -> String {
        let result = try await Gemini.generate(
            VoiceTranscript.Result.self, system: Prompts.transcribeSystem,
            parts: [.audio(audio, mimeType: mimeType)], schema: Prompts.transcribeSchema)
        return try VoiceTranscript.text(from: result)
    }

    static func rewrite(
        draft: String, context: ChatAnalysis?, friend: Friend?, language: String,
        formality: Friend.Formality?, style: String?
    ) async throws -> [Suggestion] {
        let input = Prompts.rewriteInput(
            draft: draft, context: context, friend: friend, language: language, formality: formality)
        let result = try await Gemini.generate(
            RewriteResult.self, system: Prompts.rewriteSystem(style: style), parts: [.text(input)],
            schema: Prompts.rewriteSchema)
        return result.variants
    }

    private struct RewriteResult: Decodable {
        var variants: [Suggestion]
    }
}
