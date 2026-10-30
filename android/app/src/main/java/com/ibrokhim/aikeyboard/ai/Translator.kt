package com.ibrokhim.aikeyboard.ai

import com.ibrokhim.aikeyboard.data.ChatAnalysis
import com.ibrokhim.aikeyboard.data.ChatDetails
import com.ibrokhim.aikeyboard.data.ChatLine
import com.ibrokhim.aikeyboard.data.ClipboardRead
import com.ibrokhim.aikeyboard.data.Friend
import com.ibrokhim.aikeyboard.data.QuickRead
import com.ibrokhim.aikeyboard.data.RewriteTweak
import com.ibrokhim.aikeyboard.data.SharedStore
import com.ibrokhim.aikeyboard.data.Suggestion
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.Serializable

sealed interface ChatInput {
    /** Tagged lines read by the accessibility service: "[TOP] Emma", "[L] u free?", "[R] maybe". */
    data class Transcript(val lines: List<String>) : ChatInput

    /** Fallback for apps that draw text the accessibility tree cannot see. */
    class Screenshot(val jpeg: ByteArray) : ChatInput
}

data class AnalyzeResult(val analysis: ChatAnalysis, val partialError: Throwable?)

class Translator(private val llm: LlmClient) {
    /**
     * Two parallel calls on the same chat: the short one (translation) is handed to [onQuickRead] as soon
     * as it lands, the longer one (suggestions + transcript) completes the result. Throws only if both fail.
     * [friends] lets the model map a cut-off or misread name onto a friend it already knows, and brings the
     * user's notes about them.
     */
    suspend fun analyze(
        input: ChatInput,
        friends: List<Friend>,
        style: String? = null,
        quality: GeminiQuality = GeminiQuality.FAST,
        onQuickRead: (QuickRead) -> Unit,
    ): AnalyzeResult = coroutineScope {
        val (basics, content) = when (input) {
            is ChatInput.Transcript -> Prompts.transcriptBasics to listOf(Part.Text(input.lines.joinToString("\n")))
            is ChatInput.Screenshot -> Prompts.screenshotBasics to listOf(Part.Jpeg(input.jpeg))
        }
        val parts = Prompts.knownFriendsPart(friends)?.let { listOf(Part.Text(it)) + content } ?: content
        val details = async {
            runCatchingNonCancel {
                val text = llm.generate(Prompts.details(basics), parts, Prompts.detailsSchema, quality)
                SharedStore.json.decodeFromString(ChatDetails.serializer(), text)
            }
        }
        val quick = runCatchingNonCancel {
            val text = llm.generate(Prompts.quick(basics, style), parts, Prompts.quickSchema, quality)
            SharedStore.json.decodeFromString(QuickRead.serializer(), text)
        }
        quick.getOrNull()?.let(onQuickRead)
        val detailsResult = details.await()
        val quickError = quick.exceptionOrNull()
        val detailsError = detailsResult.exceptionOrNull()
        if (quickError != null && detailsError != null) throw quickError
        AnalyzeResult(ChatAnalysis.of(quick.getOrNull(), detailsResult.getOrNull()), quickError ?: detailsError)
    }

    suspend fun rewrite(
        draft: String,
        context: ChatAnalysis?,
        friend: Friend?,
        language: String,
        formality: Friend.Formality? = null,
        history: List<ChatLine> = emptyList(),
        notes: String? = null,
        tweaks: List<RewriteTweak> = emptyList(),
        examples: List<Friend.Example> = emptyList(),
        style: String? = null,
        quality: GeminiQuality = GeminiQuality.FAST,
    ): List<Suggestion> {
        val input = Prompts.rewriteInput(draft, context, friend, language, formality, history, notes, tweaks, examples)
        val text = llm.generate(Prompts.rewriteSystem(style), listOf(Part.Text(input)), Prompts.rewriteSchema, quality)
        return SharedStore.json.decodeFromString(RewriteResult.serializer(), text).variants
    }

    /**
     * The copied text → translation, summary and replies, as a [ChatAnalysis] for the shared state. The active
     * friend's notes go along, like with a chat read; the other friends' do not — the text is for this chat.
     */
    suspend fun readClipboard(
        text: String,
        partner: Friend?,
        style: String? = null,
        quality: GeminiQuality = GeminiQuality.FAST,
    ): ChatAnalysis {
        val parts = mutableListOf<Part>()
        val notes = Prompts.capped(partner?.notes)
        if (partner != null && notes != null) parts += Part.Text("The user's notes about ${partner.name}, who wrote this:\n$notes")
        parts += Part.Text("Copied text:\n$text")
        val answer = llm.generate(Prompts.clipboardSystem(style), parts, Prompts.clipboardSchema, quality)
        return SharedStore.json.decodeFromString(ClipboardRead.serializer(), answer).analysis(partner?.name.orEmpty(), text)
    }

    @Serializable
    private data class RewriteResult(val variants: List<Suggestion>)
}
