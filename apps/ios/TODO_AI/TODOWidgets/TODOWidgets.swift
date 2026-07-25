import SwiftUI
import WidgetKit

// ── shared snapshot (written by the app via WidgetBridge) ───────────

private struct WBlock: Codable {
    let title: String
    let category: String?
    let start: String
    let end: String
    let fixed: Bool
}

private let SUITE = "group.com.bravim.TODO-AI"

private let isoParser: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

private func loadBlocks() -> [WBlock] {
    guard let defaults = UserDefaults(suiteName: SUITE),
          let data = defaults.data(forKey: "todayBlocks"),
          let blocks = try? JSONDecoder().decode([WBlock].self, from: data) else { return [] }
    // stale snapshot from a previous day renders nothing rather than lies
    let today = Calendar.current.startOfDay(for: Date())
    return blocks.filter {
        guard let s = isoParser.date(from: $0.start) else { return false }
        return Calendar.current.startOfDay(for: s) == today
    }
}

// ── design tokens (widget target can't see the app's DS) ────────────

private extension Color {
    init(hexValue: UInt) {
        self.init(red: Double((hexValue >> 16) & 0xFF) / 255,
                  green: Double((hexValue >> 8) & 0xFF) / 255,
                  blue: Double(hexValue & 0xFF) / 255)
    }
}

let wVoid = Color(hexValue: 0x08090A)
let wPaper = Color(hexValue: 0xE8EAED)
let wMist = Color(hexValue: 0xB4B8BD)
let wAsh = Color(hexValue: 0x62666D)
let wLime = Color(hexValue: 0xE4F222)

func wCategoryColor(_ category: String?) -> Color {
    switch category {
    case "deep_work": Color(hexValue: 0x6366F1)
    case "health": Color(hexValue: 0x27A644)
    case "meals": Color(hexValue: 0x02B8CC)
    case "admin": Color(hexValue: 0x8B5CF6)
    case "social": Color(hexValue: 0xEB5757)
    case nil: Color(hexValue: 0x62666D)
    default: Color(hexValue: 0x6366F1)
    }
}

// ── timeline ────────────────────────────────────────────────────────

struct NowEntry: TimelineEntry {
    let date: Date
    let current: (title: String, category: String?, end: Date)?
    let next: (title: String, start: Date)?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> NowEntry {
        NowEntry(date: .now,
                 current: ("Deep work — design doc", "deep_work", .now.addingTimeInterval(3600)),
                 next: ("Lunch", .now.addingTimeInterval(3600)))
    }

    func getSnapshot(in context: Context, completion: @escaping (NowEntry) -> Void) {
        completion(entry(at: .now, blocks: loadBlocks()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowEntry>) -> Void) {
        let blocks = loadBlocks()
        let now = Date()
        var times: Set<Date> = [now]
        for b in blocks {
            if let s = isoParser.date(from: b.start), s > now { times.insert(s) }
            if let e = isoParser.date(from: b.end), e > now { times.insert(e) }
        }
        let entries = times.sorted().prefix(16).map { entry(at: $0, blocks: blocks) }
        completion(Timeline(entries: Array(entries), policy: .atEnd))
    }

    private func entry(at t: Date, blocks: [WBlock]) -> NowEntry {
        typealias Parsed = (block: WBlock, start: Date, end: Date)
        let parsed: [Parsed] = blocks.compactMap {
            guard let s = isoParser.date(from: $0.start),
                  let e = isoParser.date(from: $0.end) else { return nil }
            return ($0, s, e)
        }
        // the app's own blocks win over fixed events when both cover "now"
        let running = parsed.filter { $0.start <= t && t < $0.end }
            .sorted { !$0.block.fixed && $1.block.fixed }
        let upcoming = parsed.filter { $0.start > t }
            .min { $0.start < $1.start }
        return NowEntry(
            date: t,
            current: running.first.map { ($0.block.title, $0.block.category, $0.end) },
            next: upcoming.map { ($0.block.title, $0.start) })
    }
}

// ── medium widget (design 5f) ───────────────────────────────────────

struct NowWidgetView: View {
    var entry: NowEntry

    private func hhmm(_ d: Date) -> String {
        let c = Calendar.current
        return String(format: "%d:%02d", c.component(.hour, from: d), c.component(.minute, from: d))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let current = entry.current {
                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(wCategoryColor(current.category)).frame(width: 5, height: 5)
                        Text("TODO_AI · NOW")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .kerning(0.8).foregroundStyle(wAsh)
                    }
                    Spacer()
                    Text("UNTIL \(hhmm(current.end))")
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(wAsh)
                }
                Text(current.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(wPaper)
                    .lineLimit(2)
                    .padding(.top, 8)
            } else {
                HStack(spacing: 6) {
                    Circle().fill(wAsh).frame(width: 5, height: 5)
                    Text("TODO_AI")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .kerning(0.8).foregroundStyle(wAsh)
                }
                Text("Nothing running.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(wMist)
                    .padding(.top, 8)
            }
            Spacer(minLength: 8)
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5)
            HStack(spacing: 6) {
                Text("NEXT")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .kerning(0.7).foregroundStyle(wAsh)
                if let next = entry.next {
                    Text("\(next.title.uppercased()) \(hhmm(next.start))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(wMist).lineLimit(1)
                } else {
                    Text("— CLEAR").font(.system(size: 9, design: .monospaced)).foregroundStyle(wAsh)
                }
                Spacer()
            }
            .padding(.top, 8)
        }
        .containerBackground(wVoid, for: .widget)
    }
}

struct TODOWidgets: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TODOWidgetsNow", provider: Provider()) { entry in
            NowWidgetView(entry: entry)
        }
        .configurationDisplayName("Now")
        .description("The block happening now, and what's next.")
        .supportedFamilies([.systemMedium])
    }
}
