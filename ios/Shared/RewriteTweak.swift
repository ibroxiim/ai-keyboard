import Foundation

/// "Biroz qisqaroq qil" — what the user can ask of ✨ after seeing the variants, the way they would in a chat
/// with the model. Several can be on at once; every change asks for the variants again.
enum RewriteTweak: String, CaseIterable, Codable {
    case shorter, warmer, formal, playful

    var label: String {
        switch self {
        case .shorter: "qisqaroq"
        case .warmer: "iliqroq"
        case .formal: "rasmiyroq"
        case .playful: "hazil"
        }
    }

    /// For the prompt's `Adjust:` line.
    var instruction: String {
        switch self {
        case .shorter: "shorter"
        case .warmer: "warmer and more affectionate"
        case .formal: "more formal and polite"
        case .playful: "playful, with light humour"
        }
    }
}
