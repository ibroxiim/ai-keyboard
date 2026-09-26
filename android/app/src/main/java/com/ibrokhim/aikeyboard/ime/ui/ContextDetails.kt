package com.ibrokhim.aikeyboard.ime.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ibrokhim.aikeyboard.data.ChatAnalysis
import com.ibrokhim.aikeyboard.ime.KeyboardTheme

/** The whole analysed conversation in place of the keys (iOS `ContextDetails`). */
@Composable
fun ContextDetails(context: ChatAnalysis, theme: KeyboardTheme, bottomInset: Dp, onClose: () -> Unit) {
    val ink = Color(theme.label)
    val muted = ink.copy(alpha = 0.6f)
    val accent = Color(theme.accent)
    Column(Modifier.fillMaxSize().background(Color(theme.background)).padding(bottom = bottomInset)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                context.partner.ifEmpty { "Suhbat" }, color = ink, fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f),
            )
            Text(
                "Klaviatura", color = accent, fontSize = 14.sp, fontWeight = FontWeight.Medium,
                modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable(onClick = onClose).padding(6.dp),
            )
        }
        Column(
            Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 12.dp).padding(bottom = 8.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            if (context.summaryUz.isNotEmpty()) Text(context.summaryUz, color = ink, fontSize = 13.sp)
            if (context.lastIncoming.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(context.lastIncoming, color = ink, fontSize = 13.sp, fontWeight = FontWeight.Medium)
                    Text(context.lastIncomingUz, color = muted, fontSize = 13.sp)
                }
            }
            Box(Modifier.fillMaxWidth().height(1.dp).background(muted.copy(alpha = 0.3f)))
            context.transcript.forEach { line ->
                val mine = line.from == "me"
                Box(Modifier.fillMaxWidth(), contentAlignment = if (mine) Alignment.CenterEnd else Alignment.CenterStart) {
                    Text(
                        line.text, color = ink, fontSize = 12.5.sp,
                        modifier = Modifier
                            .widthIn(max = 300.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .background(if (mine) accent.copy(alpha = 0.25f) else Color(theme.key))
                            .padding(horizontal = 10.dp, vertical = 6.dp),
                    )
                }
            }
        }
    }
}
