package com.ibrokhim.aikeyboard.ime.ui

import com.ibrokhim.aikeyboard.data.Friend
import com.ibrokhim.aikeyboard.data.Languages
import com.ibrokhim.aikeyboard.data.SharedState
import com.ibrokhim.aikeyboard.data.Suggestion
import com.ibrokhim.aikeyboard.ime.AiUiState

/** The status row: what the keyboard is doing or showing right now. */
sealed interface Status {
    data class Notice(val text: String) : Status
    data object Reading : Status
    data class Translation(val partner: String, val text: String) : Status
    data object Variants : Status
    data class Failed(val message: String) : Status
    data class Idle(val target: String) : Status
}

/** The chip row under it; `None` collapses the bar to the status row. */
sealed interface Chips {
    data object None : Chips
    data object Preparing : Chips
    data class Replies(val items: List<Suggestion>) : Chips
    data class Picker(val friends: List<Friend>, val languages: List<String>) : Chips
}

data class BarModel(val status: Status, val chips: Chips, val rewriting: Boolean) {
    val expanded: Boolean get() = chips != Chips.None
}

fun barModel(state: SharedState, ui: AiUiState, now: Long): BarModel {
    val context = state.freshContext(now)
    val analyzing = state.isAnalyzing(now)
    val error = state.recentError(now)
    val status = when {
        ui.notice != null -> Status.Notice(ui.notice)
        ui.variants.isNotEmpty() -> Status.Variants
        context != null -> Status.Translation(context.partner, context.lastIncomingUz)
        analyzing -> Status.Reading
        error != null -> Status.Failed(error)
        else -> Status.Idle(targetLabel(state, now))
    }
    val chips = when {
        ui.variants.isNotEmpty() -> Chips.Replies(ui.variants)
        context != null && context.suggestions.isNotEmpty() -> Chips.Replies(context.suggestions)
        analyzing -> Chips.Preparing
        ui.pickerOpen -> Chips.Picker(state.friends, Languages.common.filter { it != state.language(now) })
        else -> Chips.None
    }
    return BarModel(status, chips, ui.rewriting)
}

/** "✨ → 🇬🇧 English · Emma": where ✨ writes to when there is no chat on screen. */
fun targetLabel(state: SharedState, now: Long): String {
    val language = state.language(now)
    val friend = state.activeFriendProfile(now)?.name
    return "✨ → ${Languages.flag(language)} $language" + (friend?.let { " · $it" } ?: "")
}
