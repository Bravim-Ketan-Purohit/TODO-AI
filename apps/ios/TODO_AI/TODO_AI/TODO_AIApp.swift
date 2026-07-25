import BackgroundTasks
import SwiftUI
import UserNotifications

@main
struct TODO_AIApp: App {
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @Environment(\.scenePhase) private var scenePhase

    static let refreshID = "com.bravim.TODO-AI.disruptions"

    init() {
        Fonts.register()
        // disruption watch (5d): while backgrounded, check whether the calendar
        // changed under a synced task and nudge before the user hits the overlap
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshID,
                                        using: nil) { task in
            Self.handleRefresh(task as! BGAppRefreshTask)
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasOnboarded {
                    MainTabView()
                } else {
                    OnboardingView()
                }
            }
            .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Self.scheduleRefresh() }
        }
    }

    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func handleRefresh(_ task: BGAppRefreshTask) {
        scheduleRefresh()  // chain the next check
        let work = Task {
            if let d = (try? await API.disruptions())?.disruption,
               let first = d.moves.first {
                let content = UNMutableNotificationContent()
                content.title = "Calendar changed"
                content.body = "\"\(d.cause)\" now collides with \(first.title). Open to reflow."
                content.sound = .default
                try? await UNUserNotificationCenter.current().add(UNNotificationRequest(
                    identifier: "disruption", content: content, trigger: nil))
            }
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
}
