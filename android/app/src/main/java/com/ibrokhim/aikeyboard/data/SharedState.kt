package com.ibrokhim.aikeyboard.data

import kotlinx.serialization.Serializable

/** Everything the keyboard, the chat reader and the app share. Times are epoch milliseconds. */
@Serializable
data class SharedState(
    val context: ChatAnalysis? = null,
    val contextDate: Long? = null,
    val analyzingSince: Long? = null,
    val lastError: String? = null,
    val lastErrorDate: Long? = null,
    /** ✨ target when there is no fresh context. Follows the last analysed chat and the keyboard's chips. */
    val targetLanguage: String? = null,
    /** Friend picked in the keyboard (or the last analysed one) — gives ✨ their tone without a chat read. */
    val activeFriend: String? = null,
    /** People seen in chats, most recent first. */
    val friends: List<Friend> = emptyList(),
    /** App setting: the bottom-row КИР/LAT key becomes an emoji key. */
    val emojiKey: Boolean = false,
    /** App setting: read the chat when the keyboard opens in a messenger. */
    val autoRead: Boolean = false,
    /** Hash of the last auto-read chat lines, so an unchanged chat is not sent again. */
    val lastReadHash: String? = null,
    /** App setting: the languages in the keyboard's chip row, in order. Null until edited — then [Languages.defaults]. */
    val languages: List<String>? = null,
    /** App setting: the user's own instructions for how to translate, added to every translation prompt. */
    val translationStyle: String? = null,
    /** App setting: slower models with more thinking for translations. */
    val qualityMode: Boolean = false,
    /** App setting: keep what each friend wrote, and the user's corrections, for ✨. */
    val rememberChats: Boolean = true,
) {
    /** Suggestions from an old chat read are worse than none — the chat has moved on. */
    fun freshContext(now: Long): ChatAnalysis? {
        val context = context ?: return null
        val at = contextDate ?: return null
        return if (now - at < CONTEXT_LIFETIME_MS) context else null
    }

    fun isAnalyzing(now: Long): Boolean = analyzingSince?.let { now - it < ANALYSIS_TIMEOUT_MS } ?: false

    fun recentError(now: Long): String? {
        val at = lastErrorDate ?: return null
        return if (now - at < ERROR_LIFETIME_MS) lastError else null
    }

    fun language(now: Long): String =
        freshContext(now)?.language?.takeIf { it.isNotEmpty() } ?: targetLanguage ?: "English"

    val languageList: List<String> get() = languages ?: Languages.defaults

    /** The friend whose tone ✨ uses when there is no fresh context. */
    fun activeFriendProfile(now: Long): Friend? {
        if (freshContext(now) != null) return null
        return activeFriendRecord
    }

    /** The friend ✨ is writing to — with or without a fresh context. */
    val activeFriendRecord: Friend?
        get() {
            val name = activeFriend ?: return null
            return friends.firstOrNull { it.name == name }
        }

    /** The formality the user picked for that friend. */
    val chosenFormality: Friend.Formality? get() = activeFriendRecord?.formality

    /** What the active friend wrote and was written, for ✨; nothing while chat memory is off. */
    val rememberedMessages: List<ChatLine>
        get() = if (!rememberChats) emptyList() else activeFriendRecord?.history.orEmpty()

    /** The active friend's corrections, for ✨; nothing while chat memory is off. */
    val rememberedExamples: List<Friend.Example>
        get() = if (!rememberChats) emptyList() else activeFriendRecord?.examples.orEmpty()

    /** The analysed partner becomes the newest friend and the ✨ target; what the user decided about them stays. */
    fun remember(analysis: ChatAnalysis, now: Long): SharedState {
        // Empty when the quick half failed — keep what we knew.
        if (analysis.language.isEmpty()) return this
        if (analysis.partner.isEmpty()) return copy(targetLanguage = analysis.language, activeFriend = null)
        val same = friends.filter { Friend.isSamePerson(it.name, analysis.partner) }
        val name = Friend.bestName(listOf(analysis.partner) + same.map { it.name })
        val others = friends.filterNot { Friend.isSamePerson(it.name, analysis.partner) }
        val history = if (!rememberChats) null else
            ChatHistory.merged(same.firstNotNullOfOrNull { it.history }.orEmpty(), analysis.transcript)
        val friend = Friend(
            name = name, language = analysis.language, tone = analysis.tone, lastSeen = now,
            formality = same.firstNotNullOfOrNull { it.formality },
            history = history,
            notes = same.firstNotNullOfOrNull { it.notes },
            examples = if (!rememberChats) null else same.firstNotNullOfOrNull { it.examples },
        )
        return copy(targetLanguage = analysis.language, friends = (listOf(friend) + others).take(MAX_FRIENDS), activeFriend = name)
    }

    fun forgetFriend(name: String): SharedState =
        copy(friends = friends.filterNot { it.name == name }, activeFriend = activeFriend.takeUnless { it == name })

    fun updateFriend(name: String, change: (Friend) -> Friend): SharedState =
        copy(friends = friends.map { if (it.name == name) change(it) else it })

    /** Turning memory off also forgets what was already saved. */
    fun setRememberChats(on: Boolean): SharedState {
        if (on) return copy(rememberChats = true)
        return copy(rememberChats = false, friends = friends.map { it.copy(history = null, examples = null) })
    }

    /** The correction goes to the friend ✨ was writing to; nothing is kept while chat memory is off. */
    fun learn(example: Friend.Example): SharedState {
        if (!rememberChats) return this
        val name = activeFriend ?: return this
        if (friends.none { it.name == name }) return this
        return updateFriend(name) { it.learn(example) }
    }

    /**
     * Merges entries `Friend.isSamePerson` considers one person. The list is most-recent-first, so the
     * first entry keeps its language and tone; the name becomes the most complete one.
     */
    fun mergeDuplicateFriends(): SharedState {
        val merged = mutableListOf<Friend>()
        for (friend in friends) {
            val index = merged.indexOfFirst { Friend.isSamePerson(it.name, friend.name) }
            if (index >= 0) {
                val kept = merged[index]
                merged[index] = kept.copy(
                    name = Friend.bestName(listOf(kept.name, friend.name)),
                    formality = kept.formality ?: friend.formality,
                    history = kept.history ?: friend.history,
                    notes = kept.notes ?: friend.notes,
                    examples = kept.examples ?: friend.examples,
                )
            } else {
                merged.add(friend)
            }
        }
        if (merged == friends) return this
        val active = activeFriend?.let { name -> merged.firstOrNull { Friend.isSamePerson(it.name, name) }?.name }
        return copy(friends = merged, activeFriend = active ?: activeFriend)
    }

    companion object {
        const val CONTEXT_LIFETIME_MS = 15 * 60 * 1000L
        const val ANALYSIS_TIMEOUT_MS = 60 * 1000L
        const val ERROR_LIFETIME_MS = 120 * 1000L
        const val MAX_FRIENDS = 8
    }
}
