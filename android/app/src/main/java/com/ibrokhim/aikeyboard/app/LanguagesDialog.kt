package com.ibrokhim.aikeyboard.app

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.InputChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.ibrokhim.aikeyboard.data.Languages

/** The languages in the keyboard's chip row: add from the catalog or type one in, ✕ to drop (iOS `LanguagesView`). */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun LanguagesDialog(
    list: List<String>,
    edited: Boolean,
    onChange: (List<String>?) -> Unit,
    onDismiss: () -> Unit,
) {
    var menuOpen by remember { mutableStateOf(false) }
    var custom by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = { TextButton(onClick = onDismiss) { Text("Yopish") } },
        dismissButton = if (edited) ({ TextButton(onClick = { onChange(null) }) { Text("Standart ro'yxat") } }) else null,
        title = { Text("Klaviatura tillari") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (list.isEmpty()) {
                    Text("Ro'yxat bo'sh — klaviaturada faqat do'stlaringiz chiqadi.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    list.forEach { language ->
                        InputChip(
                            selected = false,
                            onClick = { onChange(list - language) },
                            label = { Text("${Languages.flag(language)} $language  ✕") },
                        )
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    TextButton(onClick = { menuOpen = true }) { Text("+ Katalogdan") }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        Languages.addable(list).forEach { entry ->
                            DropdownMenuItem(
                                text = { Text("${entry.flag} ${entry.name}") },
                                onClick = { onChange(Languages.adding(entry.name, list)); menuOpen = false },
                            )
                        }
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = custom, onValueChange = { custom = it }, singleLine = true,
                        label = { Text("Boshqa til (inglizcha)") }, modifier = Modifier.weight(1f),
                    )
                    TextButton(
                        onClick = { onChange(Languages.adding(custom, list)); custom = "" },
                        enabled = Languages.normalized(custom) != null,
                    ) { Text("Qo'shish") }
                }
                Text(
                    "Klaviaturadagi ✨ qatorida shu tartibda chiqadi. Til nomi Gemini'ga tarjima tili sifatida yuboriladi.",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        modifier = Modifier.fillMaxWidth(),
    )
}
