package com.ibrokhim.aikeyboard.app

import android.content.ClipboardManager
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import com.ibrokhim.aikeyboard.ai.KeyCheck
import com.ibrokhim.aikeyboard.data.ApiKeyStore
import kotlinx.coroutines.launch

/**
 * "API kalit qo'shish": the user types or pastes a Gemini key, the key is checked once with Google, and only
 * then saved (iOS `APIKeySheet`). [onDone] gets a line for the settings screen after a save or delete.
 */
@Composable
fun ApiKeyDialog(keys: ApiKeyStore, hasKey: Boolean, onDone: (String) -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val focus = remember { FocusRequester() }
    var text by remember { mutableStateOf("") }
    var reveals by remember { mutableStateOf(false) }
    var checking by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<String?>(null) }
    var confirmsDelete by remember { mutableStateOf(false) }
    val key = ApiKeyStore.normalize(text)

    fun save() {
        val candidate = key ?: return
        if (checking) return
        checking = true
        problem = null
        scope.launch {
            val outcome = KeyCheck.check(candidate)
            checking = false
            when (outcome) {
                is KeyCheck.Outcome.Rejected -> problem = outcome.reason
                is KeyCheck.Outcome.Unverified -> {
                    keys.userKey = candidate
                    onDone("Saqlandi, lekin tekshirib bo'lmadi: ${outcome.reason}")
                }
                KeyCheck.Outcome.Valid -> {
                    keys.userKey = candidate
                    onDone("Saqlandi — kalit ishlayapti ✓")
                }
            }
        }
    }

    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }

    AlertDialog(
        onDismissRequest = { if (!checking) onDismiss() },
        properties = DialogProperties(dismissOnBackPress = !checking, dismissOnClickOutside = !checking),
        title = { Text(if (hasKey) "Kalitni almashtirish" else "API kalit qo'shish") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = text,
                    onValueChange = {
                        text = it
                        problem = null
                    },
                    label = { Text("Gemini API kaliti") },
                    placeholder = { Text("AIza…") },
                    singleLine = true,
                    enabled = !checking,
                    isError = problem != null,
                    textStyle = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace),
                    visualTransformation = if (reveals) VisualTransformation.None else PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { save() }),
                    trailingIcon = {
                        TextButton(onClick = { reveals = !reveals }) { Text(if (reveals) "Yashir" else "Ko'rsat") }
                    },
                    modifier = Modifier.fillMaxWidth().focusRequester(focus),
                )
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    TextButton(enabled = !checking, onClick = {
                        val clip = context.getSystemService(ClipboardManager::class.java)?.primaryClip
                        val pasted = clip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(context)?.toString()
                        if (pasted.isNullOrBlank()) problem = "Nusxada matn yo'q" else text = pasted
                    }) { Text("Nusxadan qo'yish") }
                    TextButton(onClick = {
                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://aistudio.google.com/apikey")))
                    }) { Text("Kalit olish") }
                }
                problem?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium) }
                Text(
                    "Saqlashdan oldin Google'da bir marta tekshiriladi. Kalit faqat shu telefonda turadi va faqat Gemini'ga yuboriladi.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (hasKey) {
                    if (confirmsDelete) {
                        Text("Tarjima va ✨ yangi kalit qo'shilmaguncha ishlamaydi.", style = MaterialTheme.typography.bodySmall)
                        TextButton(enabled = !checking, onClick = {
                            keys.userKey = null
                            onDone("Kalit o'chirildi")
                        }) { Text("Ha, kalitni o'chirish", color = MaterialTheme.colorScheme.error) }
                    } else {
                        TextButton(enabled = !checking, onClick = { confirmsDelete = true }) {
                            Text("Kalitni o'chirish", color = MaterialTheme.colorScheme.error)
                        }
                    }
                }
            }
        },
        confirmButton = {
            Button(enabled = key != null && !checking, onClick = { save() }) {
                if (checking) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                        Text("Tekshirilmoqda…")
                    }
                } else {
                    Text("Saqlash")
                }
            }
        },
        dismissButton = {
            TextButton(enabled = !checking, onClick = onDismiss) { Text("Bekor") }
        },
    )
}
