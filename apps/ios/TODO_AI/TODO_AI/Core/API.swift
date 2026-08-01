import Foundation

// ── Models (mirror apps/api responses; snake_case auto-converted) ───

struct ChatQuestion: Decodable, Hashable {
    let taskTitle: String
    let question: String
    let suggestions: [String]
}

struct PlanItem: Decodable, Hashable, Identifiable {
    let title: String
    let category: String?
    let start: String
    let end: String
    let fixed: Bool
    let location: String?
    var id: String { title + start }
}

struct EditInfo: Decodable, Hashable {
    let title: String
    let category: String?
    let oldStart: String
    let oldEnd: String
    let newStart: String?
    let newEnd: String?
    let deleted: Bool
}

struct FixOption: Decodable, Hashable {
    let title: String
    let subtitle: String
}

struct ChatReply: Decodable {
    let type: String   // clarify | proposal | synced | edited | confirm_delete | overflow | info
    let text: String
    let questions: [ChatQuestion]
    let plan: [PlanItem]
    let edits: [EditInfo]
    let options: [FixOption]
    let suggestedCategories: [String]
}

struct AnchorRecord: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String
    let category: String
    let days: [String]
    let startTime: String?
    let endTime: String?
    let until: String?
}

struct NudgeDay: Decodable, Hashable {
    let day: String
    let status: String  // done | missed | none
}

struct Nudge: Decodable {
    let kind: String
    let text: String
    let gridLabel: String
    let week: [NudgeDay]
    let note: String
    let question: String
    let options: [String]
    let suggestedWorkout: String
}

struct NudgeResponse: Decodable {
    let nudge: Nudge?
}

struct RecapOpenTask: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String
    let category: String
    let start: String
}

struct Recap: Decodable {
    let date: String
    let done: Int
    let total: Int
    let open: [RecapOpenTask]
}

struct RolloverTask: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String
    let category: String
    let durationMinutes: Int
    let missedTime: String
    let fitsToday: String?
}

struct Rollover: Decodable {
    let yesterday: String
    let done: Int
    let total: Int
    let open: [RolloverTask]
    let backlog: [BacklogItem]?
    let stale: [BacklogItem]?
    let deadlines: [DeadlineAlert]?
}

struct RecoveryBlock: Decodable, Hashable {
    let start: String
    let minutes: Int
    let title: String
}

struct DeadlineAlert: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String
    let dueDate: String
    let category: String
    let targetMinutes: Int
    let doneMinutes: Int
    let bookedMinutes: Int
    let behindMinutes: Int
    let recovery: [RecoveryBlock]
    let recoverable: Int
}

struct BacklogItem: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String
    let category: String
    let durationMinutes: Int
    let fitsAt: String?
    let createdAt: String?
    let daysParked: Int?
}

struct WeekCategory: Decodable, Hashable {
    let category: String
    let done: Int
    let total: Int
    let pct: Int
    let doneHours: Double?
    let budgetHours: Double?
    let suggestedBudget: Double?
}

struct WeekInsight: Decodable {
    let category: String
    let suggestedWindow: String
    let text: String
    let options: [String]
}

struct WeekReview: Decodable, Identifiable {
    var id: String { "\(done)-\(total)-\(dropped.count)" }
    let done: Int
    let total: Int
    let categories: [WeekCategory]
    let avgSlipMin: Int?
    let insight: WeekInsight?
    let bestDay: String?
    let dropped: [DroppedTask]
}

struct GapOffer: Decodable {
    let minutes: Int
    let untilTitle: String
    let untilTime: String
    let start: String
    let item: BacklogItem
}

struct GapResponse: Decodable {
    let gap: GapOffer?
}

struct Briefing: Decodable {
    let title: String
    let body: String
}

struct PrepOffer: Decodable {
    let meetingTitle: String
    let meetingStart: String
    let attendees: Int
    let start: String
    let minutes: Int
}

struct PrepResponse: Decodable {
    let prep: PrepOffer?
}

struct DisruptionMove: Decodable, Hashable {
    let taskId: Int
    let title: String
    let category: String
    let oldStart: String
    let oldEnd: String
    let newStart: String
    let newEnd: String
    let cause: String
}

struct Disruption: Decodable {
    let cause: String
    let moves: [DisruptionMove]
    let unplaced: [String]
}

struct DeletedTask: Decodable, Identifiable, Hashable {
    let taskId: Int
    let title: String
    let category: String
    let start: String
    var id: Int { taskId }
}

struct DisruptionResponse: Decodable {
    let disruption: Disruption?
    let deleted: [DeletedTask]?
    let followed: [EditInfo]?  // gcal-side moves the backend already synced
}

struct TaskItem: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String
    let category: String
    let startTs: String
    let endTs: String
    let status: String   // planned | completed | missed | rescheduled
    let location: String?
}

struct AnchorItem: Decodable, Identifiable, Hashable {
    let taskId: Int
    let title: String
    let category: String
    let start: String
    let end: String
    let location: String?
    var id: Int { taskId }
}

struct FixedEvent: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let start: String
    let end: String
}

struct DayPayload: Decodable {
    let date: String
    let tasks: [TaskItem]
    let anchors: [AnchorItem]
    let fixed: [FixedEvent]
}

struct DayDot: Decodable, Hashable {
    let category: String
    let done: Bool
    let current: Bool
}

struct HistoryDay: Decodable, Identifiable {
    let date: String
    let done: Int
    let total: Int
    let categories: [String]
    let dots: [DayDot]
    let hasNote: Bool
    var id: String { date }
}

struct NoteItem: Decodable, Identifiable, Hashable {
    let date: String
    let mood: String
    let text: String
    let hasPhoto: Bool
    let done: Int
    let total: Int
    var id: String { date }
}

struct DroppedTask: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String
    let category: String
    let date: String
}

struct WrappedWeek: Decodable, Hashable {
    let plannedMonday: Bool
    let pct: Int
}

struct WrappedChange: Decodable, Hashable {
    let category: String
    let beforePct: Int
    let afterPct: Int
}

struct WrappedData: Decodable {
    let month: String
    let rangeLabel: String
    let monthKey: String
    let plannedDays: Int
    let totalTasks: Int
    let landedPct: Int
    let deepHours: Int
    let deepDelta: Int?
    let weeks: [WrappedWeek]
    let change: WrappedChange?
}

struct WrappedResponse: Decodable {
    let wrapped: WrappedData?
}

struct Profile: Codable {
    var role: String?
    var wake = "07:00"
    var sleep = "23:00"
    var energyPeak = "morning"
    var lunch = "12:30"
    var workout: String?
    // role packs — stored in the backend's profile blob; the LLM reads them
    var deepWorkMinutes: Int?
    var meetingDays: [String]?
    var codeReview: String?
    var onCall: Bool?
    var studyBlockMinutes: Int?
    var studyTime: String?
    var breaks: String?
    var deadlineBuffer: String?
    var customCategories: [String]?
    var categoryWindows: [String: String]?
    var weeklyBudgets: [String: Double]?
}

struct AnchorsSummary: Decodable {
    let classes: Int
    let until: String?
}

struct Me: Decodable {
    let email: String
    let profile: Profile?
    let anchors: AnchorsSummary?
}

// ── Client ──────────────────────────────────────────────────────────

enum APIError: LocalizedError {
    case noSession
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .noSession:
            return "Not signed in"
        case let .http(code, body):
            // backend errors carry a human message in {"detail": "..."} — show that
            if let data = body.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = obj["detail"] as? String {
                return detail
            }
            return "Server error \(code): \(body)"
        }
    }
}

enum API {
    // Simulator reaches the Mac's localhost directly; a physical device goes
    // through the ngrok tunnel (https, so Google OAuth + ATS are both happy).
    #if targetEnvironment(simulator)
    static var base = URL(string: "http://127.0.0.1:8000")!
    #else
    static var base = URL(string: "https://stunner-resolved-pampered.ngrok-free.dev")!
    #endif
    static var tz: String { TimeZone.current.identifier }

    static var authStartURL: URL { base.appending(path: "/auth/google/start") }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private static func request<T: Decodable>(
        _ path: String, method: String = "GET", body: [String: Any]? = nil
    ) async throws -> T {
        guard let token = Keychain.sessionToken else { throw APIError.noSession }
        // URL(string:relativeTo:) keeps query strings intact (appending(path:) encodes "?")
        guard let url = URL(string: path, relativeTo: base) else {
            throw APIError.http(0, "Bad path \(path)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("1", forHTTPHeaderField: "ngrok-skip-browser-warning")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw APIError.http(code, String(decoding: data, as: UTF8.self))
        }
        return try decoder.decode(T.self, from: data)
    }

    // Endpoints
    static func chat(message: String? = nil, approve: Bool = false,
                     deleteDecision: String? = nil) async throws -> ChatReply {
        try await request("/chat", method: "POST",
                          body: ["message": message as Any, "approve": approve,
                                 "delete_decision": deleteDecision as Any, "tz": tz])
    }

    static func nudges() async throws -> NudgeResponse {
        try await request("/nudges?tz=\(tz)")
    }

    static func anchors() async throws -> [AnchorRecord] {
        try await request("/anchors")
    }

    static func addAnchor(title: String, startTime: String, endTime: String) async throws {
        struct OK: Decodable { let ok: Bool }
        let _: OK = try await request("/anchors?tz=\(tz)", method: "POST",
                                      body: ["title": title, "start_time": startTime,
                                             "end_time": endTime])
    }

    static func recap() async throws -> Recap {
        try await request("/recap?tz=\(tz)")
    }

    static func rollover() async throws -> Rollover {
        try await request("/rollover?tz=\(tz)")
    }

    static func applyRollover(carry: [Int], drop: [Int]) async throws {
        struct Result: Decodable { let dropped: Int }
        let _: Result = try await request("/rollover?tz=\(tz)", method: "POST",
                                          body: ["carry": carry, "drop": drop])
    }

    static func weekReview() async throws -> WeekReview {
        try await request("/week-review?tz=\(tz)")
    }

    static func resolveReview(carry: [Int], backlog: [Int], letgo: [Int]) async throws {
        struct Result: Decodable { let parked: Int }
        let _: Result = try await request("/week-review/resolve?tz=\(tz)", method: "POST",
                                          body: ["carry": carry, "backlog": backlog,
                                                 "letgo": letgo])
    }

    static func wrapped() async throws -> WrappedResponse {
        try await request("/wrapped?tz=\(tz)")
    }

    static func notes() async throws -> [NoteItem] {
        try await request("/notes")
    }

    static func putNote(date: String, mood: String, text: String, hasPhoto: Bool) async throws {
        struct OK: Decodable { let ok: Bool }
        let _: OK = try await request("/notes/\(date)", method: "PUT",
                                      body: ["mood": mood, "text": text,
                                             "has_photo": hasPhoto])
    }

    static func respread(deadlineId: Int, blocks: [RecoveryBlock]) async throws {
        struct Result: Decodable { let created: Int }
        let _: Result = try await request("/deadlines/\(deadlineId)/respread?tz=\(tz)",
                                          method: "POST",
                                          body: ["blocks": blocks.map {
                                              ["start": $0.start, "minutes": $0.minutes,
                                               "title": $0.title] as [String: Any]
                                          }])
    }

    static func backlog() async throws -> [BacklogItem] {
        try await request("/backlog")
    }

    /// Auto (start nil) → first free slot in the next 7 days; otherwise the
    /// user's picked time. Returns the ISO start it landed on.
    static func scheduleBacklog(id: Int, at start: String? = nil) async throws
        -> (title: String, start: String) {
        struct Result: Decodable { let title: String; let start: String }
        let r: Result = try await request("/backlog/\(id)/schedule?tz=\(tz)",
                                          method: "POST", body: ["start": start as Any])
        return (r.title, r.start)
    }

    static func dropBacklog(id: Int) async throws {
        struct OK: Decodable { let ok: Bool }
        let _: OK = try await request("/backlog/\(id)", method: "DELETE")
    }

    static func prep() async throws -> PrepResponse {
        try await request("/prep?tz=\(tz)")
    }

    static func gapfill() async throws -> GapResponse {
        try await request("/gapfill?tz=\(tz)")
    }

    static func briefing() async throws -> Briefing {
        try await request("/briefing?tz=\(tz)")
    }

    static func addPrep(_ offer: PrepOffer) async throws {
        struct OK: Decodable { let ok: Bool }
        let _: OK = try await request("/prep?tz=\(tz)", method: "POST",
                                      body: ["meeting_title": offer.meetingTitle,
                                             "start": offer.start,
                                             "minutes": offer.minutes])
    }

    static func disruptions() async throws -> DisruptionResponse {
        try await request("/disruptions?tz=\(tz)")
    }

    static func resolveDeleted(ids: [Int], action: String) async throws {
        struct OK: Decodable { let ok: Bool }
        let _: OK = try await request("/disruptions/deleted?tz=\(tz)", method: "POST",
                                      body: ["task_ids": ids, "action": action])
    }

    static func applyReflow(_ moves: [DisruptionMove]) async throws {
        struct Result: Decodable { let moved: Int }
        let _: Result = try await request("/disruptions?tz=\(tz)", method: "POST",
                                          body: ["moves": moves.map {
                                              ["task_id": $0.taskId,
                                               "new_start": $0.newStart,
                                               "new_end": $0.newEnd] as [String: Any]
                                          }])
    }

    static func today() async throws -> DayPayload {
        let payload: DayPayload = try await request("/today?tz=\(tz)")
        WidgetBridge.save(payload)
        return payload
    }

    static func day(_ date: String) async throws -> DayPayload {
        try await request("/days/\(date)?tz=\(tz)")
    }

    static func history() async throws -> [HistoryDay] {
        try await request("/history?days=30&tz=\(tz)")
    }

    static func me() async throws -> Me {
        try await request("/me")
    }

    static func saveProfile(_ profile: Profile) async throws {
        struct OK: Decodable { let ok: Bool }
        let dict = try JSONSerialization.jsonObject(
            with: JSONEncoder.snake.encode(profile)) as? [String: Any]
        let _: OK = try await request("/me/profile", method: "PUT", body: dict)
    }

    static func setStatus(taskId: Int, status: String) async throws {
        struct OK: Decodable { let ok: Bool }
        let _: OK = try await request("/tasks/\(taskId)/status", method: "POST",
                                      body: ["status": status])
    }
}

private extension JSONEncoder {
    static let snake: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()
}
