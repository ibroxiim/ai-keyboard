package com.ibrokhim.aikeyboard.app

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.ibrokhim.aikeyboard.data.Friend
import com.ibrokhim.aikeyboard.data.Languages

/**
 * One remembered friend: what the chat reads found out about them, and what the user decided — formality,
 * notes for the model, whether to keep their chat (iOS `FriendDetailView`).
 */
@Composable
fun FriendDetailDialog(
    friend: Friend,
    onChange: ((Friend) -> Friend) -> Unit,
    onForget: () -> Unit,
    onDismiss: () -> Unit,
) {
    var editingNotes by remember { mutableStateOf(false) }
    if (editingNotes) {
        InstructionsDialog(
            title = "Ko'rsatma",
            placeholder = "Masalan: sinfdoshim, hazil aralash yozamiz; sen deb gapiramiz; u o'zbekcha bir-ikki so'z biladi",
            initial = friend.notes.orEmpty(),
            onSave = { text -> onChange { it.copy(notes = text.ifEmpty { null }) }; editingNotes = false },
            onDismiss = { editingNotes = false },
        )
        return
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = { TextButton(onClick = onDismiss) { Text("Yopish") } },
        dismissButton = { TextButton(onClick = { onForget(); onDismiss() }) { Text("Do'stni o'chirish", color = MaterialTheme.colorScheme.error) } },
        title = { Text("${Languages.flag(friend.language)} ${friend.name}") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    listOf(friend.language, friend.tone).filter { it.isNotBlank() }.joinToString(" · "),
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text("Muloqot darajasi", style = MaterialTheme.typography.titleSmall)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(friend.formality == null, { onChange { it.copy(formality = null) } }, { Text("Avto") })
                    FilterChip(friend.formality == Friend.Formality.INFORMAL, { onChange { it.copy(formality = Friend.Formality.INFORMAL) } }, { Text("Norasmiy (sen)") })
                    FilterChip(friend.formality == Friend.Formality.FORMAL, { onChange { it.copy(formality = Friend.Formality.FORMAL) } }, { Text("Rasmiy (siz)") })
                }
                Text(
                    "Daraja sizniki — ✨ shunga amal qiladi; Avto bo'lsa suhbatdan o'zi aniqlaydi.",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                HorizontalDivider()
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("Ko'rsatma", style = MaterialTheme.typography.titleSmall)
                        Text(
                            friend.notes ?: "Yo'q — kim u, qanday ohangda yozasiz",
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 3, overflow = TextOverflow.Ellipsis,
                        )
                    }
                    TextButton(onClick = { editingNotes = true }) { Text(if (friend.notes == null) "Yozish" else "Tahrirlash") }
                }
                HorizontalDivider()
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Xotira: ${friend.history?.size ?: 0} xabar", modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                    TextButton(onClick = { onChange { it.copy(history = null) } }, enabled = !friend.history.isNullOrEmpty()) { Text("Tozalash") }
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("O'rganilgan tuzatishlar: ${friend.examples?.size ?: 0}", modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                    TextButton(onClick = { onChange { it.copy(examples = null) } }, enabled = !friend.examples.isNullOrEmpty()) { Text("Unutish") }
                }
                Text(
                    "Xotira — chat o'qishlaridan yig'ilgan xabarlar, ✨ uchun suhbat konteksti. Tuzatishlar — ✨ variantini yuborishdan oldin o'zgartirgan holatlaringiz. Ikkalasi faqat shu telefonda.",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.padding(2.dp))
            }
        },
        modifier = Modifier.fillMaxWidth(),
    )
}
