package com.ibrokhim.aikeyboard.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ibrokhim.aikeyboard.BuildConfig
import com.ibrokhim.aikeyboard.R
import com.ibrokhim.aikeyboard.ai.KeyCheck
import com.ibrokhim.aikeyboard.data.ApiKeyStore
import com.ibrokhim.aikeyboard.data.ChatAnalysis
import com.ibrokhim.aikeyboard.data.Languages
import com.ibrokhim.aikeyboard.data.SharedState
import com.ibrokhim.aikeyboard.data.SharedStore
import kotlinx.coroutines.launch

private val Done = Color(0xFF2EAD5B)

/** The app screen: setup steps, the Gemini key, a place to try the keyboard, and its settings (iOS `ContentView`). */
@Composable
fun SetupScreen(resumeTick: Int) {
    val context = LocalContext.current
    val store = remember { SharedStore.get(context) }
    val keys = remember { ApiKeyStore.get(context) }
    val shared by store.state.collectAsState()
    var keyVersion by remember { mutableIntStateOf(0) }
    val status = remember(resumeTick, keyVersion) { readSetupStatus(context, keys) }
    var disclosure by remember { mutableStateOf(false) }
    val now = System.currentTimeMillis()

    Scaffold { padding ->
        LazyColumn(
            Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            item { Header(status.done) }
            item { StepsSection(status, context) { disclosure = true } }
            item { KeySection(keys) { keyVersion++ } }
            item { TrySection(context) }
            item { LanguageSection(shared, now) { language -> store.update { it.copy(targetLanguage = language, activeFriend = null) } } }
            item { KeyboardSection(shared, store) }
            if (shared.friends.isNotEmpty()) item { FriendsSection(shared) { name -> store.update { it.forgetFriend(name) } } }
            shared.context?.let { analysis -> item { ContextSection(analysis, stale = shared.freshContext(now) == null) } }
            item { PrivacySection() }
        }
    }
    if (disclosure) {
        ReaderDisclosure(
            onDismiss = { disclosure = false },
            onAgree = {
                disclosure = false
                context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
            },
        )
    }
}

@Composable
private fun Header(done: Boolean) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier.size(56.dp).clip(RoundedCornerShape(14.dp))
                .background(Brush.linearGradient(listOf(Color(0xFF3D7BFF), Color(0xFF7B4BFF)))),
        ) {
            Image(painterResource(R.drawable.ic_launcher_foreground), contentDescription = null, modifier = Modifier.fillMaxSize())
        }
        Spacer(Modifier.width(14.dp))
        Column {
            Text("AI Keyboard", fontSize = 24.sp, fontWeight = FontWeight.Bold)
            Text(
                if (done) "Tayyor — DM'da klaviaturadagi 📖 ni bosing" else "DM uchun AI klaviatura · beta",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun Section(title: String, footer: String? = null, content: @Composable ColumnScope.() -> Unit) {
    Column {
        Text(title, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
        Spacer(Modifier.height(8.dp))
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp), content = content)
        }
        if (footer != null) {
            Text(
                footer, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 6.dp, start = 4.dp, end = 4.dp),
            )
        }
    }
}

@Composable
private fun StepsSection(status: SetupStatus, context: Context, onReader: () -> Unit) {
    Section("Sozlash") {
        Step(
            1, status.keyboardEnabled, status.current == 0, "Klaviaturani yoqing",
            "Tizim sozlamalaridagi ekran klaviaturalari ro'yxatida AI Keyboard'ni yoqing.", "Ochish",
        ) { context.startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)) }
        Step(
            2, status.keyboardSelected, status.current == 1, "AI Keyboard'ni tanlang",
            "Yozish paytida AI Keyboard chiqishi uchun uni joriy klaviatura qiling.", "Tanlash",
        ) { context.getSystemService(InputMethodManager::class.java).showInputMethodPicker() }
        Step(
            3, status.readerEnabled, status.current == 2, "Chatni o'qishga ruxsat bering",
            "📖 bosilganda yozayotgan chatingiz matnini o'qish uchun (Accessibility xizmati).", "Ruxsat berish",
            onReader,
        )
        Step(
            4, status.hasKey, status.current == 3, "Gemini kalitini kiriting",
            "Tarjima va javoblar Google Gemini orqali ishlaydi. Kalit bepul — pastdagi bo'limda.", null,
        ) {}
    }
}

@Composable
private fun Step(number: Int, done: Boolean, current: Boolean, title: String, body: String, action: String?, onAction: () -> Unit) {
    Row(verticalAlignment = Alignment.Top) {
        Box(
            Modifier.size(28.dp).clip(CircleShape).background(
                when {
                    done -> Done
                    current -> MaterialTheme.colorScheme.primary
                    else -> MaterialTheme.colorScheme.surfaceVariant
                },
            ),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                if (done) "✓" else "$number", fontSize = 14.sp, fontWeight = FontWeight.SemiBold,
                color = if (done || current) Color.White else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleSmall)
            Text(body, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (!done && action != null) {
                Spacer(Modifier.height(8.dp))
                if (current) Button(onClick = onAction) { Text(action) } else OutlinedButton(onClick = onAction) { Text(action) }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun KeySection(keys: ApiKeyStore, onChanged: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var text by remember { mutableStateOf(keys.userKey.orEmpty()) }
    var message by remember { mutableStateOf<String?>(null) }
    var checking by remember { mutableStateOf(false) }
    Section(
        "Gemini kaliti",
        footer = "Kalit faqat shu telefonda saqlanadi va faqat Google Gemini'ga yuboriladi. " +
            "Bepul kalit: aistudio.google.com/apikey",
    ) {
        OutlinedTextField(
            value = text,
            onValueChange = {
                text = it.trim()
                message = null
            },
            label = { Text("API kalit") },
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            modifier = Modifier.fillMaxWidth(),
        )
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = {
                keys.userKey = text
                onChanged()
                message = if (text.isBlank()) "Kalit o'chirildi" else "Saqlandi"
            }) { Text("Saqlash") }
            OutlinedButton(
                enabled = !checking && (text.isNotBlank() || keys.effectiveKey().isNotBlank()),
                onClick = {
                    checking = true
                    scope.launch {
                        message = KeyCheck.check(text.ifBlank { keys.effectiveKey() }) ?: "✓ Kalit ishlayapti"
                        checking = false
                    }
                },
            ) { Text(if (checking) "Tekshirilmoqda…" else "Tekshirish") }
            TextButton(onClick = {
                context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://aistudio.google.com/apikey")))
            }) { Text("Kalit olish") }
        }
        message?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
        if (keys.userKey == null && BuildConfig.GEMINI_API_KEY.isNotBlank()) {
            Text(
                "Debug build: local.properties'dagi kalit ishlatilyapti.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun TrySection(context: Context) {
    var text by remember { mutableStateOf("") }
    Section("Sinab ko'rish", footer = "Demo chatda to'qima Emma suhbati bor — 📖 va ✨ ni messengersiz sinash mumkin.") {
        Button(onClick = { context.startActivity(Intent(context, DemoChatActivity::class.java)) }) { Text("Demo chatni ochish") }
        OutlinedTextField(
            value = text,
            onValueChange = { text = it },
            label = { Text("Shu yerga yozib ko'ring") },
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun LanguageSection(shared: SharedState, now: Long, onSelect: (String) -> Unit) {
    val current = shared.language(now)
    Section(
        "✨ qaysi tilga yozadi",
        footer = "O'zi almashadi: chat o'qilgandan keyin — suhbat tiliga. Klaviaturada do'stingiz nomini bossangiz — uning tiliga.",
    ) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            (listOf(current) + Languages.common.filter { it != current }).forEach { language ->
                FilterChip(
                    selected = language == current,
                    onClick = { onSelect(language) },
                    label = { Text("${Languages.flag(language)} $language") },
                )
            }
        }
    }
}

@Composable
private fun KeyboardSection(shared: SharedState, store: SharedStore) {
    Section("Klaviatura") {
        SettingSwitch(
            "😀 tugmasi",
            "КИР/LAT o'rniga emoji paneli. Klaviatura lotin yozuvida qoladi — kirill kerak bo'lsa, o'chiring.",
            shared.emojiKey,
        ) { on -> store.update { it.copy(emojiKey = on) } }
        SettingSwitch(
            "Avtomatik o'qish",
            "Messengerda klaviatura ochilganda chat 📖 bosilmasdan o'qiladi va Gemini'ga yuboriladi. " +
                "Chat o'zgarmasa qayta yuborilmaydi.",
            shared.autoRead,
        ) { on -> store.update { it.copy(autoRead = on) } }
    }
}

@Composable
private fun SettingSwitch(title: String, body: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleSmall)
            Text(body, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Spacer(Modifier.width(12.dp))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@Composable
private fun FriendsSection(shared: SharedState, onForget: (String) -> Unit) {
    Section("Do'stlar", footer = "Har chat o'qilgandan keyin eslab qolinadi. Klaviaturada ularni bir bosishda tanlaysiz.") {
        shared.friends.forEach { friend ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("${Languages.flag(friend.language)} ${friend.name}", style = MaterialTheme.typography.titleSmall)
                    Text(
                        listOf(friend.language, friend.tone).filter { it.isNotBlank() }.joinToString(" · "),
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                TextButton(onClick = { onForget(friend.name) }) { Text("O'chirish") }
            }
        }
    }
}

@Composable
private fun ContextSection(context: ChatAnalysis, stale: Boolean) {
    Section(
        "Oxirgi kontekst",
        footer = if (stale) "Eskirgan: klaviatura 15 daqiqadan eski kontekstni ko'rsatmaydi." else null,
    ) {
        Text(context.partner.ifEmpty { "Suhbat" }, style = MaterialTheme.typography.titleSmall)
        if (context.summaryUz.isNotEmpty()) Text(context.summaryUz, style = MaterialTheme.typography.bodyMedium)
        if (context.lastIncomingUz.isNotEmpty()) {
            Text(context.lastIncomingUz, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun PrivacySection() {
    Section("Maxfiylik") {
        Text(
            "• Chat faqat 📖 bosilganda yoki siz yoqqan avtomatik o'qishda, faqat messengerlarda o'qiladi.\n" +
                "• O'qilgan matn (ilova matnni bermasa — skrinshot) faqat Google Gemini'ga yuboriladi.\n" +
                "• Telefonda oxirgi 6 ta xabar va do'stlar ro'yxati saqlanadi; zaxira nusxaga tushmaydi.\n" +
                "• Klaviatura yozganingizni hech qayerga yubormaydi — faqat ✨ bosilganda qoralama.",
            style = MaterialTheme.typography.bodySmall,
        )
    }
}

@Composable
private fun ReaderDisclosure(onDismiss: () -> Unit, onAgree: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Chatni o'qish") },
        text = {
            Text(
                "AI Keyboard Accessibility xizmati orqali yozayotgan chatingiz matnini o'qiydi:\n\n" +
                    "• faqat klaviaturadagi 📖 bosilganda yoki siz yoqqan avtomatik o'qishda (messengerlarda);\n" +
                    "• matn (ilova matnni bermasa — ekran skrinshoti) tarjima va javoblar uchun Google Gemini'ga yuboriladi;\n" +
                    "• yozish maydonlari (parollar ham) o'qilmaydi, boshqa paytda xizmat hech narsa qilmaydi.\n\n" +
                    "Davom etsangiz, Accessibility sozlamalari ochiladi — «AI Keyboard — chatni o'qish»ni yoqing.",
            )
        },
        confirmButton = { Button(onClick = onAgree) { Text("Roziman") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Bekor qilish") } },
    )
}
