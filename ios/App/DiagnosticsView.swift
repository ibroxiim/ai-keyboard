import SwiftUI

/// Sessions the keyboard recorded, live: the keyboard posts `AppGroup.diagnosticsChanged` after writing one.
@MainActor
final class DiagnosticsLog: ObservableObject {
    @Published private(set) var sessions: [DiagnosticSession] = []
    private var observer: DarwinObserver?

    init() {
        observer = DarwinObserver(name: AppGroup.diagnosticsChanged) { [weak self] in self?.reload() }
        reload()
    }

    /// Newest first.
    func reload() {
        sessions = DiagnosticsStore.load().reversed()
    }

    func clear() {
        DiagnosticsStore.clear()
        reload()
    }
}

/// Diagnostika: the keyboard's session recording switch, the typing test and the recorded sessions.
struct DiagnosticsView: View {
    @ObservedObject var store: SharedStateModel
    @StateObject private var log = DiagnosticsLog()
    @State private var typed = ""
    @State private var diff: PhraseDiff?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Form {
            Section {
                Toggle("Diagnostika", isOn: Binding(
                    get: { store.state.diagnosticsEnabled ?? false },
                    set: { on in store.update { $0.diagnosticsEnabled = on } }
                ))
            } footer: {
                Text("Yoqilganda klaviatura har ochilishida qisqa hisobot yozadi: teginishlar, yo'qolganlari, kechikish, CPU, harorat. Yozilgan matn saqlanmaydi. Full Access kerak.")
            }
            testSection
            sessionsSection
        }
        .navigationTitle("Diagnostika")
        .onAppear { log.reload() }
    }

    // MARK: Typing test

    private var testSection: some View {
        Section {
            Text(PhraseDiff.testPhrase).font(.callout)
            TextField("Iborani AI Keyboard bilan shu yerga yozing", text: $typed, axis: .vertical)
                .lineLimit(3...8)
                .focused($fieldFocused)
                .textContentType(UITextContentType(rawValue: DiagnosticsMarker.contentType))
                .submitLabel(.continue)
                .autocorrectionDisabled()
            HStack {
                Button("Tugatish") {
                    fieldFocused = false
                    diff = PhraseDiff.compare(expected: PhraseDiff.testPhrase, typed: typed)
                }
                .disabled(typed.isEmpty)
                .buttonStyle(.borderless)
                Spacer()
                Button("Qaytadan", role: .destructive) {
                    typed = ""
                    diff = nil
                }
                .buttonStyle(.borderless)
            }
            if let diff { testResult(diff) }
        } header: {
            Text("Yozish testi")
        } footer: {
            Text("Diagnostika yoqiq bo'lsin. Iborani odatdagidek yozing, xatolarni tuzatmang, keyin «Tugatish».")
        }
    }

    @ViewBuilder
    private func testResult(_ diff: PhraseDiff) -> some View {
        let session = log.sessions.first { $0.testMode }
        VStack(alignment: .leading, spacing: 4) {
            Text(diff.isPerfect
                ? "Yozilgan qism to'liq mos"
                : "Tushib qolgan: \(diff.missing) · ortiqcha: \(diff.extra) · almashgan: \(diff.substituted)")
                .font(.headline)
            if diff.unfinished > 0 {
                Text("Iboraning yozilmagan qismi: \(diff.unfinished) belgi")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let session {
                Text("Klaviatura: \(session.touches) teginish, \(session.typed) harf, bekor qilingan \(session.lost), tiklangan \(session.outcomes[TouchOutcome.recoveredMissingEnd.rawValue] ?? 0)")
                    .font(.footnote)
                if diff.missing > 0 && session.lost == 0 {
                    Text("Matnda harf yetishmaydi, lekin klaviatura hech bir teginishni yo'qotmagan: harf yo bosilmagan, yo teginish klaviaturaga yetib kelmagan (tizim darajasi).")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } else {
                Text("Klaviatura hisoboti hali kelmadi — Diagnostika yoqiqmi?")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Sessions

    private var sessionsSection: some View {
        Section {
            if log.sessions.isEmpty {
                Text("Hali sessiya yo'q").foregroundStyle(.secondary)
            }
            ForEach(log.sessions) { session in
                SessionRow(session: session)
            }
            if let url = DiagnosticsStore.fileURL, !log.sessions.isEmpty {
                ShareLink(item: url) {
                    Label("JSON eksport", systemImage: "square.and.arrow.up")
                }
                Button("Tozalash", role: .destructive) { log.clear() }
            }
        } header: {
            Text("Sessiyalar")
        }
    }
}

private struct SessionRow: View {
    let session: DiagnosticSession

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(session.start, style: .time)
                Text(String(format: "%.0f s", session.duration)).foregroundStyle(.secondary)
                if session.testMode {
                    Text("test")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                }
                Spacer()
                Text(session.thermal.map(\.state).joined(separator: "→"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(session.touches) teginish · yo'qolgan \(session.lost) · p95 \(milliseconds(session.upToInsertMs?.p95)) · CPU \(String(format: "%.1f", session.cpu.percent))% · \(String(format: "%.0f", session.memoryMB.end)) MB")
                .font(.caption)
                .foregroundStyle(.secondary)
            if session.mainBusy.over50ms > 0 {
                Text("Asosiy oqim > 50 ms: \(session.mainBusy.over50ms) marta, eng uzuni \(String(format: "%.0f", session.mainBusy.maxMs)) ms")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func milliseconds(_ value: Double?) -> String {
        value.map { String(format: "%.1f ms", $0) } ?? "—"
    }
}
