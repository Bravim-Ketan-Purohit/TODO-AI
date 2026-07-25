import ActivityKit
import Foundation
import WidgetKit

/// Shared-container snapshot the widget renders from (design 5f). The app
/// writes it whenever /today loads; the widget never talks to the network.
struct WBlock: Codable {
    let title: String
    let category: String?
    let start: String  // ISO
    let end: String
    let fixed: Bool
}

enum WidgetBridge {
    static let suite = "group.com.bravim.TODO-AI"

    static func save(_ p: DayPayload) {
        var blocks = p.tasks.filter { $0.status != "missed" }.map {
            WBlock(title: $0.title, category: $0.category,
                   start: $0.startTs, end: $0.endTs, fixed: false)
        }
        blocks += p.anchors.map {
            WBlock(title: $0.title, category: $0.category,
                   start: $0.start, end: $0.end, fixed: false)
        }
        blocks += p.fixed.map {
            WBlock(title: $0.title, category: nil, start: $0.start, end: $0.end, fixed: true)
        }
        blocks.sort { $0.start < $1.start }
        guard let defaults = UserDefaults(suiteName: suite),
              let data = try? JSONEncoder().encode(blocks) else { return }
        defaults.set(data, forKey: "todayBlocks")
        defaults.set(p.date, forKey: "todayDate")
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Focus session Live Activity (design 5g). The widget extension holds an
/// identical copy of this type — ActivityKit matches them by name + encoding.
struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endDate: Date
        var next: String?  // "LUNCH 12:30"
    }

    var title: String
    var category: String
}
