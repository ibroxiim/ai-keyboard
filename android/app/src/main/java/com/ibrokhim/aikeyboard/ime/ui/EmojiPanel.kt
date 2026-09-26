package com.ibrokhim.aikeyboard.ime.ui

import android.view.HapticFeedbackConstants
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyHorizontalGrid
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ibrokhim.aikeyboard.R
import com.ibrokhim.aikeyboard.ime.EmojiCategory
import com.ibrokhim.aikeyboard.ime.EmojiData
import com.ibrokhim.aikeyboard.ime.KeyboardTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The keyboard's own emoji panel, laid out like the system one: a horizontally scrolling 5-row grid,
 * the category name on top, ABC · categories · ⌫ at the bottom (iOS `EmojiPanelView`).
 */
@Composable
fun EmojiPanel(
    recents: List<String>,
    theme: KeyboardTheme,
    bottomInset: Dp,
    onEmoji: (String) -> Unit,
    onAbc: () -> Unit,
    onBackspace: () -> Unit,
) {
    val ink = Color(theme.label)
    val muted = ink.copy(alpha = 0.55f)
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val sections = remember(recents) {
        val recent = if (recents.isEmpty()) emptyList() else listOf(EmojiCategory("Ko'p ishlatilgan", "🕘", recents))
        recent + EmojiData.categories
    }
    val starts = remember(sections) { sections.runningFold(0) { start, section -> start + section.emojis.size }.dropLast(1) }
    val all = remember(sections) { sections.flatMap { it.emojis } }
    val grid = rememberLazyGridState()
    val current by remember(starts) {
        derivedStateOf { starts.indexOfLast { it <= grid.firstVisibleItemIndex }.coerceAtLeast(0) }
    }

    Column(Modifier.fillMaxSize().background(Color(theme.background)).padding(bottom = bottomInset)) {
        Text(
            sections[current].title.uppercase(), color = muted, fontSize = 11.sp, fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(start = 12.dp, top = 4.dp).height(16.dp),
        )
        LazyHorizontalGrid(
            rows = GridCells.Fixed(5),
            state = grid,
            modifier = Modifier.fillMaxWidth().weight(1f),
            contentPadding = PaddingValues(horizontal = 4.dp),
        ) {
            items(all.size) { index ->
                val emoji = all[index]
                Box(
                    Modifier.width(44.dp).fillMaxHeight().clickable {
                        view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                        onEmoji(emoji)
                    },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(emoji, fontSize = 26.sp)
                }
            }
        }
        Row(Modifier.fillMaxWidth().height(40.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1.4f).fillMaxHeight().clickable(onClick = onAbc), contentAlignment = Alignment.Center) {
                Text("ABC", color = ink, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            }
            sections.forEachIndexed { index, section ->
                Box(
                    Modifier.weight(1f).fillMaxHeight().clickable { scope.launch { grid.scrollToItem(starts[index]) } },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(section.icon, fontSize = 18.sp, modifier = Modifier.alpha(if (index == current) 1f else 0.4f))
                }
            }
            Box(
                Modifier.weight(1.4f).fillMaxHeight().pointerInput(onBackspace) {
                    detectTapGestures(onPress = {
                        view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                        onBackspace()
                        val repeat = scope.launch {
                            delay(400)
                            while (true) {
                                onBackspace()
                                delay(60)
                            }
                        }
                        tryAwaitRelease()
                        repeat.cancel()
                    })
                },
                contentAlignment = Alignment.Center,
            ) {
                Icon(painterResource(R.drawable.key_backspace), contentDescription = "O'chirish", tint = ink, modifier = Modifier.size(22.dp))
            }
        }
    }
}
