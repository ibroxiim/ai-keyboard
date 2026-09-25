package com.ibrokhim.aikeyboard.data

object Languages {
    val common = listOf(
        "English", "Korean", "Russian", "Turkish", "Japanese", "Chinese",
        "Arabic", "German", "Spanish", "French",
    )

    fun flag(language: String): String = when (language.lowercase()) {
        "english" -> "🇬🇧"
        "korean" -> "🇰🇷"
        "russian" -> "🇷🇺"
        "turkish" -> "🇹🇷"
        "japanese" -> "🇯🇵"
        "chinese" -> "🇨🇳"
        "arabic" -> "🇸🇦"
        "german" -> "🇩🇪"
        "spanish" -> "🇪🇸"
        "french" -> "🇫🇷"
        "italian" -> "🇮🇹"
        "portuguese" -> "🇵🇹"
        "hindi" -> "🇮🇳"
        "indonesian" -> "🇮🇩"
        "kazakh" -> "🇰🇿"
        "uzbek" -> "🇺🇿"
        else -> "🌐"
    }
}
