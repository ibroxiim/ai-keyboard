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

    /** The friend whose tone ✨ uses when there is no fresh context. */
    fun activeFriendProfile(now: Long): Friend? {
        if (freshContext(now) != null) return null
        val name = activeFriend ?: return null
        return friends.firstOrNull { it.name == name }
    }

    /** The analysed partner becomes the newest friend and the ✨ target. */
    fun remember(analysis: ChatAnalysis, now: Long): SharedState {
        // Empty when the quick half failed — keep what we knew.
        if (analysis.language.isEmpty()) return this
        if (analysis.partner.isEmpty()) return copy(targetLanguage = analysis.language, activeFriend = null)
        val same = friends.filter { Friend.isSamePerson(it.name, analysis.partner) }
        val name = Friend.bestName(listOf(analysis.partner) + same.map { it.name })
        val others = friends.filterNot { Friend.isSamePerson(it.name, analysis.partner) }
        val list = (listOf(Friend(name, analysis.language, analysis.tone, now)) + others).take(MAX_FRIENDS)
        return copy(targetLanguage = analysis.language, friends = list, activeFriend = name)
    }

    fun forgetFriend(name: String): SharedState =
        copy(friends = friends.filterNot { it.name == name }, activeFriend = activeFriend.takeUnless { it == name })

    /**
     * Merges entries `Friend.isSamePerson` considers one person. The list is most-recent-first, so the
     * first entry keeps its language and tone; the name becomes the most complete one.
     */
    fun mergeDuplicateFriends(): SharedState {
        val merged = mutableListOf<Friend>()
        for (friend in friends) {
            val index = merged.indexOfFirst { Friend.isSamePerson(it.name, friend.name) }
            if (index >= 0) {
                merged[index] = merged[index].copy(name = Friend.bestName(listOf(merged[index].name, friend.name)))
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
