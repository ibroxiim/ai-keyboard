package com.ibrokhim.aikeyboard.ime.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ibrokhim.aikeyboard.data.Languages
import com.ibrokhim.aikeyboard.data.Suggestion
import com.ibrokhim.aikeyboard.ime.KeyboardAi
import com.ibrokhim.aikeyboard.ime.KeyboardTheme

private class BarColors(theme: KeyboardTheme) {
    val background = Color(theme.background)
    val ink = Color(theme.label)
    val muted = Color(theme.label).copy(alpha = 0.6f)
    val chip = Color(theme.key)
    val accent = Color(theme.accent)
    val onAccent = Color(theme.onAccent)
}

/** Status row (+ chip row when it has something) above the keys — the iOS `SuggestionBar`. */
@Composable
fun SuggestionBar(model: BarModel, theme: KeyboardTheme, ai: KeyboardAi, onRead: () -> Unit) {
    val colors = BarColors(theme)
    Column(
        Modifier
            .fillMaxWidth()
            .background(colors.background)
            .padding(start = 8.dp, end = 8.dp, top = 6.dp, bottom = if (model.expanded) 4.dp else 6.dp),
    ) {
        Row(Modifier.fillMaxWidth().height(36.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) { StatusRow(model.status, colors, ai, onRead) }
            Spacer(Modifier.width(8.dp))
            MagicButton(model.rewriting, colors) { ai.magic() }
        }
        if (model.expanded) {
            Spacer(Modifier.height(6.dp))
            Box(Modifier.fillMaxWidth().height(58.dp)) { ChipRow(model.chips, colors, ai) }
        }
    }
}

@Composable
private fun StatusRow(status: Status, colors: BarColors, ai: KeyboardAi, onRead: () -> Unit) {
    when (status) {
        is Status.Notice -> Line(status.text, colors.muted)
        Status.Reading -> Busy("Suhbat o'qilmoqda…", colors)
        is Status.Translation -> Row(verticalAlignment = Alignment.CenterVertically) {
            val who = status.partner.ifEmpty { "Suhbatdosh" }
            Text(
                "💬 $who: ${status.text}", color = colors.ink, fontSize = 13.sp, lineHeight = 16.sp,
                maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
            )
            Close(colors) { ai.dismissContext() }
        }
        Status.Variants -> Row(verticalAlignment = Alignment.CenterVertically) {
            Text("✨ Variantlar — birini tanlang", color = colors.ink, fontSize = 13.sp, modifier = Modifier.weight(1f))
            Close(colors) { ai.dismissVariants() }
        }
        is Status.Failed -> Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                "⚠ ${status.message}", color = colors.muted, fontSize = 13.sp, maxLines = 1,
                overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
            )
            Pill("📖 Qayta", colors, accent = true, onClick = onRead)
        }
        is Status.Idle -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Pill("📖 Chatni o'qish", colors, accent = true, onClick = onRead)
            Pill(status.target + " ▾", colors, accent = false) { ai.togglePicker() }
        }
    }
}

@Composable
private fun ChipRow(chips: Chips, colors: BarColors, ai: KeyboardAi) {
    when (chips) {
        Chips.None -> Unit
        Chips.Preparing -> Busy("Javoblar tayyorlanmoqda…", colors)
        is Chips.Replies -> LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(chips.items) { suggestion -> ReplyChip(suggestion, colors) { ai.pick(suggestion) } }
        }
        is Chips.Picker -> LazyRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            items(chips.friends) { friend ->
                Pill("${friend.name} · ${Languages.flag(friend.language)}", colors, accent = false) { ai.selectFriend(friend) }
            }
            items(chips.languages) { language ->
                Pill("${Languages.flag(language)} $language", colors, accent = false) { ai.selectLanguage(language) }
            }
        }
    }
}

@Composable
private fun ReplyChip(suggestion: Suggestion, colors: BarColors, onClick: () -> Unit) {
    Column(
        Modifier
            .fillMaxHeight()
            .widthIn(max = 250.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(colors.chip)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 6.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            suggestion.text, color = colors.ink, fontSize = 14.sp, lineHeight = 17.sp,
            fontWeight = FontWeight.Medium, maxLines = 2, overflow = TextOverflow.Ellipsis,
        )
        Text(suggestion.uz, color = colors.muted, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun Pill(text: String, colors: BarColors, accent: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .height(32.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(if (accent) colors.accent else colors.chip)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text, color = if (accent) colors.onAccent else colors.ink, fontSize = 13.sp,
            fontWeight = FontWeight.Medium, maxLines = 1,
        )
    }
}

@Composable
private fun MagicButton(rewriting: Boolean, colors: BarColors, onClick: () -> Unit) {
    Box(
        Modifier
            .size(width = 48.dp, height = 32.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(colors.accent)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        if (rewriting) {
            CircularProgressIndicator(Modifier.size(16.dp), color = colors.onAccent, strokeWidth = 2.dp)
        } else {
            Text("✨", fontSize = 16.sp)
        }
    }
}

@Composable
private fun Close(colors: BarColors, onClick: () -> Unit) {
    Box(
        Modifier.size(28.dp).clip(CircleShape).background(colors.chip).clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text("✕", color = colors.muted, fontSize = 13.sp)
    }
}

@Composable
private fun Busy(text: String, colors: BarColors) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxHeight()) {
        CircularProgressIndicator(Modifier.size(14.dp), color = colors.accent, strokeWidth = 2.dp)
        Spacer(Modifier.width(8.dp))
        Text(text, color = colors.muted, fontSize = 13.sp)
    }
}

@Composable
private fun Line(text: String, color: Color) {
    Text(text, color = color, fontSize = 13.sp, lineHeight = 16.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
}
