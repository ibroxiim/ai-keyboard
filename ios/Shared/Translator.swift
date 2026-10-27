import Foundation

enum Translator {
    /// Two parallel calls on the same screenshot: the short one (translation, ~2s) is handed to
    /// `onQuickRead` as soon as it lands, the longer one (suggestions + transcript, ~3s) completes the result.
    /// One slow call producing everything took ~3.3s before anything could be shown.
    /// Throws only if both fail; a failed half is returned as `partialError`.
    /// `friends` lets the model map a cut-off or misread name ("Christi...", "Christima") onto the friend it
    /// already knows, so each screenshot does not create a new friend card, and brings the user's notes about them.
    static func analyze(
        jpeg: Data, friends: [Friend], style: String?, quality: GeminiQuality = .fast,
        onQuickRead: @escaping (QuickRead) -> Void
    ) async throws -> (analysis: ChatAnalysis, partialError: Error?) {
        var parts: [Gemini.Part] = [.jpeg(jpeg)]
        if let known = Prompts.knownFriendsPart(friends) { parts.insert(.text(known), at: 0) }
        let detailsTask = Task {
            try await Signposts.measureAsync("details") {
                try await Gemini.generate(
                    ChatDetails.self, system: Prompts.detailsSystem, parts: parts, schema: Prompts.detailsSchema,
                    quality: quality)
            }
        }
        var quick: QuickRead?
        var quickError: Error?
        do {
            quick = try await Signposts.measureAsync("quickRead") {
                try await Gemini.generate(
                    QuickRead.self, system: Prompts.quickSystem(style: style), parts: parts, schema: Prompts.quickSchema,
                    quality: quality)
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
        formality: Friend.Formality?, history: [ChatAnalysis.Line], notes: String?, style: String?,
        tweaks: [RewriteTweak] = [], examples: [Friend.Example] = [], quality: GeminiQuality = .fast
    ) async throws -> [Suggestion] {
        let input = Prompts.rewriteInput(
            draft: draft, context: context, friend: friend, language: language, formality: formality,
            history: history, notes: notes, tweaks: tweaks, examples: examples)
        let result = try await Gemini.generate(
            RewriteResult.self, system: Prompts.rewriteSystem(style: style), parts: [.text(input)],
            schema: Prompts.rewriteSchema, quality: quality)
        return result.variants
    }

    private struct RewriteResult: Decodable {
        var variants: [Suggestion]
    }
}

extension Translator {
    /// The copied text → translation, summary and replies, as a `ChatAnalysis` for the shared state. The active
    /// friend's notes go along, like with a screenshot; the other friends' do not — the text is for this chat.
    static func readClipboard(
        text: String, partner: Friend?, style: String?, quality: GeminiQuality = .fast
    ) async throws -> ChatAnalysis {
        var parts: [Gemini.Part] = []
        if let partner, let notes = Prompts.capped(partner.notes) {
            parts.append(.text("The user's notes about \(partner.name), who wrote this:\n" + notes))
        }
        parts.append(.text("Copied text:\n" + text))
        let read = try await Gemini.generate(
            ClipboardRead.self, system: Prompts.clipboardSystem(style: style), parts: parts,
            schema: Prompts.clipboardSchema, quality: quality)
        return read.analysis(partner: partner?.name ?? "", text: text)
    }
}
