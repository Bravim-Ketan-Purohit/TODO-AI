import UserNotifications

/// The two daily nudges (design 4d): morning plan prompt + evening recap.
/// No streaks, no badges, no spam.
enum Nudges {
    static func enable() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }
        schedule(id: "morning-plan", hour: 7, minute: 15,
                 title: "Ready to plan your day?",
                 body: "Brain-dump your morning — it lands on your calendar.")
        schedule(id: "evening-recap", hour: 21, minute: 30,
                 title: "Wrap up the day?",
                 body: "A quick recap tunes where things land next week.")
        scheduleWeekly()
        return true
    }

    /// Sunday 20:00 — weekly review (design 5b). Safe to call repeatedly;
    /// re-adding the same identifier replaces the request.
    static func ensureWeeklyIfAuthorized() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            scheduleWeekly()
        }
    }

    private static func scheduleWeekly() {
        let content = UNMutableNotificationContent()
        content.title = "Your week is ready"
        content.body = "90 seconds to close it out — mostly tapping."
        content.sound = .default
        var comps = DateComponents()
        comps.weekday = 1  // Sunday
        comps.hour = 18    // design 7a: the 6pm invitation
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "weekly-review", content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
    }

    private static func schedule(id: String, hour: Int, minute: Int, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let request = UNNotificationRequest(
            identifier: id, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true))
        UNUserNotificationCenter.current().add(request)
    }
}
