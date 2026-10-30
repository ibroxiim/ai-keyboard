package com.ibrokhim.aikeyboard.ime.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ibrokhim.aikeyboard.data.Suggestion
import com.ibrokhim.aikeyboard.ime.KeyboardTheme

/**
 * Every reply in full, over the keys — a chip cuts them at two lines (iOS `VariantList`). [original] is the draft
 * ✨ started from, shown as "↩︎ Asli" when these are ✨ variants; [picked] is the reply now in the field.
 */
@Composable
fun VariantList(
    title: String,
    items: List<Suggestion>,
    original: String?,
    picked: String?,
    focus: String?,
    theme: KeyboardTheme,
    bottomInset: Dp,
    onPick: (Suggestion) -> Unit,
    onRestore: () -> Unit,
    onClose: () -> Unit,
) {
    val ink = Color(theme.label)
    val muted = ink.copy(alpha = 0.6f)
    val accent = Color(theme.accent)
    val listState = rememberLazyListState()
    LaunchedEffect(focus) {
        val index = items.indexOfFirst { it.text == focus }
        if (index >= 0) listState.scrollToItem(index + (if (original != null) 1 else 0))
    }
    Column(Modifier.fillMaxSize().background(Color(theme.background)).padding(bottom = bottomInset)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(title, color = ink, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            Text(
                "Klaviatura", color = accent, fontSize = 14.sp, fontWeight = FontWeight.Medium,
                modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable(onClick = onClose).padding(6.dp),
            )
        }
        LazyColumn(
            state = listState,
            contentPadding = PaddingValues(start = 10.dp, end = 10.dp, bottom = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (original != null) {
                item { Card("↩︎ Asli", null, original, picked == null, theme, onRestore) }
            }
            items(items.size) { index ->
                val suggestion = items[index]
                Card(suggestion.text, suggestion.read, suggestion.uz, picked == suggestion.text, theme) { onPick(suggestion) }
            }
        }
    }
}

@Composable
private fun Card(text: String, reading: String?, detail: String, selected: Boolean, theme: KeyboardTheme, onClick: () -> Unit) {
    val ink = Color(theme.label)
    val muted = ink.copy(alpha = 0.6f)
    val shape = RoundedCornerShape(12.dp)
    Column(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color(theme.key))
            .border(2.dp, if (selected) Color(theme.accent) else Color.Transparent, shape)
            .clickable(onClick = onClick)
            .padding(10.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(text, color = ink, fontSize = 15.sp, fontWeight = FontWeight.Medium)
        if (reading != null) Text(reading, color = muted, fontSize = 13.sp, fontStyle = FontStyle.Italic)
        Text(detail, color = muted, fontSize = 13.sp)
    }
}
