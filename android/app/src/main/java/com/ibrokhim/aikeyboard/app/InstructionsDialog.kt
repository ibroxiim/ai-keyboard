package com.ibrokhim.aikeyboard.app

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.ibrokhim.aikeyboard.ai.InstructionsImport
import com.ibrokhim.aikeyboard.ai.Prompts

/**
 * Full-screen editor for the texts that go into prompts: the global "Tarjima uslubi" and a friend's notes.
 * "Fayldan" reads a .md/.txt into the field (the text is copied, nothing is linked).
 */
@Composable
fun InstructionsDialog(
    title: String,
    placeholder: String,
    initial: String,
    onSave: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    var text by remember { mutableStateOf(initial) }
    var error by remember { mutableStateOf<String?>(null) }
    val context = LocalContext.current
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val bytes = runCatching { context.contentResolver.openInputStream(uri)?.use { it.readBytes() } }.getOrNull()
        val imported = bytes?.let(InstructionsImport::text)
        if (imported == null) error = "Bu faylni matn sifatida o'qib bo'lmadi. .md yoki .txt fayl tanlang." else text = imported
    }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize()) {
            Column(Modifier.fillMaxSize().safeDrawingPadding().imePadding().padding(16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                    TextButton(onClick = onDismiss) { Text("Bekor") }
                    Button(onClick = { onSave(text.trim().take(Prompts.STYLE_LIMIT)) }) { Text("Saqlash") }
                }
                Spacer(Modifier.padding(4.dp))
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it.take(Prompts.STYLE_LIMIT) },
                    placeholder = { Text(placeholder, color = MaterialTheme.colorScheme.onSurfaceVariant) },
                    modifier = Modifier.fillMaxWidth().weight(1f),
                )
                Spacer(Modifier.padding(4.dp))
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TextButton(onClick = { picker.launch(arrayOf("text/*", "application/octet-stream")) }) { Text("Fayldan (.md, .txt)") }
                    TextButton(onClick = { text = "" }) { Text("Tozalash") }
                    Spacer(Modifier.weight(1f))
                    Text(
                        "${text.length} / ${Prompts.STYLE_LIMIT}",
                        style = MaterialTheme.typography.labelMedium,
                        color = if (text.length >= Prompts.STYLE_LIMIT) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
                Spacer(Modifier.width(0.dp))
            }
        }
    }
}
