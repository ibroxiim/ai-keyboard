import Foundation

/// What became of one touch on the keys. The keyboard's journal counts these; the app's Diagnostika screen
/// reads the counts back by `rawValue`.
enum TouchOutcome: String {
    case typed
    /// Typed early because the next finger landed while this one was still down.
    case rolledOver
    /// Typed after the finger slid onto another character.
    case slid
    /// Typed because the keys were rebuilt under the finger (layer or alphabet change).
    case committedOnRebuild
    /// UIKit never delivered the end; typed when the next touch showed it was gone.
    case recoveredMissingEnd
    /// The system cancelled the touch; nothing was typed.
    case cancelledBySystem
    /// Space, return, backspace, shift or another function key did its action.
    case function

    var producedCharacter: Bool {
        switch self {
        case .typed, .rolledOver, .slid, .committedOnRebuild, .recoveredMissingEnd: true
        case .cancelledBySystem, .function: false
        }
    }
}
