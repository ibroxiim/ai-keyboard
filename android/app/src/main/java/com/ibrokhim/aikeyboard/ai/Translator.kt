package com.ibrokhim.aikeyboard.ai

import com.ibrokhim.aikeyboard.data.ChatAnalysis
import com.ibrokhim.aikeyboard.data.ChatDetails
import com.ibrokhim.aikeyboard.data.Friend
import com.ibrokhim.aikeyboard.data.QuickRead
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
     * [knownFriends] lets the model map a cut-off or misread name onto a friend it already knows.
     */
    suspend fun analyze(
        input: ChatInput,
        knownFriends: List<String>,
        onQuickRead: (QuickRead) -> Unit,
    ): AnalyzeResult = coroutineScope {
        val (basics, content) = when (input) {
            is ChatInput.Transcript -> Prompts.transcriptBasics to listOf(Part.Text(input.lines.joinToString("\n")))
            is ChatInput.Screenshot -> Prompts.screenshotBasics to listOf(Part.Jpeg(input.jpeg))
        }
        val details = async {
            runCatchingNonCancel {
                val text = llm.generate(Prompts.details(basics), content, Prompts.detailsSchema)
                SharedStore.json.decodeFromString(ChatDetails.serializer(), text)
            }
        }
        val quickParts = if (knownFriends.isEmpty()) {
            content
        } else {
            listOf(Part.Text("Known friends: " + knownFriends.joinToString(", "))) + content
        }
        val quick = runCatchingNonCancel {
            val text = llm.generate(Prompts.quick(basics), quickParts, Prompts.quickSchema)
            SharedStore.json.decodeFromString(QuickRead.serializer(), text)
        }
        quick.getOrNull()?.let(onQuickRead)
        val detailsResult = details.await()
        val quickError = quick.exceptionOrNull()
        val detailsError = detailsResult.exceptionOrNull()
        if (quickError != null && detailsError != null) throw quickError
        AnalyzeResult(ChatAnalysis.of(quick.getOrNull(), detailsResult.getOrNull()), quickError ?: detailsError)
    }

    suspend fun rewrite(draft: String, context: ChatAnalysis?, friend: Friend?, language: String): List<Suggestion> {
        val input = Prompts.rewriteInput(draft, context, friend, language)
        val text = llm.generate(Prompts.rewriteSystem, listOf(Part.Text(input)), Prompts.rewriteSchema)
        return SharedStore.json.decodeFromString(RewriteResult.serializer(), text).variants
    }

    @Serializable
    private data class RewriteResult(val variants: List<Suggestion>)
}
