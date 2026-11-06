import SwiftUI

/// "API kalit qo'shish": the user types or pastes a Gemini key, the key is checked once with Google, and only
/// then saved to the Keychain, where the keyboard reads it too.
struct APIKeySheet: View {
    let hasKey: Bool
    /// Called after a save or delete, with a line for the settings screen.
    let onDone: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var reveals = false
    @State private var checking = false
    @State private var problem: String?
    @State private var confirmsDelete = false
    @FocusState private var focused: Bool

    private var key: String? { APIKey.normalized(text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Group {
                            if reveals {
                                TextField("AIza…", text: $text)
                            } else {
                                SecureField("AIza…", text: $text)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .onChange(of: text) { problem = nil }
                        Button {
                            reveals.toggle()
                        } label: {
                            Image(systemName: reveals ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(reveals ? "Kalitni yashirish" : "Kalitni ko'rsatish")
                    }
                    PasteButton(payloadType: String.self) { strings in
                        Task { @MainActor in text = strings.first ?? "" }
                    }
                } header: {
                    Text("Gemini API kaliti")
                } footer: {
                    Text("Saqlashdan oldin Google'da bir marta tekshiriladi. Kalit faqat shu telefonning Keychain'ida turadi va faqat Gemini'ga yuboriladi.")
                }

                if let problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                        Label("Bepul kalit olish — aistudio.google.com", systemImage: "arrow.up.right.square")
                    }
                }

                if hasKey {
                    Section {
                        Button("Kalitni o'chirish", role: .destructive) { confirmsDelete = true }
                    }
                }
            }
            .navigationTitle(hasKey ? "Kalitni almashtirish" : "API kalit qo'shish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Bekor") { dismiss() }
                        .disabled(checking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if checking {
                        ProgressView()
                    } else {
                        Button("Saqlash", action: save)
                            .disabled(key == nil)
                    }
                }
            }
            .confirmationDialog("Kalit o'chirilsinmi?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("O'chirish", role: .destructive) {
                    KeyStore.delete()
                    onDone("Kalit o'chirildi")
                    dismiss()
                }
            } message: {
                Text("Tarjima va ✨ yangi kalit qo'shilmaguncha ishlamaydi.")
            }
            .interactiveDismissDisabled(checking)
            .onAppear { focused = true }
        }
    }

    private func save() {
        guard let key, !checking else { return }
        checking = true
        problem = nil
        Task { @MainActor in
            let outcome = await Gemini.check(key: key)
            checking = false
            guard outcome.shouldSave else {
                if case .rejected(let reason) = outcome { problem = reason }
                return
            }
            do {
                try KeyStore.save(key)
            } catch {
                problem = error.localizedDescription
                return
            }
            if case .unverified(let reason) = outcome {
                onDone("Saqlandi, lekin tekshirib bo'lmadi: \(reason)")
            } else {
                onDone("Saqlandi — kalit ishlayapti ✓")
            }
            dismiss()
        }
    }
}
