import Foundation

/// A build signed with a free Apple ID carries a provisioning profile that lasts 7 days; after that iOS refuses to
/// open the app and the keyboard drops out, with nothing on screen to say why. The profile ships inside the bundle
/// (`embedded.mobileprovision`), so the app and the keyboard can both read when it ends and warn beforehand.
/// App Store builds and the Simulator have no profile — everything here then reports "unknown" and stays silent.
enum ProvisioningExpiry {
    enum Status: Equatable {
        case valid
        /// Inside `warnWindow`.
        case soon
        case expired
    }

    /// From this far before the end the keyboard and the app show the countdown.
    static let warnWindow: TimeInterval = 72 * 3600

    /// Local notifications, relative to the expiry: the last two days, the last hours, and one hour after — the one
    /// that matters when the app is already dead and nothing else would say why.
    static let reminderOffsets: [TimeInterval] = [-48 * 3600, -24 * 3600, -6 * 3600, 3600]

    // MARK: Reading

    /// The expiry of the profile this process was signed with; nil when there is none.
    static func expirationDate(in bundle: Bundle = .main) -> Date? {
        #if DEBUG
        // The Simulator has no profile. `echo 20 > <App Group>/debug-expiry-hours.txt` pretends 20 hours are left.
        if let url = SharedStore.containerURL?.appendingPathComponent("debug-expiry-hours.txt"),
           let text = try? String(contentsOf: url, encoding: .utf8),
           let hours = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return Date(timeIntervalSinceNow: hours * 3600)
        }
        #endif
        guard let path = bundle.path(forResource: "embedded", ofType: "mobileprovision"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path))
        else { return nil }
        return expirationDate(profile: data)
    }

    /// The profile is a signed (CMS) blob with the property list inside as plain XML — cut it out and read it.
    static func expirationDate(profile data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), options: .backwards),
              start.lowerBound < end.upperBound,
              let plist = try? PropertyListSerialization.propertyList(
                from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any]
        else { return nil }
        return plist["ExpirationDate"] as? Date
    }

    // MARK: Meaning

    static func status(expiry: Date, now: Date) -> Status {
        let remaining = expiry.timeIntervalSince(now)
        if remaining <= 0 { return .expired }
        return remaining <= warnWindow ? .soon : .valid
    }

    /// "2 kun" / "20 soat" / "<1 soat". Always rounds down — it must never promise more time than there is. The
    /// extra second only absorbs floating-point noise on exact hours (a reminder set for exactly 6 h before).
    static func remainingText(expiry: Date, now: Date) -> String {
        let remaining = max(0, expiry.timeIntervalSince(now)) + 1
        if remaining >= 24 * 3600 { return "\(Int(remaining / (24 * 3600))) kun" }
        if remaining >= 3600 { return "\(Int(remaining / 3600)) soat" }
        return "<1 soat"
    }

    /// The small orange note beside the keyboard's target pill; nil while there is nothing to warn about.
    static func keyboardNote(expiry: Date?, now: Date) -> String? {
        guard let expiry else { return nil }
        switch status(expiry: expiry, now: now) {
        case .valid: return nil
        case .soon: return "⏳ " + remainingText(expiry: expiry, now: now)
        case .expired: return "⏳ tugadi"
        }
    }

    static func reminderDates(expiry: Date, now: Date) -> [Date] {
        reminderOffsets.map { expiry + $0 }.filter { $0 > now }.sorted()
    }
}
