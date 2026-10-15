import SwiftUI

/// The languages in the keyboard's chip row: add from the catalog or type one in, swipe to drop, "Tahrirlash" to reorder.
struct LanguagesView: View {
    @ObservedObject var store: SharedStateModel
    @State private var editMode: EditMode = .inactive
    @State private var asksCustomName = false
    @State private var customName = ""

    private var list: [String] { store.state.languageList }

    var body: some View {
        List {
            Section {
                ForEach(list, id: \.self) { language in
                    Text("\(Languages.flag(language)) \(language)")
                }
                .onDelete { offsets in save { $0.remove(atOffsets: offsets) } }
                .onMove { source, destination in save { $0.move(fromOffsets: source, toOffset: destination) } }
            } footer: {
                if list.isEmpty {
                    Text("Ro'yxat bo'sh — klaviaturada faqat do'stlaringiz chiqadi.")
                } else {
                    Text("Klaviaturadagi ✨ qatorida shu tartibda chiqadi. O'chirish uchun chapga suring, tartibini o'zgartirish uchun «Tahrirlash»ni bosing.")
                }
            }
            Section {
                Menu {
                    ForEach(Languages.addable(to: list), id: \.name) { entry in
                        Button("\(entry.flag) \(entry.name)") { save { $0 = Languages.adding(entry.name, to: $0) } }
                    }
                    Divider()
                    Button("Boshqa til…") { asksCustomName = true }
                } label: {
                    Label("Til qo'shish", systemImage: "plus.circle.fill")
                }
                if store.state.languages != nil {
                    Button("Standart ro'yxatga qaytarish", role: .destructive) {
                        store.update { $0.languages = nil }
                    }
                }
            }
        }
        .navigationTitle("Klaviatura tillari")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, $editMode)
        // Not `EditButton`: it follows the phone's language and the footer above names this button in Uzbek.
        .toolbar {
            Button(editMode.isEditing ? "Tayyor" : "Tahrirlash") {
                withAnimation { editMode = editMode.isEditing ? .inactive : .active }
            }
        }
        .alert("Boshqa til", isPresented: $asksCustomName) {
            TextField("Masalan: Swahili", text: $customName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            Button("Qo'shish") {
                save { $0 = Languages.adding(customName, to: $0) }
                customName = ""
            }
            Button("Bekor qilish", role: .cancel) { customName = "" }
        } message: {
            Text("Til nomini inglizcha yozing — shu nom tarjima tili sifatida Gemini'ga yuboriladi.")
        }
    }

    private func save(_ change: (inout [String]) -> Void) {
        var updated = list
        change(&updated)
        guard updated != list else { return }
        store.update { $0.languages = updated }
    }
}
