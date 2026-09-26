import PhotosUI
import SwiftUI

/// Shared state, live: reloads when the keyboard or the Back Tap intent writes (Darwin notification).
@MainActor
final class SharedStateModel: ObservableObject {
    @Published private(set) var state = SharedStore.load()
    private var observer: DarwinObserver?

    init() {
        observer = DarwinObserver(name: AppGroup.stateChanged) { [weak self] in self?.reload() }
        var merged = state
        merged.mergeDuplicateFriends()
        if merged != state { update { $0.mergeDuplicateFriends() } }
    }

    func reload() { state = SharedStore.load() }

    func update(_ change: (inout SharedState) -> Void) {
        SharedStore.update(change)
        reload()
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = SharedStateModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var isAnalyzing = false
    @State private var errorText: String?
    @State private var testText = ""
    @FocusState private var testFieldFocused: Bool

    private var state: SharedState { store.state }
    private let shortcutFile = Bundle.main.url(forResource: "AI Keyboard", withExtension: "shortcut")

    var body: some View {
        NavigationStack {
            Form {
                if SharedStore.containerURL == nil {
                    Section {
                        Label("App Group ishlamayapti — klaviatura kontekstni ko'rmaydi", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
                setupSection
                testSection
                languageSection
                keyboardSection
                friendsSection
                contextSection
            }
            .navigationTitle("AI Keyboard")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.reload() }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            analyze(item)
        }
    }

    // MARK: Setup

    /// iOS keeps the enabled keyboards in the global defaults; the keyboard's own first
    /// launch is the fallback proof.
    private var keyboardAdded: Bool {
        EnabledKeyboards.containsAIKeyboard || state.keyboardFullAccessDate != nil
    }

    private var fullAccessOn: Bool { state.keyboardFullAccessDate != nil }
    private var shortcutWorks: Bool { state.shortcutRunDate != nil }

    private var setupSection: some View {
        Section {
            step(1, "Klaviaturani qo'shing", done: keyboardAdded,
                 "Settings → General → Keyboard → Keyboards → Add New Keyboard → AI Keyboard")
            step(2, "Full Access'ni yoqing", done: fullAccessOn,
                 "Keyboards → AI Keyboard → Allow Full Access. Keyin pastdagi maydonda AI Keyboard klaviaturasini bir marta oching — shu bilan tasdiqlanadi.")
            if !keyboardAdded || !fullAccessOn {
                Button("Ilova sozlamalarini ochish") {
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                }
            }
            step(3, "Shortcut'ni qo'shing", done: shortcutWorks,
                 "Tugmani bosing → ro'yxatdan Shortcuts'ni tanlang → «Add Shortcut».")
            if let shortcutFile, !shortcutWorks {
                ShareLink(item: shortcutFile) {
                    Label("Shortcut'ni qo'shish", systemImage: "square.and.arrow.down")
                }
            }
            step(4, "Back Tap'ga ulang", done: shortcutWorks,
                 "Settings → Accessibility → Touch → Back Tap → Double Tap → AI Keyboard shortcut'i. Keyin DM'da orqaga 2× urib sinang.")
            if !shortcutWorks {
                Button("Settings'ni ochish (Accessibility)") { openSettingsRoot() }
            }
        } header: {
            Text("Sozlash")
        } footer: {
            if !shortcutWorks {
                Text("3–4-qadamlar birinchi Back Tap ishlaganda belgilanadi.")
            }
        }
    }

    /// iOS 27 ignores deep paths (Accessibility/Touch/Back Tap) and only honours the bare
    /// "App-prefs:" root — Accessibility is on that first screen. Private scheme: App Store review may reject it.
    private func openSettingsRoot() {
        UIApplication.shared.open(URL(string: "App-prefs:")!) { opened in
            if !opened { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
        }
    }

    private func step(_ number: Int, _ title: String, done: Bool, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.green)
                } else {
                    Text("\(number)")
                        .font(.headline)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.accentColor.opacity(0.15)))
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(done ? .secondary : .primary)
                if !done {
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Test

    private var testSection: some View {
        Section("Sinab ko'rish") {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                HStack {
                    Label("DM skrinshotini tanlash", systemImage: "photo.on.rectangle")
                    Spacer()
                    if isAnalyzing { ProgressView() }
                }
            }
            .disabled(isAnalyzing)
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }
            TextField("Klaviaturani shu yerda sinang", text: $testText, axis: .vertical)
                .lineLimit(2...5)
                .focused($testFieldFocused)
                .onAppear {
                    #if DEBUG
                    // `-focusTestField YES` launch argument: opens the keyboard for device screenshots.
                    if UserDefaults.standard.bool(forKey: "focusTestField") { testFieldFocused = true }
                    #endif
                }
        }
    }

    // MARK: Language & friends

    private var languageSection: some View {
        Section {
            Picker("✨ tili", selection: Binding(
                get: { state.targetLanguage ?? "English" },
                set: { language in store.update { $0.targetLanguage = language; $0.activeFriend = nil } }
            )) {
                let options = Languages.common.contains(state.targetLanguage ?? "English")
                    ? Languages.common : Languages.common + [state.targetLanguage ?? "English"]
                ForEach(options, id: \.self) { Text("\(Languages.flag($0)) \($0)") }
            }
        } footer: {
            Text("O'zi almashadi: skrinshotdan keyin — suhbat tiliga. Klaviaturada do'stingiz nomini bossangiz — uning tiliga.")
        }
    }

    private var keyboardSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { state.emojiKey ?? false },
                set: { on in store.update { $0.emojiKey = on } }
            )) {
                Label("КИР o'rniga emoji tugmasi", systemImage: "face.smiling")
            }
        } header: {
            Text("Klaviatura")
        } footer: {
            Text("Yoqilsa, pastki qatordagi КИР/LAT tugmasi 😀 ga almashadi va emoji panelini ochadi. Klaviatura lotin yozuvida qoladi — kirill kerak bo'lsa, o'chiring.")
        }
    }

    @ViewBuilder
    private var friendsSection: some View {
        if let friends = state.friends, !friends.isEmpty {
            Section {
                ForEach(friends) { friend in
                    HStack {
                        Text(Languages.flag(friend.language))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(friend.name)
                            Text("\(friend.language) · \(friend.tone)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if state.activeFriend == friend.name {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .onDelete { offsets in
                    let names = offsets.map { friends[$0].name }
                    store.update { state in
                        state.friends?.removeAll { names.contains($0.name) }
                        if let active = state.activeFriend, names.contains(active) { state.activeFriend = nil }
                    }
                }
            } header: {
                Text("Do'stlar")
            } footer: {
                Text("Har skrinshotdan keyin eslab qolinadi. Klaviaturada ularni bir bosishda tanlaysiz.")
            }
        }
    }

    // MARK: Context

    @ViewBuilder
    private var contextSection: some View {
        if let context = state.context, let date = state.contextDate {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    if !context.partner.isEmpty { Text(context.partner).font(.headline) }
                    Text(context.summaryUz).font(.subheadline)
                }
                if !context.lastIncoming.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.lastIncoming).font(.callout)
                        Text(context.lastIncomingUz).font(.callout).foregroundStyle(.secondary)
                    }
                }
                ForEach(context.suggestions) { suggestion in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.text)
                        Text(suggestion.uz).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Button("Kontekstni tozalash", role: .destructive) {
                    store.update { $0.context = nil; $0.contextDate = nil }
                }
            } header: {
                HStack {
                    Text("Oxirgi kontekst")
                    Spacer()
                    Text(date, style: .relative)
                }
            } footer: {
                if state.freshContext == nil {
                    Text("Eskirgan: klaviatura 15 daqiqadan eski kontekstni ko'rsatmaydi.")
                }
            }
        }
    }

    private func analyze(_ item: PhotosPickerItem) {
        isAnalyzing = true
        errorText = nil
        Task {
            defer {
                isAnalyzing = false
                pickerItem = nil
                store.reload()
            }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw AppError(message: "Rasmni yuklab bo'lmadi")
                }
                try await ChatAnalysisService.run(imageData: data, fromShortcut: false)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
