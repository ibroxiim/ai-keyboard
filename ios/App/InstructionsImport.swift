import Foundation

/// A file picked in Files for "Tarjima uslubi" or a friend's notes: plain text or Markdown, read into the editor.
enum InstructionsImport {
    /// The file's text, tidied and cut at `Prompts.styleLimit`; nil when it is empty or not text at all.
    static func text(from data: Data) -> String? {
        guard var text = decode(data) else { return nil }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        // A UTF-8 byte-order mark survives decoding as U+FEFF, which is not whitespace to `trimmingCharacters`.
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(Prompts.styleLimit))
    }

    private static func decode(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        // UTF-16 only with a byte-order mark: without one, any bytes "decode" into nonsense instead of failing.
        let head = [UInt8](data.prefix(2))
        guard head == [0xFF, 0xFE] || head == [0xFE, 0xFF] else { return nil }
        return String(data: data, encoding: .utf16)
    }
}
