import SwiftUI

@main
struct TODO_AIApp: App {
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    init() {
        Fonts.register()
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
    }
}
