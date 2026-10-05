import os
import UserNotifications

/// Schedules the local notifications for the end of the signing profile (see `ProvisioningExpiry`). They are the
/// only reminder that still reaches you when the app is not opened for days — and the one after the deadline is
/// the only one that explains why the app no longer starts. Called on every launch and return to the app, so a
/// reinstall (new profile, new date) replaces the old schedule.
enum ExpiryReminder {
    private static let identifierPrefix = "profile-expiry-"

    /// Nil on builds without a profile (Simulator, App Store).
    static func refresh() async {
        guard let expiry = ProvisioningExpiry.expirationDate() else { return }
        let center = UNUserNotificationCenter.current()
        // Only asks the first time; afterwards it just reports the choice.
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }

        let now = Date()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) })

        let dates = ProvisioningExpiry.reminderDates(expiry: expiry, now: now)
        Logger(subsystem: "com.ibrokhim.dmtranslator", category: "expiry")
            .info("profile ends \(expiry, privacy: .public); \(dates.count) reminders scheduled: \(dates.map(\.description).joined(separator: ", "), privacy: .public)")
        for date in dates {
            let content = UNMutableNotificationContent()
            content.title = "AI Keyboard"
            content.body = date > expiry
                ? "Imzo muddati tugadi — ilova va klaviatura ochilmaydi. Telefonni Mac'ga ulab, qayta o'rnating."
                : "Imzo \(ProvisioningExpiry.remainingText(expiry: expiry, now: date)) ichida tugaydi. Telefonni Mac'ga ulab, qayta o'rnating — keyin ilova ochilmay qoladi."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: date.timeIntervalSince(now), repeats: false)
            let request = UNNotificationRequest(
                identifier: identifierPrefix + String(Int(date.timeIntervalSince1970)), content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    /// False when the user turned notifications off — the app then says so, since the reminder cannot reach them.
    static func notificationsAllowed() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status != .denied
    }
}
