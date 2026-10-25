import SwiftUI

/// One remembered friend: what the screenshots found out about them, and what the user decided — formality,
/// notes for the model, whether to keep their chat.
struct FriendDetailView: View {
    @ObservedObject var store: SharedStateModel
    let name: String
    @Environment(\.dismiss) private var dismiss

    private var friend: Friend? { store.state.friends?.first { $0.name == name } }

    var body: some View {
        Form {
            if let friend {
                Section {
                    LabeledContent("Til", value: "\(Languages.flag(friend.language)) \(friend.language)")
                    LabeledContent("Ohang", value: friend.tone)
                    Picker("Muloqot darajasi", selection: Binding<Friend.Formality?>(
                        get: { friend.formality },
                        set: { value in update { $0.formality = value } }
                    )) {
                        Text("Avto").tag(Friend.Formality?.none)
                        Text("Norasmiy (sen)").tag(Friend.Formality?.some(.informal))
                        Text("Rasmiy (siz)").tag(Friend.Formality?.some(.formal))
                    }
                } footer: {
                    Text("Til va ohangni har skrinshot yangilaydi. Daraja sizniki — ✨ shunga amal qiladi; Avto bo'lsa suhbatdan o'zi aniqlaydi.")
                }
                Section {
                    NavigationLink {
                        InstructionsEditor(
                            title: "Ko'rsatma",
                            placeholder: "Masalan: sinfdoshim, hazil aralash yozamiz; sen deb gapiramiz; u o'zbekcha bir-ikki so'z biladi",
                            initial: friend.notes ?? ""
                        ) { text in update { $0.notes = text.isEmpty ? nil : text } }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Ko'rsatma")
                                Spacer()
                                Text(friend.notes == nil ? "Yo'q" : "\(friend.notes?.count ?? 0) belgi")
                                    .foregroundStyle(.secondary)
                            }
                            if let notes = friend.notes {
                                Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                } footer: {
                    Text("Bu odam bilan qanday gaplashishingiz: kim u, qanday ohangda yozasiz. Kelgan xabar tarjimasi ham, ✨ ham shuni hisobga oladi.")
                }
                Section {
                    LabeledContent("Xotira", value: "\(friend.history?.count ?? 0) xabar")
                    Button("Xotirani tozalash", role: .destructive) { update { $0.history = nil } }
                        .disabled((friend.history ?? []).isEmpty)
                } footer: {
                    Text("Skrinshotlardan yig'ilgan xabarlar — ✨ uchun suhbat konteksti. Faqat shu telefonda.")
                }
                Section {
                    Button("Do'stni o'chirish", role: .destructive) {
                        store.update { state in
                            state.friends?.removeAll { $0.name == name }
                            if state.activeFriend == name { state.activeFriend = nil }
                        }
                        dismiss()
                    }
                }
            } else {
                Text("Bu do'st endi ro'yxatda yo'q.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func update(_ change: (inout Friend) -> Void) {
        store.update { state in
            guard let index = state.friends?.firstIndex(where: { $0.name == name }) else { return }
            change(&state.friends![index])
        }
    }
}
