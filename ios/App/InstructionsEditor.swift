import SwiftUI
import UniformTypeIdentifiers

/// Full-screen editor for the texts that go into prompts: the global "Tarjima uslubi" and a friend's notes.
/// Saves when the user leaves or the app goes to the background, not on every keystroke: each save rewrites the
/// shared file and wakes the keyboard.
struct InstructionsEditor: View {
    let title: String
    let placeholder: String
    let initial: String
    let onSave: (String) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var text = ""
    @State private var saved = ""
    @State private var importing = false
    @State private var importError: String?
    @FocusState private var focused: Bool

    private static let readableTypes: [UTType] = {
        var types: [UTType] = [.plainText, .text]
        if let markdown = UTType(filenameExtension: "md") { types.append(markdown) }
        return types
    }()

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 17)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .focused($focused)
                    .padding(.horizontal, 12)
                    .onChange(of: text) { _, new in
                        if new.count > Prompts.styleLimit { text = String(new.prefix(Prompts.styleLimit)) }
                    }
            }
            Divider()
            HStack {
                Text("Fayldan yuklash (.md, .txt) ⋯ menyuda").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Text("\(text.count) / \(Prompts.styleLimit)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(text.count >= Prompts.styleLimit ? .orange : .secondary)
            }
            .padding(12)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { importing = true } label: { Label("Fayldan yuklash (almashtiradi)", systemImage: "doc") }
                    Button(role: .destructive) { text = "" } label: { Label("Tozalash", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Tayyor") { focused = false }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.readableTypes) { result in
            switch result {
            case .success(let url): load(url)
            case .failure(let error): importError = error.localizedDescription
            }
        }
        .alert("Fayl o'qilmadi", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .onAppear {
            text = initial
            saved = initial
        }
        .onDisappear(perform: save)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { save() }
        }
    }

    private func load(_ url: URL) {
        // Files hands out security-scoped URLs; reading one without opening the scope fails silently.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let imported = InstructionsImport.text(from: data) else {
            importError = "Bu faylni matn sifatida o'qib bo'lmadi. .md yoki .txt fayl tanlang."
            return
        }
        text = imported
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != saved else { return }
        saved = trimmed
        onSave(trimmed)
    }
}
