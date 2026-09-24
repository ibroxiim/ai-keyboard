import Foundation

/// The keyboards enabled in Settings → General → Keyboard → Keyboards, as iOS keeps them in the global defaults.
enum KeyboardOrder {
    static let tarjimonID = "com.ibrokhim.dmtranslator.keyboard"

    private static var keyboards: [String]? {
        UserDefaults.standard.array(forKey: "AppleKeyboards") as? [String]
    }

    static var tarjimonAdded: Bool {
        keyboards?.contains { $0.hasPrefix(tarjimonID) } ?? false
    }
}
