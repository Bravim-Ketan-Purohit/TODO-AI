import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        VStack(spacing: 16) {
            Text("TODO_AI")
                .font(.largeTitle)
            Text("Type your day. It becomes your calendar.")
                .foregroundStyle(.secondary)
            Button("Get started") { hasOnboarded = true }
        }
        .padding()
    }
}
