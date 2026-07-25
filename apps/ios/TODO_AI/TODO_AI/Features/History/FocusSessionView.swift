import ActivityKit
import SwiftUI
import UIKit

/// Focus session (design 5h): a block that defends itself. Just a timer —
/// no system Focus mode, no blocking claims. Ends itself at the block's end.
struct FocusSessionView: View {
    let title: String
    let category: String?
    let endMin: Int
    let taskId: Int?
    var next: String?  // "LUNCH 12:30" — for the Live Activity (5g)
    let onStatus: (Int, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var activity: Activity<FocusActivityAttributes>?

    private func remaining(at now: Date) -> Int {
        let nowMin = Calendar.current.component(.hour, from: now) * 60
            + Calendar.current.component(.minute, from: now)
        let nowSec = Calendar.current.component(.second, from: now)
        return max(0, endMin * 60 - (nowMin * 60 + nowSec))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = remaining(at: context.date)
            let color = DS.category(category)
            VStack(spacing: 0) {
                Spacer()
                HStack(spacing: 8) {
                    Circle().fill(color).frame(width: 6, height: 6)
                    Text("FOCUS · \((category ?? "task").replacingOccurrences(of: "_", with: " ").uppercased())")
                        .font(DS.mono(10)).kerning(1.0).foregroundStyle(DS.ash)
                }
                Text(String(format: "%d:%02d", left / 60, left % 60))
                    .font(DS.mono(64))
                    .foregroundStyle(DS.paper)
                    .monospacedDigit()
                    .padding(.top, 18)
                Text(title)
                    .font(DS.inter(16, .medium)).foregroundStyle(DS.mist)
                    .padding(.top, 6)
                Text("UNTIL \(String(format: "%d:%02d", endMin / 60, endMin % 60))")
                    .font(DS.mono(10)).kerning(0.8).foregroundStyle(DS.ash)
                    .padding(.top, 10)
                Spacer()
                if left == 0 {
                    Text("Block ended.")
                        .font(DS.inter(14)).foregroundStyle(DS.fog)
                        .padding(.bottom, 16)
                }
                Button {
                    if let taskId { onStatus(taskId, "completed") }
                    dismiss()
                } label: {
                    Text(left == 0 ? "Mark done" : "Done early")
                        .font(DS.inter(15, .medium)).foregroundStyle(Color(hex: 0x08090A))
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(DS.acidLime)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                Button {
                    dismiss()
                } label: {
                    Text(left == 0 ? "Close" : "Leave focus")
                        .font(DS.inter(13)).foregroundStyle(DS.ash)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .padding(.top, 4).padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.void)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            startActivity()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            let current = activity
            Task { await current?.end(nil, dismissalPolicy: .immediate) }
        }
    }

    // lock screen + Dynamic Island companion (design 5g)
    private func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              let end = Calendar.current.date(bySettingHour: endMin / 60,
                                              minute: endMin % 60, second: 0, of: .now),
              end > .now else { return }
        activity = try? Activity.request(
            attributes: FocusActivityAttributes(title: title, category: category ?? "task"),
            content: .init(state: .init(endDate: end, next: next), staleDate: end))
    }
}
