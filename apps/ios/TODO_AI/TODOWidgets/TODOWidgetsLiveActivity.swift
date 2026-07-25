import ActivityKit
import SwiftUI
import WidgetKit

/// Identical copy of the app target's attributes — ActivityKit matches
/// activities across targets by type name + encoding.
struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endDate: Date
        var next: String?  // "LUNCH 12:30"
    }

    var title: String
    var category: String
}

private func laCategoryColor(_ category: String) -> Color {
    switch category {
    case "deep_work": Color(red: 0.39, green: 0.40, blue: 0.95)
    case "health": Color(red: 0.15, green: 0.65, blue: 0.27)
    case "meals": Color(red: 0.01, green: 0.72, blue: 0.80)
    case "admin": Color(red: 0.55, green: 0.36, blue: 0.96)
    case "social": Color(red: 0.92, green: 0.34, blue: 0.34)
    default: Color(red: 0.39, green: 0.40, blue: 0.95)
    }
}

/// Lock screen + Dynamic Island during a focus session (design 5g).
struct TODOWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            // lock screen banner
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(laCategoryColor(context.attributes.category))
                            .frame(width: 5, height: 5)
                        Text("FOCUS · \(context.attributes.category.replacingOccurrences(of: "_", with: " ").uppercased())")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .kerning(0.8)
                            .foregroundStyle(Color(red: 0.38, green: 0.40, blue: 0.43))
                    }
                    Spacer()
                    Text(timerInterval: Date.now...context.state.endDate, countsDown: true)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.89, green: 0.95, blue: 0.13))
                        .frame(width: 60, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                }
                Text(context.attributes.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.91, green: 0.92, blue: 0.93))
                if let next = context.state.next {
                    Text("NEXT · \(next)")
                        .font(.system(size: 9, design: .monospaced)).kerning(0.7)
                        .foregroundStyle(Color(red: 0.38, green: 0.40, blue: 0.43))
                }
            }
            .padding(14)
            .activityBackgroundTint(Color(red: 0.03, green: 0.035, blue: 0.04))
            .activitySystemActionForegroundColor(Color(red: 0.89, green: 0.95, blue: 0.13))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Circle().fill(laCategoryColor(context.attributes.category))
                            .frame(width: 6, height: 6)
                        Text(context.attributes.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date.now...context.state.endDate, countsDown: true)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .frame(width: 56, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let next = context.state.next {
                        Text("NEXT · \(next)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Circle().fill(laCategoryColor(context.attributes.category))
                    .frame(width: 8, height: 8)
            } compactTrailing: {
                Text(timerInterval: Date.now...context.state.endDate, countsDown: true)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .frame(width: 44, alignment: .trailing)
            } minimal: {
                Circle().fill(laCategoryColor(context.attributes.category))
                    .frame(width: 8, height: 8)
            }
        }
    }
}
