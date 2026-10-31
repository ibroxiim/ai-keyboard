import CoreGraphics

enum KeyboardMetrics {
    static let statusHeight: CGFloat = 34
    static let chipsHeight: CGFloat = 58
    static let barHeight: CGFloat = 6 + statusHeight + 6 + chipsHeight + 4
    /// Status row only — about the height of the system keyboard's prediction bar.
    static let compactBarHeight: CGFloat = 6 + statusHeight + 6
    static let keyHeight: CGFloat = 44
    static let rowGap: CGFloat = 11
    static let keyGap: CGFloat = 6
    static let sideInset: CGFloat = 3
    static let keysTopInset: CGFloat = 8
    static let keysHeight: CGFloat = keysTopInset + keyHeight * 4 + rowGap * 3 + 4
    /// The GIF strip: tall enough for a readable preview, like Gboard's.
    static let gifStripHeight: CGFloat = 118
    static let gifBarHeight: CGFloat = 6 + statusHeight + 6 + gifStripHeight + 4

    /// What sits above the keys; the keyboard grows and shrinks with it.
    enum BarMode: Equatable { case compact, expanded, gif }

    static func barHeight(for mode: BarMode) -> CGFloat {
        switch mode {
        case .compact: compactBarHeight
        case .expanded: barHeight
        case .gif: gifBarHeight
        }
    }

    static func totalHeight(bar mode: BarMode) -> CGFloat { barHeight(for: mode) + keysHeight }

    static func totalHeight(barExpanded: Bool) -> CGFloat { totalHeight(bar: barExpanded ? .expanded : .compact) }
}
