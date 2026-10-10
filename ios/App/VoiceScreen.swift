import SwiftUI

/// The dictation sheet: opened by the keyboard's 🎤 (and by the "Gapirish" row), it records, shows the progress and
/// the result. Also the fallback when the keyboard cannot open the app: the text can be copied from here.
struct VoiceScreen: View {
    @EnvironmentObject private var voice: VoiceController

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                content
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .navigationTitle("Gapirish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Yopish") { voice.showsScreen = false }
                }
            }
        }
        .interactiveDismissDisabled(voice.state?.phase == .recording)
    }

    @ViewBuilder
    private var content: some View {
        switch voice.state?.phase {
        case .recording: recording
        case .transcribing: transcribing
        case .done: result
        case .failed: failure
        case nil: ready
        }
    }

    private var ready: some View {
        VStack(spacing: 20) {
            icon("mic.fill", color: .accentColor)
            Text("O'zbekcha gapiring — matn yoziladi.").multilineTextAlignment(.center)
            Button("Yozishni boshlash") { start() }.buttonStyle(.borderedProminent)
        }
    }

    private var recording: some View {
        VStack(spacing: 20) {
            icon("mic.fill", color: .red)
            if let since = voice.state?.since {
                // One tick a second, only while this screen is on and recording.
                TimelineView(.periodic(from: since, by: 1)) { context in
                    Text(Self.clock(context.date.timeIntervalSince(since)))
                        .font(.system(size: 34, weight: .semibold, design: .monospaced))
                }
            }
            Text("Chatga qayting — yozuv davom etadi.\nPastki chekka bo'ylab o'ngga suring. Tugagach klaviaturadagi ⏹ ni bosing.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("To'xtatish") { voice.stop() }.buttonStyle(.borderedProminent).tint(.red)
        }
    }

    private var transcribing: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Matn yozilmoqda…").foregroundStyle(.secondary)
        }
    }

    private var result: some View {
        VStack(spacing: 16) {
            Text(voice.state?.text ?? "")
                .font(.title3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Klaviaturada «🎤 Qo'yish» tugmasi bu matnni maydonga qo'yadi.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Nusxa olish") { UIPasteboard.general.string = voice.state?.text }
                    .buttonStyle(.bordered)
                Button("Qayta yozish") { start() }.buttonStyle(.bordered)
            }
        }
    }

    private var failure: some View {
        VStack(spacing: 16) {
            icon("exclamationmark.triangle.fill", color: .orange)
            Text(voice.state?.error ?? "Xato").multilineTextAlignment(.center)
            if voice.state?.error == VoiceError.microphoneDenied.localizedDescription {
                Button("Sozlamalarni ochish") {
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                }
                .buttonStyle(.borderedProminent)
            }
            HStack(spacing: 12) {
                if voice.canRetry {
                    Button("Qayta urinish") { voice.retry() }.buttonStyle(.borderedProminent)
                }
                Button("Qayta yozish") { start() }.buttonStyle(.bordered)
            }
        }
    }

    private func icon(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 44))
            .foregroundStyle(.white)
            .frame(width: 96, height: 96)
            .background(Circle().fill(color))
    }

    private func start() {
        Task { await voice.start(id: UUID().uuidString) }
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
