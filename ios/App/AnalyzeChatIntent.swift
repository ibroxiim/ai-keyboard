import AppIntents
import UniformTypeIdentifiers

/// Back Tap → Shortcut [Take Screenshot → this]. Runs in the background; the result
/// lands in the keyboard's suggestion bar.
struct AnalyzeChatIntent: AppIntent {
    static var title: LocalizedStringResource = "Suhbatni tahlil qil"
    static var description = IntentDescription(
        "DM skrinshotini o'qiydi va kelgan xabar tarjimasi bilan javob takliflarini AI Keyboard klaviaturasiga tayyorlaydi.")
    static var openAppWhenRun = false

    @Parameter(title: "Skrinshot", supportedContentTypes: [.image])
    var screenshot: IntentFile

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let analysis = try await ChatAnalysisService.run(imageData: screenshot.data, fromShortcut: true)
        let meaning = analysis.lastIncomingUz.isEmpty ? analysis.summaryUz : analysis.lastIncomingUz
        let line = analysis.partner.isEmpty ? meaning : "\(analysis.partner): \(meaning)"
        return .result(value: line, dialog: "\(line)")
    }
}
