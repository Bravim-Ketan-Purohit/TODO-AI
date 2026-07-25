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
        return true
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
