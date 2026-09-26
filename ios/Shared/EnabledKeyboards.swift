import Foundation

/// The keyboards enabled in Settings → General → Keyboard → Keyboards, as iOS keeps them in the global defaults.
enum EnabledKeyboards {
    static let aiKeyboardID = "com.ibrokhim.dmtranslator.keyboard"

    private static var keyboards: [String]? {
        UserDefaults.standard.array(forKey: "AppleKeyboards") as? [String]
    }

    static var containsAIKeyboard: Bool {
        keyboards?.contains { $0.hasPrefix(aiKeyboardID) } ?? false
    }
}
