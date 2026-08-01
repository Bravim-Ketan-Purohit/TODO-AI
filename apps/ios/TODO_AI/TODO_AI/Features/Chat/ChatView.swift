import SwiftUI
import UIKit

extension Notification.Name {
    static let calendarDisconnected = Notification.Name("calendarDisconnected")
}

struct ChatMessage: Identifiable {
    enum Role { case user, ai }
    let id = UUID()
    let role: Role
    var text: String
    var label: String = "TODO_AI"
    var questions: [ChatQuestion] = []
    var plan: [PlanItem] = []
    var approvable = false
    var edits: [EditInfo] = []
    var options: [FixOption] = []
    var confirmDelete = false
    var nudge: Nudge?
    var recap: Recap?
    var rollover: Rollover?      // morning triage (5a)
    var weekReview: WeekReview?  // Sunday review (5b)
    var prep: PrepOffer?         // meeting prep offer (5e)
    var disruption: Disruption?  // calendar-changed reflow (5d)
    var deletedTasks: [DeletedTask] = []  // events removed directly in gcal
    var backlogOffers: [BacklogItem] = []  // backlog drain (morning)
    var staleItems: [BacklogItem] = []     // parked 10+ days — decide now
    var gapOffer: GapOffer?                // micro-gap before the next thing
    var deadlineAlert: DeadlineAlert?      // behind on a goal → re-spread offer
    var notePrompt = false       // evening reflection (7o)
    var pending = false   // offline-held (3i)
    var undoHint = false  // "put it back" (3a)
    var suggestedCategories: [String] = []
}

struct ChatView: View {
    @AppStorage("nudgesOff") private var nudgesOff = false
    @AppStorage("lastRecapDate") private var lastRecapDate = ""
    @AppStorage("lastRolloverDate") private var lastRolloverDate = ""
    @AppStorage("lastReviewWeek") private var lastReviewWeek = ""
    @AppStorage("lastPrepMeeting") private var lastPrepMeeting = ""
    @AppStorage("dismissedDisruption") private var dismissedDisruption = ""
    @AppStorage("lastGapOffer") private var lastGapOffer = ""
    @AppStorage("lastNoteDate") private var lastNoteDate = ""
    @State private var sundayReview: WeekReview?
    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var sending = false
    @State private var offline = false
    @State private var pendingText: String?
    @State private var today: DayPayload?
    @State private var showVoice = false
    @State private var showBacklog = false
    @FocusState private var inputFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .leading) {
            chatBody
            if showBacklog {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { showBacklog = false }
                    .transition(.opacity)
                BacklogDrawer(isOpen: $showBacklog) { confirmation in
                    showBacklog = false
                    messages.append(ChatMessage(role: .ai, text: confirmation))
                    Task { today = try? await API.today() }
                }
                .frame(width: 300)
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .leading))
            }
        }
        .animation(.spring(duration: 0.3), value: showBacklog)
    }

    private var chatBody: some View {
        VStack(spacing: 0) {
            header
            if offline {
                offlineBanner
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if messages.isEmpty { greeting }
                        ForEach(messages) { msg in
                            MessageView(msg: msg, actions: actions)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        if sending {
                            ThinkingView(fixedCount: today?.fixed.count ?? 0)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.spring(duration: 0.35), value: messages.count)
                }
                .scrollDismissesKeyboard(.immediately)
                .simultaneousGesture(TapGesture().onEnded { inputFocused = false })
                .onChange(of: messages.count) {
                    withAnimation { proxy.scrollTo("bottom") }
                }
            }
            inputBar
        }
        .background(DS.pageGradient)
        .fullScreenCover(item: $sundayReview) { review in
            SundayReviewView(review: review) {
                let wc = Calendar(identifier: .iso8601)
                    .dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
                lastReviewWeek = "\(wc.yearForWeekOfYear ?? 0)-W\(wc.weekOfYear ?? 0)"
                sundayReview = nil
                messages.append(ChatMessage(role: .ai,
                    text: "Week closed. See you Monday."))
            }
        }
        .sheet(isPresented: $showVoice) {
            // transcript lands in the composer — nothing sends until the user taps send
            VoiceRantView { transcript in
                input = transcript
                inputFocused = true
            }
        }
        .task { await onAppear() }
        .onChange(of: scenePhase) { _, phase in
            // returning from Google Calendar must re-check for disruptions (5d)
            if phase == .active { Task { await checkDisruptions() } }
        }
        .task(id: offline) {
            // retry loop (3i): every 10s while offline
            while offline, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                if offline { await retryPending() }
            }
        }
    }

    private var actions: MessageActions {
        MessageActions(
            sendText: { send($0) },
            approve: { approve() },
            adjust: { inputFocused = true },
            deleteDecision: { decideDelete($0) },
            replan: { send($0.title) },
            addCategory: { addCategory($0) },
            nudgeAnswer: { answerNudge($0, nudge: $1) },
            recapAnswer: { answerRecap($0, recap: $1) },
            rolloverAnswer: { answerRollover($0, rollover: $1) },
            weekAnswer: { answerWeek($0, review: $1) },
            prepAnswer: { answerPrep($0, prep: $1) },
            reflowAnswer: { answerReflow($0, disruption: $1) },
            deletedAnswer: { answerDeleted($0, tasks: $1) },
            backlogAnswer: { answerBacklog($0, offers: $1) },
            staleAnswer: { answerStale($0, items: $1) },
            gapAnswer: { answerGap($0, gap: $1) },
            deadlineAnswer: { answerDeadline($0, alert: $1) },
            noteSave: { saveNote(mood: $0, text: $1, photo: $2) },
            noteSkip: {
                lastNoteDate = todayYMD
                for i in messages.indices { messages[i].notePrompt = false }
            },
            retry: { Task { await retryPending() } },
            discard: { pendingText = nil; offline = false }
        )
    }

    // ── lifecycle ───────────────────────────────────────────────────

    private func onAppear() async {
        Nudges.ensureWeeklyIfAuthorized()
        // parallel — each is a full tunnel round-trip
        async let todayFetch = API.today()
        async let nudgeFetch = API.nudges()
        today = try? await todayFetch
        if !nudgesOff, let nudge = (try? await nudgeFetch)?.nudge {
            messages.append(ChatMessage(role: .ai, text: nudge.text,
                                        label: "TODO_AI · WEEKLY REVIEW", nudge: nudge))
        }
        // morning rollover (5a): first open of the day — loose ends + backlog drain
        if lastRolloverDate != todayYMD,
           let roll = try? await API.rollover() {
            lastRolloverDate = todayYMD
            if !roll.open.isEmpty {
                let n = roll.open.count
                messages.append(ChatMessage(
                    role: .ai,
                    text: "Yesterday: \(roll.done) of \(roll.total). "
                        + "Carry the \(n == 1 ? "open one" : "\(n) open ones") to today?",
                    label: "TODO_AI · GOOD MORNING", rollover: roll))
            }
            if let offers = roll.backlog, !offers.isEmpty {
                messages.append(ChatMessage(
                    role: .ai,
                    text: "Today has room — from your backlog:",
                    label: "TODO_AI · BACKLOG", backlogOffers: offers))
            }
            if let stale = roll.stale, !stale.isEmpty {
                let names = stale.map(\.title).joined(separator: ", ")
                messages.append(ChatMessage(
                    role: .ai,
                    text: "\(names) \(stale.count == 1 ? "has" : "have") been parked a while. "
                        + "Schedule or let go?",
                    label: "TODO_AI · BACKLOG", staleItems: stale))
            }
            for alert in roll.deadlines ?? [] {
                let h = Double(alert.behindMinutes) / 60
                messages.append(ChatMessage(
                    role: .ai,
                    text: "You're \(String(format: "%.2g", h))h behind on "
                        + "\(alert.title) (due \(alert.dueDate)). I found room to recover:",
                    label: "TODO_AI · DEADLINE", deadlineAlert: alert))
            }
        }
        // disruption reflow (5d): the calendar changed under a synced task
        await checkDisruptions()
        // micro-gap filler: a parked item fits the space before the next thing
        if let gap = (try? await API.gapfill())?.gap {
            let key = "\(gap.item.id)-\(gap.untilTime)"
            if key != lastGapOffer {
                lastGapOffer = key
                messages.append(ChatMessage(
                    role: .ai,
                    text: "\(gap.minutes) min until \(gap.untilTitle) — enough for this:",
                    label: "TODO_AI · GAP", gapOffer: gap))
            }
        }
        // meeting prep (5e): offered, never auto-added; once per meeting
        if let prep = (try? await API.prep())?.prep, prep.meetingStart != lastPrepMeeting {
            lastPrepMeeting = prep.meetingStart
            messages.append(ChatMessage(
                role: .ai,
                text: "\(prep.meetingTitle) at \(hhmm(prep.meetingStart)) — "
                    + "want \(prep.minutes) min of prep right before it?",
                label: "TODO_AI · MEETING PREP", prep: prep))
        }
        // the Sunday Review ritual (7a-7f): Sundays, once per week — full screen
        let weekday = Calendar.current.component(.weekday, from: Date())
        let wc = Calendar(identifier: .iso8601)
            .dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        let weekID = "\(wc.yearForWeekOfYear ?? 0)-W\(wc.weekOfYear ?? 0)"
        if weekday == 1, lastReviewWeek != weekID,
           let review = try? await API.weekReview(), review.total > 0 {
            sundayReview = review
        }
        // evening recap (4e), once per day after 20:00
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 20, lastRecapDate != todayYMD,
           let recap = try? await API.recap(), !recap.open.isEmpty {
            lastRecapDate = todayYMD
            messages.append(ChatMessage(
                role: .ai,
                text: "Day's done — \(recap.done) of \(recap.total). "
                    + "\(recap.open.count) still open:",
                label: "TODO_AI · DAY RECAP", recap: recap))
        }
        // day note prompt (7o): evenings, once, only if today has no note yet
        if hour >= 20, lastNoteDate != todayYMD {
            let existing = (try? await API.notes()) ?? []
            if !existing.contains(where: { $0.date == todayYMD }) {
                messages.append(ChatMessage(role: .ai, text: "How was today?",
                                            label: "TODO_AI", notePrompt: true))
            }
        }
    }

    // ── header / greeting / input ───────────────────────────────────

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                inputFocused = false
                showBacklog = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(DS.mist)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Rectangle()
                .fill(DS.bone)
                .frame(width: 9, height: 9)
                .cornerRadius(2)
                .rotationEffect(.degrees(45))
            Text("TODO_AI").font(DS.inter(15, .semibold)).foregroundStyle(DS.paper)
            Spacer()
            Text(headerDate).font(DS.mono(10)).kerning(0.8).foregroundStyle(DS.ash)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Circle().fill(DS.coral).frame(width: 5, height: 5)
            Text("OFFLINE — RETRYING EVERY 10S")
                .font(DS.mono(9)).kerning(0.7).foregroundStyle(DS.coral)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.coral.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(DS.coral.opacity(0.3), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 20)
    }

    private var greetingWord: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case ..<12: "Good morning."
        case ..<17: "Good afternoon."
        default: "Good evening."
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(greetingWord)
                    .font(DS.inter(24, .medium)).foregroundStyle(DS.paper)
                Text("Brain-dump your day — I'll fit it around what's already on your calendar.")
                    .font(DS.inter(14)).foregroundStyle(DS.fog)
            }
            if let fixed = today?.fixed, !fixed.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("ON YOUR CALENDAR TODAY")
                        .font(DS.mono(9)).kerning(0.9).foregroundStyle(DS.ash)
                    ForEach(fixed) { ev in
                        HStack(spacing: 10) {
                            Text(hhmm(ev.start))
                                .font(DS.mono(10)).foregroundStyle(DS.ash)
                                .frame(width: 36, alignment: .leading)
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(DS.smoke, lineWidth: 0.5)
                                .frame(width: 6, height: 6)
                            Text(ev.title).font(DS.inter(13)).foregroundStyle(DS.mist)
                        }
                    }
                }
                .padding(14)
                .background(DS.cardGradient)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.cardStroke, lineWidth: 1))
            }
            HStack(spacing: 8) {
                ForEach(["Plan my day", "Add one task", "Move something"], id: \.self) { chip in
                    Button {
                        inputFocused = true
                    } label: {
                        Text(chip)
                            .font(DS.inter(12)).foregroundStyle(DS.mist)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Color.white.opacity(0.03))
                            .overlay(Capsule().stroke(DS.graphite, lineWidth: 0.5))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 24)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Plan your day…", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .font(DS.inter(14))
                .foregroundStyle(DS.bone)
                .focused($inputFocused)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Color.white.opacity(0.02))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Button {
                showVoice = true
            } label: {
                Image(systemName: "mic")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DS.mist)
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(DS.graphite, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(sending)
            Button {
                send(input)
            } label: {
                Image(systemName: sending ? "stop.fill" : "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: 0x08090A))
                    .frame(width: 40, height: 40)
                    .background(DS.limeGradient)
                    .clipShape(Circle())
                    .opacity(sending ? 0.35 : 1)
                    .shadow(color: DS.acidLime.opacity(sending ? 0 : 0.35), radius: 9, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(sending || input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
        .overlay(alignment: .top) { DS.hairline.frame(height: 0.5) }
    }

    // ── actions ─────────────────────────────────────────────────────

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !sending else { return }
        messages.append(ChatMessage(role: .user, text: trimmed))
        input = ""
        Task { await deliver(trimmed) }
    }

    private func deliver(_ text: String) async {
        sending = true
        do {
            handle(try await API.chat(message: text))
            offline = false
            pendingText = nil
        } catch let error as URLError where error.code != .cancelled {
            // offline (3i): hold the message, retry loop takes over
            pendingText = text
            offline = true
            if let i = messages.lastIndex(where: { $0.role == .user && $0.text == text }) {
                messages[i].pending = true
            }
            messages.append(ChatMessage(
                role: .ai,
                text: "Can't reach the planner. Your message is saved — I'll send it when you're back online.",
                options: [FixOption(title: "Retry now", subtitle: ""),
                          FixOption(title: "Discard", subtitle: "")]))
        } catch {
            routeError(error)
        }
        sending = false
    }

    private func retryPending() async {
        guard let text = pendingText, !sending else { return }
        sending = true
        do {
            handle(try await API.chat(message: text))
            offline = false
            pendingText = nil
            for i in messages.indices { messages[i].pending = false }
        } catch {
            // stay offline; loop continues
        }
        sending = false
    }

    private func approve() {
        guard !sending else { return }
        for i in messages.indices { messages[i].approvable = false }
        Task {
            sending = true
            do {
                handle(try await API.chat(approve: true))
            } catch {
                routeError(error)
            }
            sending = false
        }
    }

    private func decideDelete(_ decision: String) {
        for i in messages.indices { messages[i].confirmDelete = false }
        Task {
            sending = true
            do {
                handle(try await API.chat(deleteDecision: decision))
            } catch {
                routeError(error)
            }
            sending = false
        }
    }

    private func addCategory(_ name: String) {
        for i in messages.indices {
            messages[i].suggestedCategories.removeAll { $0 == name }
        }
        Task {
            if let me = try? await API.me(), var profile = me.profile {
                var cats = profile.customCategories ?? []
                if !cats.contains(name) { cats.append(name) }
                profile.customCategories = cats
                try? await API.saveProfile(profile)
            }
            messages.append(ChatMessage(role: .ai,
                text: "Added \"\(name.replacingOccurrences(of: "_", with: " "))\" to your categories."))
        }
    }

    private func answerNudge(_ option: String, nudge: Nudge) {
        for i in messages.indices { messages[i].nudge = nil }
        if option.hasPrefix("Yes") {
            Task {
                if let me = try? await API.me(), var profile = me.profile {
                    profile.workout = nudge.suggestedWorkout
                    try? await API.saveProfile(profile)
                }
                messages.append(ChatMessage(role: .ai,
                    text: "Done — workouts default to \(nudge.suggestedWorkout) now."))
            }
        } else if option == "Stop asking" {
            nudgesOff = true
            messages.append(ChatMessage(role: .ai, text: "Okay — no more weekly reviews."))
        } else {
            messages.append(ChatMessage(role: .ai, text: "Keeping it as is."))
        }
    }

    private func answerRecap(_ option: String, recap: Recap) {
        for i in messages.indices { messages[i].recap = nil }
        switch option {
        case "Did them all":
            Task {
                for task in recap.open {
                    try? await API.setStatus(taskId: task.id, status: "completed")
                }
                messages.append(ChatMessage(role: .ai,
                    text: "Nice — \(recap.done + recap.open.count) of \(recap.total). Day closed."))
            }
        case "Missed them":
            Task {
                for task in recap.open {
                    try? await API.setStatus(taskId: task.id, status: "missed")
                }
                messages.append(ChatMessage(role: .ai,
                    text: "Logged. That data tunes where these land next week."))
            }
        default:
            // "X → tomorrow"
            if let first = recap.open.first {
                send("Move \(first.title) to tomorrow")
            }
        }
    }

    private func answerRollover(_ option: String, rollover: Rollover) {
        for i in messages.indices { messages[i].rollover = nil }
        let ids = rollover.open.map(\.id)
        let carry: [Int]
        if option.hasPrefix("Carry") {
            carry = ids
        } else if option.hasPrefix("Just"), let first = ids.first {
            carry = [first]
        } else {
            carry = []
        }
        let drop = ids.filter { !carry.contains($0) }
        Task {
            sending = true
            do {
                try await API.applyRollover(carry: carry, drop: drop)
                today = try? await API.today()
                messages.append(ChatMessage(role: .ai, text: carry.isEmpty
                    ? "Cleared. Fresh slate today."
                    : "Done — \(carry.count) carried into today's free slots. Synced to your calendar."))
            } catch {
                routeError(error)
            }
            sending = false
        }
    }

    private func answerWeek(_ option: String, review: WeekReview) {
        for i in messages.indices { messages[i].weekReview = nil }
        guard option.hasPrefix("Shift"), let insight = review.insight else {
            messages.append(ChatMessage(role: .ai, text: "Keeping it as is."))
            return
        }
        Task {
            if let me = try? await API.me(), var profile = me.profile {
                var windows = profile.categoryWindows ?? [:]
                windows[insight.category] = insight.suggestedWindow
                profile.categoryWindows = windows
                try? await API.saveProfile(profile)
            }
            messages.append(ChatMessage(role: .ai,
                text: "Done — \(insight.category.replacingOccurrences(of: "_", with: " ")) "
                    + "tasks now default to the \(insight.suggestedWindow)."))
        }
    }

    private func disruptionSignature(_ d: Disruption) -> String {
        d.cause + d.moves.map { "\($0.taskId)" }.joined(separator: ",")
    }

    private func checkDisruptions() async {
        guard let resp = try? await API.disruptions() else { return }
        if let d = resp.disruption,
           disruptionSignature(d) != dismissedDisruption,
           !messages.contains(where: { $0.disruption != nil }) {
            messages.append(ChatMessage(
                role: .ai,
                text: "\"\(d.cause)\" landed on your plan — "
                    + "\(d.moves.count + d.unplaced.count) task(s) now collide. Reflow?",
                label: "TODO_AI · CALENDAR CHANGED", disruption: d))
        }
        if let followed = resp.followed, !followed.isEmpty {
            // already synced server-side — just show what was followed
            today = try? await API.today()
            messages.append(ChatMessage(
                role: .ai,
                text: "You moved \(followed.count == 1 ? "an event" : "\(followed.count) events") "
                    + "in Google Calendar — I followed:",
                label: "TODO_AI · CALENDAR CHANGED", edits: followed))
        }
        if let gone = resp.deleted, !gone.isEmpty,
           !messages.contains(where: { !$0.deletedTasks.isEmpty }) {
            let names = gone.map(\.title).joined(separator: ", ")
            messages.append(ChatMessage(
                role: .ai,
                text: "\(names) \(gone.count == 1 ? "was" : "were") deleted from your "
                    + "Google Calendar. Drop \(gone.count == 1 ? "it" : "them") from the plan too?",
                label: "TODO_AI · CALENDAR CHANGED", deletedTasks: gone))
        }
    }

    private func saveNote(mood: String, text: String, photo: UIImage?) {
        lastNoteDate = todayYMD
        for i in messages.indices { messages[i].notePrompt = false }
        if let photo { NotePhotoStore.save(photo, for: todayYMD) }
        Task {
            try? await API.putNote(date: todayYMD, mood: mood, text: text,
                                   hasPhoto: photo != nil)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            messages.append(ChatMessage(role: .ai,
                text: "Noted. It'll be on the day — and in your journal."))
        }
    }

    private func answerGap(_ option: String, gap: GapOffer) {
        for i in messages.indices { messages[i].gapOffer = nil }
        guard option == "Do it now" else {
            messages.append(ChatMessage(role: .ai, text: "Parked — enjoy the breather."))
            return
        }
        Task {
            sending = true
            do {
                let r = try await API.scheduleBacklog(id: gap.item.id, at: gap.start)
                today = try? await API.today()
                messages.append(ChatMessage(role: .ai,
                    text: "\(r.title) starts at \(hhmm(r.start)) — synced. "
                        + "Done before \(gap.untilTitle)."))
            } catch {
                routeError(error)
            }
            sending = false
        }
    }

    private func answerStale(_ option: String, items: [BacklogItem]) {
        for i in messages.indices { messages[i].staleItems = [] }
        Task {
            sending = true
            if option.hasPrefix("Let go") {
                for item in items { try? await API.dropBacklog(id: item.id) }
                messages.append(ChatMessage(role: .ai,
                    text: "Let go. If it mattered, it'll come back on its own."))
            } else {
                var placed: [String] = []
                for item in items {
                    if let r = try? await API.scheduleBacklog(id: item.id) {
                        placed.append("\(r.title) → \(hhmm(r.start))")
                    }
                }
                today = try? await API.today()
                messages.append(ChatMessage(role: .ai, text: placed.isEmpty
                    ? "No room found — still parked. Open ☰ to pick a time yourself."
                    : "Scheduled: \(placed.joined(separator: ", ")). Synced."))
            }
            sending = false
        }
    }

    private func answerDeadline(_ option: String, alert: DeadlineAlert) {
        for i in messages.indices { messages[i].deadlineAlert = nil }
        guard option == "Re-spread" else {
            messages.append(ChatMessage(role: .ai,
                text: "Left alone — I'll check again tomorrow morning."))
            return
        }
        Task {
            sending = true
            do {
                try await API.respread(deadlineId: alert.id, blocks: alert.recovery)
                today = try? await API.today()
                messages.append(ChatMessage(role: .ai,
                    text: "Recovered \(alert.recovery.count) block(s) — synced to your calendar. "
                        + "\(alert.title) is back on track."))
            } catch {
                routeError(error)
            }
            sending = false
        }
    }

    private func answerBacklog(_ option: String, offers: [BacklogItem]) {
        for i in messages.indices { messages[i].backlogOffers = [] }
        guard option != "Keep parked" else {
            messages.append(ChatMessage(role: .ai, text: "Parked — they'll come up again."))
            return
        }
        Task {
            sending = true
            var placed: [String] = []
            for offer in offers {
                if let r = try? await API.scheduleBacklog(id: offer.id) {
                    placed.append("\(r.title) at \(r.start)")
                }
            }
            today = try? await API.today()
            messages.append(ChatMessage(role: .ai, text: placed.isEmpty
                ? "No room left after all — they stay parked."
                : "Scheduled: \(placed.joined(separator: ", ")). Synced."))
            sending = false
        }
    }

    private func answerDeleted(_ option: String, tasks gone: [DeletedTask]) {
        for i in messages.indices { messages[i].deletedTasks = [] }
        let restore = option.hasPrefix("Put")
        Task {
            sending = true
            do {
                try await API.resolveDeleted(ids: gone.map(\.taskId),
                                             action: restore ? "restore" : "remove")
                today = try? await API.today()
                messages.append(ChatMessage(role: .ai, text: restore
                    ? "Restored — back on your calendar at the original times."
                    : "Dropped from the plan. Calendar and app agree again."))
            } catch {
                routeError(error)
            }
            sending = false
        }
    }

    private func answerPrep(_ option: String, prep: PrepOffer) {
        for i in messages.indices { messages[i].prep = nil }
        guard option == "Add prep" else {
            messages.append(ChatMessage(role: .ai, text: "Skipped — no prep block."))
            return
        }
        Task {
            sending = true
            do {
                try await API.addPrep(prep)
                today = try? await API.today()
                messages.append(ChatMessage(role: .ai,
                    text: "Prep — \(prep.meetingTitle) added at \(hhmm(prep.start)). Synced."))
            } catch {
                routeError(error)
            }
            sending = false
        }
    }

    private func answerReflow(_ option: String, disruption: Disruption) {
        for i in messages.indices { messages[i].disruption = nil }
        guard option == "Reflow" else {
            dismissedDisruption = disruptionSignature(disruption)
            messages.append(ChatMessage(role: .ai,
                text: "Left as is — the overlap stays on your calendar."))
            return
        }
        Task {
            sending = true
            do {
                try await API.applyReflow(disruption.moves)
                today = try? await API.today()
                let times = disruption.moves.map { "\($0.title) → \(hhmm($0.newStart))" }
                    .joined(separator: ", ")
                var text = "Reflowed: \(times)."
                if !disruption.unplaced.isEmpty {
                    text += " No room left for: \(disruption.unplaced.joined(separator: ", "))."
                }
                messages.append(ChatMessage(role: .ai, text: text))
            } catch {
                routeError(error)
            }
            sending = false
        }
    }

    private func handle(_ reply: ChatReply) {
        if ["synced", "edited"].contains(reply.type) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        messages.append(ChatMessage(
            role: .ai, text: reply.text,
            questions: reply.questions, plan: reply.plan,
            approvable: reply.type == "proposal",
            edits: reply.edits,
            options: ["overflow", "proposal"].contains(reply.type) ? reply.options : [],
            confirmDelete: reply.type == "confirm_delete",
            undoHint: reply.type == "edited" && reply.edits.contains { !$0.deleted },
            suggestedCategories: reply.suggestedCategories))
        if ["synced", "edited"].contains(reply.type) {
            Task { today = try? await API.today() }
        }
    }

    private func routeError(_ error: Error) {
        if case let APIError.http(401, body) = error, body.contains("reconnect") {
            NotificationCenter.default.post(name: .calendarDisconnected, object: nil)
            return
        }
        messages.append(ChatMessage(role: .ai, text: error.localizedDescription))
    }
}

// ── thinking (3d) ───────────────────────────────────────────────────

private struct ThinkingView: View {
    let fixedCount: Int
    @State private var stage = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TODO_AI").font(DS.mono(9)).kerning(0.9).foregroundStyle(DS.ash)
            VStack(alignment: .leading, spacing: 10) {
                stepRow(done: true, active: false,
                        text: "READ CALENDAR · \(fixedCount) FIXED EVENT\(fixedCount == 1 ? "" : "S")")
                stepRow(done: false, active: stage >= 1, text: "PLACING TASKS AROUND YOUR SCHEDULE…")
                stepRow(done: false, active: stage >= 2, text: "CHECKING CONFLICTS")
            }
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color(hex: [0x383B3F, 0x4B4F55, 0x62666D][i]))
                        .frame(width: 5, height: 5)
                        .opacity(stage % 3 == i ? 1 : 0.5)
                }
            }
            .padding(.top, 2)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.2))
                stage += 1
            }
        }
    }

    private func stepRow(done: Bool, active: Bool, text: String) -> some View {
        HStack(spacing: 9) {
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(DS.fog)
                    .frame(width: 12)
            } else {
                Circle()
                    .fill(active ? DS.acidLime : Color.clear)
                    .overlay(Circle().stroke(active ? Color.clear : DS.smoke, lineWidth: 0.5))
                    .frame(width: 7, height: 7)
                    .frame(width: 12)
            }
            Text(text)
                .font(DS.mono(10)).kerning(0.7)
                .foregroundStyle(done ? DS.fog : (active ? DS.bone : DS.ash))
        }
        .opacity(done || active ? 1 : 0.5)
    }
}

// ── message rendering ───────────────────────────────────────────────

struct MessageActions {
    let sendText: (String) -> Void
    let approve: () -> Void
    let adjust: () -> Void
    let deleteDecision: (String) -> Void
    let replan: (FixOption) -> Void
    let addCategory: (String) -> Void
    let nudgeAnswer: (String, Nudge) -> Void
    let recapAnswer: (String, Recap) -> Void
    let rolloverAnswer: (String, Rollover) -> Void
    let weekAnswer: (String, WeekReview) -> Void
    let prepAnswer: (String, PrepOffer) -> Void
    let reflowAnswer: (String, Disruption) -> Void
    let deletedAnswer: (String, [DeletedTask]) -> Void
    let backlogAnswer: (String, [BacklogItem]) -> Void
    let staleAnswer: (String, [BacklogItem]) -> Void
    let gapAnswer: (String, GapOffer) -> Void
    let deadlineAnswer: (String, DeadlineAlert) -> Void
    let noteSave: (String, String, UIImage?) -> Void
    let noteSkip: () -> Void
    let retry: () -> Void
    let discard: () -> Void
}

private struct MessageView: View {
    let msg: ChatMessage
    let actions: MessageActions
    @State private var copied = false

    var body: some View {
        if msg.role == .user {
            VStack(alignment: .trailing, spacing: 6) {
                Text(msg.text)
                    .font(DS.inter(14)).foregroundStyle(DS.bone)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background {
                        if copied { Color(hex: 0x27A644).opacity(0.35) } else { DS.bubbleGradient }
                    }
                    .clipShape(bubbleShape)
                    .overlay(bubbleShape.stroke(copied ? Color(hex: 0x27A644).opacity(0.6) : DS.bubbleStroke,
                                                lineWidth: 0.5))
                    .opacity(msg.pending ? 0.7 : 1)
                    .onLongPressGesture {
                        UIPasteboard.general.string = msg.text
                        withAnimation(.easeIn(duration: 0.15)) { copied = true }
                        Task {
                            try? await Task.sleep(for: .seconds(1))
                            withAnimation(.easeOut(duration: 0.3)) { copied = false }
                        }
                    }
                if msg.pending {
                    Text("NOT SENT · SAVED")
                        .font(DS.mono(8)).kerning(0.7).foregroundStyle(DS.ash)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 60)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(msg.label).font(DS.mono(9)).kerning(0.9).foregroundStyle(DS.ash)
                Text(msg.text).font(DS.inter(14)).foregroundStyle(DS.mist)

                if !msg.questions.isEmpty {
                    QuestionsBlock(questions: msg.questions, send: actions.sendText)
                }

                if !msg.plan.isEmpty, msg.confirmDelete {
                    DeleteConfirmCard(item: msg.plan[0], decide: actions.deleteDecision)
                } else if !msg.plan.isEmpty {
                    ProposalCard(plan: msg.plan)
                }

                ForEach(msg.edits, id: \.self) { edit in
                    EditCard(edit: edit)
                }
                if msg.undoHint {
                    Text("Undo: \"put it back\"")
                        .font(DS.inter(12)).foregroundStyle(DS.ash)
                }

                if !msg.suggestedCategories.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("New category — save it for next time?")
                            .font(DS.inter(12.5)).foregroundStyle(DS.fog)
                        FlowLayout(spacing: 8) {
                            ForEach(msg.suggestedCategories, id: \.self) { cat in
                                pillButton("Add \"\(cat.replacingOccurrences(of: "_", with: " "))\"",
                                           highlighted: true) { actions.addCategory(cat) }
                            }
                        }
                    }
                }

                if let nudge = msg.nudge {
                    NudgeCard(nudge: nudge, answer: actions.nudgeAnswer)
                }
                if let recap = msg.recap {
                    RecapCard(recap: recap, answer: actions.recapAnswer)
                }
                if let rollover = msg.rollover {
                    RolloverCard(rollover: rollover, answer: actions.rolloverAnswer)
                }
                if let review = msg.weekReview {
                    WeekReviewCard(review: review, answer: actions.weekAnswer)
                }
                if let prep = msg.prep {
                    PrepCard(prep: prep, answer: actions.prepAnswer)
                }
                if let disruption = msg.disruption {
                    DisruptionCard(disruption: disruption, answer: actions.reflowAnswer)
                }
                if !msg.deletedTasks.isEmpty {
                    DeletedCard(tasks: msg.deletedTasks, answer: actions.deletedAnswer)
                }
                if !msg.backlogOffers.isEmpty {
                    BacklogCard(offers: msg.backlogOffers, answer: actions.backlogAnswer)
                }
                if !msg.staleItems.isEmpty {
                    StaleCard(items: msg.staleItems, answer: actions.staleAnswer)
                }
                if let gap = msg.gapOffer {
                    GapCard(gap: gap, answer: actions.gapAnswer)
                }
                if msg.notePrompt {
                    NotePromptCard(onSave: { mood, text, photo in
                        actions.noteSave(mood, text, photo)
                    }, onSkip: { actions.noteSkip() })
                }
                if let alert = msg.deadlineAlert {
                    DeadlineCard(alert: alert, answer: actions.deadlineAnswer)
                }

                if !msg.options.isEmpty, msg.nudge == nil {
                    if msg.options.contains(where: { $0.title == "Retry now" }) {
                        HStack(spacing: 8) {
                            pillButton("Retry now", highlighted: true) { actions.retry() }
                            pillButton("Discard", highlighted: false) { actions.discard() }
                        }
                    } else if msg.approvable {
                        // proposal-side suggestion (e.g. batch the small tasks)
                        FlowLayout(spacing: 8) {
                            ForEach(msg.options, id: \.self) { opt in
                                pillButton(opt.title, highlighted: false) {
                                    actions.sendText(opt.title)
                                }
                            }
                        }
                    } else {
                        OverflowCard(options: msg.options, replan: actions.replan,
                                     adjust: actions.adjust)
                    }
                }

                if msg.approvable {
                    HStack(spacing: 8) {
                        Button(action: actions.approve) {
                            Text(Set(msg.plan.map { $0.start.prefix(10) }).count > 1
                                 ? "Approve week" : "Approve & sync")
                                .font(DS.inter(14, .medium))
                                .foregroundStyle(Color(hex: 0x08090A))
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .background(DS.limeGradient)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        Button(action: actions.adjust) {
                            Text("Adjust")
                                .font(DS.inter(13)).foregroundStyle(DS.mist)
                                .padding(.horizontal, 18).frame(height: 44)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(DS.graphite, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var bubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18,
                               bottomTrailingRadius: 5, topTrailingRadius: 18)
    }
}

func pillButton(_ title: String, highlighted: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title)
            .font(DS.inter(12.5, highlighted ? .medium : .regular))
            .foregroundStyle(highlighted ? DS.paper : DS.fog)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(highlighted ? Color.white.opacity(0.09) : .clear)
            .overlay(Capsule().stroke(highlighted ? Color(hex: 0x43464C) : DS.graphite,
                                      lineWidth: 0.5))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(highlighted ? 0.35 : 0), radius: 6, y: 3)
    }
    .buttonStyle(.plain)
}

/// Batched clarification (user feedback): pick an answer per question, send
/// once — one API call instead of N. A single question still sends on tap.
/// Time questions get a native wheel picker as the third option.
private struct QuestionsBlock: View {
    let questions: [ChatQuestion]
    let send: (String) -> Void
    @State private var picks: [Int: String] = [:]
    @State private var sent = false
    @State private var pickerFor: PickerTarget?

    private struct PickerTarget: Identifiable {
        let id: Int
    }

    private func isTimeQuestion(_ q: ChatQuestion) -> Bool {
        let lower = q.question.lowercased()
        if lower.contains("when") || lower.contains("what time") { return true }
        return q.suggestions.contains { $0.range(of: #"\d{1,2}:\d{2}"#,
                                                 options: .regularExpression) != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(questions.enumerated()), id: \.offset) { i, q in
                VStack(alignment: .leading, spacing: 8) {
                    (Text(questions.count > 1 ? "\(i + 1) · " : "").foregroundStyle(DS.ash)
                        + Text(q.question).foregroundStyle(DS.bone))
                        .font(DS.inter(13.5))
                    FlowLayout(spacing: 8) {
                        ForEach(q.suggestions.prefix(2), id: \.self) { opt in
                            selectPill(opt, selected: picks[i] == opt) { choose(opt, for: i) }
                        }
                        // a custom-picked time shows as its own selected pill
                        if let custom = picks[i], !q.suggestions.contains(custom) {
                            selectPill(custom, selected: true) {}
                        }
                        if isTimeQuestion(q) {
                            selectPill("Pick a time…", selected: false) {
                                pickerFor = PickerTarget(id: i)
                            }
                        }
                    }
                }
            }
            if questions.count > 1 {
                Button {
                    sent = true
                    send(questions.enumerated()
                        .compactMap { i, q in picks[i].map { "\(q.taskTitle): \($0)" } }
                        .joined(separator: ". "))
                } label: {
                    Text("Send answers")
                        .font(DS.inter(14, .medium)).foregroundStyle(Color(hex: 0x08090A))
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(DS.limeGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(sent || picks.count < questions.count)
                .opacity(sent || picks.count < questions.count ? 0.4 : 1)
            }
        }
        .sheet(item: $pickerFor) { target in
            TimePickerSheet { hhmm in
                choose(hhmm, for: target.id)
                pickerFor = nil
            }
        }
    }

    private func choose(_ value: String, for index: Int) {
        if questions.count == 1 {
            send(value)
        } else {
            picks[index] = picks[index] == value ? nil : value
        }
    }
}

/// Native iOS wheel picker for "Pick a time…" (user feedback).
private struct TimePickerSheet: View {
    let onPick: (String) -> Void
    @State private var date = Date()

    var body: some View {
        VStack(spacing: 16) {
            Text("Pick a time")
                .font(DS.inter(15, .medium)).foregroundStyle(DS.paper)
                .padding(.top, 18)
            DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
            Button {
                let f = DateFormatter()
                f.dateFormat = "HH:mm"
                onPick(f.string(from: date))
            } label: {
                Text("Use this time")
                    .font(DS.inter(15, .medium)).foregroundStyle(Color(hex: 0x08090A))
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(DS.limeGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20).padding(.bottom, 16)
        }
        .presentationDetents([.height(340)])
        .presentationBackground(DS.carbon)
    }
}

// ── event row shared by cards ───────────────────────────────────────

private func eventRow(title: String, category: String?, start: String,
                      caption: String, struck: Bool = false, dimmed: Bool = false) -> some View {
    let color = DS.category(category)
    return HStack(spacing: 10) {
        Text(hhmm(start))
            .font(DS.mono(10)).foregroundStyle(DS.ash)
            .frame(width: 36, alignment: .trailing)
            .strikethrough(struck)
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title)
                .font(DS.inter(12, .medium)).foregroundStyle(DS.paper)
                .strikethrough(struck)
            Spacer()
            Text(caption)
                .font(DS.mono(9)).foregroundStyle(Color.white.opacity(0.45))
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(color.opacity(dimmed ? 0.10 : 0.12))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(color.opacity(dimmed ? 0.35 : 0.45), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
    .opacity(dimmed ? 0.45 : 1)
}

// ── edit card (3a / 3b aftermath) ───────────────────────────────────

private struct EditCard: View {
    let edit: EditInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            eventRow(title: edit.title, category: edit.category, start: edit.oldStart,
                     caption: "", struck: true, dimmed: true)
            if let newStart = edit.newStart {
                Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(DS.ash)
                    .padding(.leading, 46)
                eventRow(title: edit.title, category: edit.category, start: newStart,
                         caption: durationCaption)
            }
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .semibold)).foregroundStyle(DS.fog)
                Text(edit.deleted ? "REMOVED FROM GOOGLE CALENDAR" : "SYNCED · GOOGLE CALENDAR")
                    .font(DS.mono(8)).kerning(0.7).foregroundStyle(DS.ash)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(DS.cardGradient)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.cardStroke, lineWidth: 1))
    }

    private var durationCaption: String {
        guard let s = edit.newStart, let e = edit.newEnd else { return "" }
        let mins = minutesSinceMidnight(e) - minutesSinceMidnight(s)
        return mins >= 60 && mins % 60 == 0 ? "\(mins / 60)H" : "\(mins)M"
    }
}

// ── delete confirm (3b) ─────────────────────────────────────────────

private struct DeleteConfirmCard: View {
    let item: PlanItem
    let decide: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                eventRow(title: item.title, category: item.category, start: item.start, caption: "")
                Text("REMOVED FROM GOOGLE CALENDAR · CAN'T UNDO AFTER TODAY")
                    .font(DS.mono(8)).kerning(0.7).foregroundStyle(DS.ash)
            }
            .padding(14)
            .background(DS.cardGradient)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.cardStroke, lineWidth: 1))
            HStack(spacing: 8) {
                Button {
                    decide("confirm")
                } label: {
                    Text("Delete")
                        .font(DS.inter(13, .medium)).foregroundStyle(DS.coral)
                        .padding(.horizontal, 18).frame(height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(DS.coral.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                Button {
                    decide("keep")
                } label: {
                    Text("Keep it")
                        .font(DS.inter(13)).foregroundStyle(DS.mist)
                        .padding(.horizontal, 18).frame(height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(DS.graphite, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// ── overflow (3c) ───────────────────────────────────────────────────

private struct OverflowCard: View {
    let options: [FixOption]
    let replan: (FixOption) -> Void
    let adjust: () -> Void
    @State private var selected = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { i, opt in
                    Button {
                        selected = i
                    } label: {
                        HStack(alignment: .top, spacing: 11) {
                            Circle()
                                .stroke(DS.smoke, lineWidth: 0.5)
                                .frame(width: 16, height: 16)
                                .overlay {
                                    if selected == i {
                                        Circle().fill(DS.acidLime).frame(width: 7, height: 7)
                                    }
                                }
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(opt.title)
                                    .font(DS.inter(13, selected == i ? .medium : .regular))
                                    .foregroundStyle(selected == i ? DS.paper : DS.mist)
                                    .multilineTextAlignment(.leading)
                                if !opt.subtitle.isEmpty {
                                    Text(opt.subtitle).font(DS.inter(11.5)).foregroundStyle(DS.ash)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 13)
                        .overlay(alignment: .bottom) {
                            if i < options.count - 1 { DS.hairline.frame(height: 0.5) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .background(DS.cardGradient)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.cardStroke, lineWidth: 1))

            HStack(spacing: 8) {
                Button {
                    replan(options[selected])
                } label: {
                    Text("Re-plan")
                        .font(DS.inter(14, .medium)).foregroundStyle(Color(hex: 0x08090A))
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(DS.limeGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                Button(action: adjust) {
                    Text("Adjust in chat")
                        .font(DS.inter(13)).foregroundStyle(DS.mist)
                        .padding(.horizontal, 18).frame(height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(DS.graphite, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// ── nudge (3f) ──────────────────────────────────────────────────────

private struct NudgeCard: View {
    let nudge: Nudge
    let answer: (String, Nudge) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text(nudge.gridLabel)
                    .font(DS.mono(9)).kerning(0.9).foregroundStyle(DS.ash)
                HStack(spacing: 10) {
                    ForEach(nudge.week, id: \.self) { day in
                        let green = DS.category("health")
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(day.status == "done" ? green.opacity(0.25) : Color.clear)
                                .overlay(RoundedRectangle(cornerRadius: 5)
                                    .stroke(green.opacity(day.status == "done" ? 0.6 : 0.4),
                                            lineWidth: 0.5))
                                .frame(width: 22, height: 22)
                                .overlay {
                                    if day.status == "done" {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(green)
                                    }
                                }
                                .opacity(day.status == "none" ? 0.2 : (day.status == "done" ? 1 : 0.35))
                            Text(day.day).font(DS.mono(8)).foregroundStyle(Color(hex: 0x4B4F55))
                        }
                    }
                    Rectangle().fill(DS.graphite).frame(width: 0.5, height: 34).padding(.horizontal, 2)
                    Text(nudge.note)
                        .font(DS.inter(11)).foregroundStyle(DS.fog)
                }
            }
            .padding(14)
            .background(DS.cardGradient)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.cardStroke, lineWidth: 1))

            Text(nudge.question).font(DS.inter(14)).foregroundStyle(DS.mist)
            FlowLayout(spacing: 8) {
                ForEach(Array(nudge.options.enumerated()), id: \.offset) { i, opt in
                    pillButton(opt, highlighted: i == 0) { answer(opt, nudge) }
                }
            }
        }
    }
}

// ── recap (4e) ──────────────────────────────────────────────────────

private struct RecapCard: View {
    let recap: Recap
    let answer: (String, Recap) -> Void

    private var options: [String] {
        var opts = ["Did them all", "Missed them"]
        if let first = recap.open.first {
            opts.append("\(first.title) → tomorrow")
        }
        return opts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                ForEach(Array(recap.open.enumerated()), id: \.offset) { i, task in
                    HStack(spacing: 10) {
                        Circle().stroke(DS.smoke, lineWidth: 0.5).frame(width: 16, height: 16)
                        Circle().fill(DS.category(task.category)).frame(width: 6, height: 6)
                        Text(task.title).font(DS.inter(13)).foregroundStyle(DS.bone)
                        Spacer()
                        Text(hhmm(task.start)).font(DS.mono(9)).foregroundStyle(DS.ash)
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) {
                        if i < recap.open.count - 1 { DS.hairline.frame(height: 0.5) }
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(DS.cardGradient)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.cardStroke, lineWidth: 1))

            FlowLayout(spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.offset) { i, opt in
                    pillButton(opt, highlighted: i == 0) { answer(opt, recap) }
                }
            }
            Text("Answers tune where these land next week.")
                .font(DS.inter(12)).foregroundStyle(DS.ash)
        }
    }
}

// ── meeting prep (5e) — offered, never auto-added ───────────────────

private struct PrepCard: View {
    let prep: PrepOffer
    let answer: (String, PrepOffer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                eventRow(title: "Prep — \(prep.meetingTitle)", category: "deep_work",
                         start: prep.start, caption: "\(prep.minutes)M")
                HStack(spacing: 6) {
                    Image(systemName: "person.2")
                        .font(.system(size: 9)).foregroundStyle(DS.ash)
                    Text("\(prep.meetingTitle.uppercased()) · \(prep.attendees) PEOPLE · \(hhmm(prep.meetingStart))")
                        .font(DS.mono(8)).kerning(0.7).foregroundStyle(DS.ash)
                }
            }
            .padding(14)
            .background(DS.cardGradient)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.cardStroke, lineWidth: 1))

            HStack(spacing: 8) {
                pillButton("Add prep", highlighted: true) { answer("Add prep", prep) }
                pillButton("Skip", highlighted: false) { answer("Skip", prep) }
            }
        }
    }
}

// ── disruption reflow (5d) — conflict caught before you saw it ──────

private struct DisruptionCard: View {
    let disruption: Disruption
    let answer: (String, Disruption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(hhmm(disruption.moves.first?.oldStart ?? ""))
                        .font(DS.mono(10)).foregroundStyle(DS.ash)
                        .frame(width: 36, alignment: .trailing)
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(DS.coral.opacity(0.7), lineWidth: 0.5)
                            .frame(width: 6, height: 6)
                        Text(disruption.cause).font(DS.inter(12, .medium)).foregroundStyle(DS.paper)
                        Spacer()
                        Text("NEW · FIXED").font(DS.mono(8)).kerning(0.7).foregroundStyle(DS.coral)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(DS.coral.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .stroke(DS.coral.opacity(0.4), lineWidth: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                ForEach(disruption.moves, id: \.self) { move in
                    eventRow(title: move.title, category: move.category,
                             start: move.oldStart, caption: "", struck: true, dimmed: true)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(DS.ash)
                        .padding(.leading, 46)
                    eventRow(title: move.title, category: move.category,
                             start: move.newStart, caption: hhmm(move.newEnd))
                }
                if !disruption.unplaced.isEmpty {
                    Text("NO ROOM TODAY: \(disruption.unplaced.joined(separator: ", ").uppercased())")
                        .font(DS.mono(8)).kerning(0.7).foregroundStyle(DS.coral.opacity(0.8))
                }
            }
            .padding(14)
            .background(DS.cardGradient)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.cardStroke, lineWidth: 1))

            HStack(spacing: 8) {
                pillButton("Reflow", highlighted: true) { answer("Reflow", disruption) }
                pillButton("Leave it", highlighted: false) { answer("Leave it", disruption) }
            }
            Text("Nothing moves until you say so.")
                .font(DS.inter(12)).foregroundStyle(DS.ash)
        }
    }
}

// ── living deadline (engine): behind → recovery blocks ──────────────

private struct DeadlineCard: View {
    let alert: DeadlineAlert
    let answer: (String, DeadlineAlert) -> Void

    var body: some View {
        let color = DS.category(alert.category)
        let covered = alert.doneMinutes + alert.bookedMinutes
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 7) {
                        Circle().fill(color).frame(width: 6, height: 6)
                        Text(alert.title).font(DS.inter(13, .medium)).foregroundStyle(DS.paper)
                    }
                    Spacer()
                    Text("DUE \(alert.dueDate.suffix(5))")
                        .font(DS.mono(9)).kerning(0.7).foregroundStyle(DS.ash)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.05))
                        Capsule().fill(color.opacity(0.8))
                            .frame(width: geo.size.width
                                   * CGFloat(min(covered, alert.targetMinutes))
                                   / CGFloat(max(alert.targetMinutes, 1)))
                    }
                }
                .frame(height: 5)
                Text("\(covered / 60)H OF \(alert.targetMinutes / 60)H COVERED · "
                     + "\(alert.behindMinutes) MIN BEHIND")
                    .font(DS.mono(9)).kerning(0.7).foregroundStyle(DS.coral.opacity(0.85))
                ForEach(alert.recovery, id: \.self) { block in
                    eventRow(title: block.title, category: alert.category,
                             start: block.start, caption: "\(block.minutes)M")
                }
            }
            .padding(14)
            .background(DS.cardGradient)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.cardStroke, lineWidth: 1))

            HStack(spacing: 8) {
                pillButton("Re-spread", highlighted: true) { answer("Re-spread", alert) }
                pillButton("Leave it", highlighted: false) { answer("Leave it", alert) }
            }
        }
    }
}

// ── backlog drain (engine) ──────────────────────────────────────────

private struct BacklogCard: View {
    let offers: [BacklogItem]
    let answer: (String, [BacklogItem]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                ForEach(Array(offers.enumerated()), id: \.offset) { i, item in
                    HStack(spacing: 10) {
                        Circle().fill(DS.category(item.category)).frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(DS.inter(13, .medium)).foregroundStyle(DS.paper)
                            Text("PARKED · \(item.durationMinutes) MIN"
                                 + (item.fitsAt.map { " · FITS AT \($0)" } ?? ""))
                                .font(DS.mono(8)).kerning(0.6).foregroundStyle(DS.ash)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) {
                        if i < offers.count - 1 { DS.hairline.frame(height: 0.5) }
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(DS.cardGradient)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.cardStroke, lineWidth: 1))

            HStack(spacing: 8) {
                pillButton(offers.count == 1 ? "Schedule it" : "Schedule them",
                           highlighted: true) { answer("Schedule", offers) }
                pillButton("Keep parked", highlighted: false) { answer("Keep parked", offers) }
            }
            Text("Parked things only surface when a day has room.")
                .font(DS.inter(12)).foregroundStyle(DS.ash)
        }
    }
}

// ── micro-gap filler ────────────────────────────────────────────────

private struct GapCard: View {
    let gap: GapOffer
    let answer: (String, GapOffer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(gap.minutes) MIN FREE · UNTIL \(gap.untilTitle.uppercased()) \(gap.untilTime)")
                    .font(DS.mono(8)).kerning(0.7).foregroundStyle(DS.ash)
                eventRow(title: gap.item.title, category: gap.item.category,
                         start: gap.start, caption: "\(gap.item.durationMinutes)M")
            }
            .padding(14)
            .background(DS.cardGradient)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.cardStroke, lineWidth: 1))

            HStack(spacing: 8) {
                pillButton("Do it now", highlighted: true) { answer("Do it now", gap) }
                pillButton("Keep parked", highlighted: false) { answer("Keep parked", gap) }
            }
        }
    }
}

// ── stale backlog (anti-rot): decide, don't drift ───────────────────

private struct StaleCard: View {
    let items: [BacklogItem]
    let answer: (String, [BacklogItem]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(spacing: 10) {
                        Circle().fill(DS.category(item.category)).frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(DS.inter(13, .medium)).foregroundStyle(DS.paper)
                            Text("PARKED \(item.daysParked ?? 0) DAYS · \(item.durationMinutes) MIN")
                                .font(DS.mono(8)).kerning(0.6)
                                .foregroundStyle(DS.coral.opacity(0.8))
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) {
                        if i < items.count - 1 { DS.hairline.frame(height: 0.5) }
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(DS.cardGradient)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.cardStroke, lineWidth: 1))

            HStack(spacing: 8) {
                pillButton("Schedule now", highlighted: true) { answer("Schedule now", items) }
                pillButton("Let go", highlighted: false) { answer("Let go", items) }
            }
            Text("Or open ☰ to pick an exact time.")
                .font(DS.inter(12)).foregroundStyle(DS.ash)
        }
    }
}

// ── deleted-in-gcal reconciliation ──────────────────────────────────

private struct DeletedCard: View {
    let tasks: [DeletedTask]
    let answer: (String, [DeletedTask]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(tasks) { task in
                    eventRow(title: task.title, category: task.category,
                             start: task.start, caption: "GONE", struck: true, dimmed: true)
                }
                Text("DELETED IN GOOGLE CALENDAR · STILL IN YOUR PLAN")
                    .font(DS.mono(8)).kerning(0.7).foregroundStyle(DS.ash)
            }
            .padding(14)
            .background(DS.cardGradient)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.cardStroke, lineWidth: 1))

            HStack(spacing: 8) {
                pillButton(tasks.count == 1 ? "Drop it" : "Drop them", highlighted: true) {
                    answer("Drop", tasks)
                }
                pillButton(tasks.count == 1 ? "Put it back" : "Put them back", highlighted: false) {
                    answer("Put back", tasks)
                }
            }
        }
    }
}

// ── morning rollover (5a) ───────────────────────────────────────────

private struct RolloverCard: View {
    let rollover: Rollover
    let answer: (String, Rollover) -> Void

    private var options: [String] {
        switch rollover.open.count {
        case 1: return ["Carry it", "Drop it"]
        case 2: return ["Carry both", "Just \(shortTitle(rollover.open[0].title))", "Drop them"]
        default: return ["Carry all", "Drop them"]
        }
    }

    private func shortTitle(_ t: String) -> String {
        t.split(separator: " ").prefix(2).joined(separator: " ").lowercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                ForEach(Array(rollover.open.enumerated()), id: \.offset) { i, task in
                    HStack(spacing: 10) {
                        Circle().fill(DS.category(task.category)).frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(task.title).font(DS.inter(13, .medium)).foregroundStyle(DS.paper)
                            Text("MISSED YESTERDAY \(task.missedTime)"
                                 + (task.fitsToday.map { " · FITS TODAY \($0)" } ?? " · NO ROOM TODAY"))
                                .font(DS.mono(8)).kerning(0.6)
                                .foregroundStyle(task.fitsToday == nil ? DS.coral.opacity(0.8) : DS.ash)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) {
                        if i < rollover.open.count - 1 { DS.hairline.frame(height: 0.5) }
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(DS.cardGradient)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.cardStroke, lineWidth: 1))

            FlowLayout(spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.offset) { i, opt in
                    pillButton(opt, highlighted: i == 0) { answer(opt, rollover) }
                }
            }
            Text("Carried tasks land in today's free slots.")
                .font(DS.inter(12)).foregroundStyle(DS.ash)
        }
    }
}

// ── week review (5b) ────────────────────────────────────────────────

private struct WeekReviewCard: View {
    let review: WeekReview
    let answer: (String, WeekReview) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(review.categories, id: \.self) { cat in
                    let color = DS.category(cat.category)
                    HStack(spacing: 10) {
                        Circle().fill(color).frame(width: 6, height: 6)
                        Text(cat.category.replacingOccurrences(of: "_", with: " "))
                            .font(DS.inter(12)).foregroundStyle(DS.mist)
                            .frame(width: 84, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.05))
                                Capsule().fill(color.opacity(0.8))
                                    .frame(width: geo.size.width * CGFloat(cat.pct) / 100)
                            }
                        }
                        .frame(height: 5)
                        // budgeted categories score against the target, not just %
                        if let budget = cat.budgetHours {
                            Text("\(String(format: "%.2g", cat.doneHours ?? 0))/\(String(format: "%.2g", budget))H")
                                .font(DS.mono(10))
                                .foregroundStyle((cat.doneHours ?? 0) >= budget ? DS.fog : DS.coral.opacity(0.85))
                                .frame(width: 52, alignment: .trailing)
                        } else {
                            Text("\(cat.pct)%")
                                .font(DS.mono(10)).foregroundStyle(DS.fog)
                                .frame(width: 34, alignment: .trailing)
                        }
                    }
                }
                if let slip = review.avgSlipMin, slip != 0 {
                    HStack {
                        Text("PLANNED VS ACTUAL")
                        Spacer()
                        Text("\(slip > 0 ? "+" : "")\(slip) MIN AVG SLIP")
                    }
                    .font(DS.mono(9)).kerning(0.8).foregroundStyle(DS.ash)
                    .padding(.top, 4)
                }
            }
            .padding(14)
            .background(DS.cardGradient)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.cardStroke, lineWidth: 1))

            if let insight = review.insight {
                Text(insight.text).font(DS.inter(13.5)).foregroundStyle(DS.bone)
                FlowLayout(spacing: 8) {
                    ForEach(Array(insight.options.enumerated()), id: \.offset) { i, opt in
                        pillButton(opt, highlighted: i == 0) { answer(opt, review) }
                    }
                }
            }
        }
    }
}

// ── proposal card (1h/1m) ───────────────────────────────────────────

private struct ProposalCard: View {
    let plan: [PlanItem]

    // multi-day plan (5c): distinct YYYY-MM-DD prefixes in the proposal
    private var days: [String] {
        Array(Set(plan.map { String($0.start.prefix(10)) })).sorted()
    }

    private func plannedMins(_ day: String) -> Int {
        plan.filter { !$0.fixed && $0.start.hasPrefix(day) }
            .map { minutesSinceMidnight($0.end) - minutesSinceMidnight($0.start) }
            .reduce(0, +)
    }

    private func hoursLabel(_ mins: Int) -> String {
        mins % 60 == 0 ? "\(mins / 60)H" : String(format: "%.1fH", Double(mins) / 60)
    }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func dayLabel(_ day: String) -> String {
        guard let d = Self.dayFmt.date(from: day) else { return day }
        return d.formatted(.dateTime.weekday(.abbreviated)).uppercased()
    }

    private func dayColor(_ day: String) -> Color {
        DS.category(plan.first { !$0.fixed && $0.start.hasPrefix(day) }?.category)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if days.count > 1 {
                weekHeader
                weekStrip.padding(.vertical, 6)
                Text("OUTLINED = EXISTING FIXED EVENTS")
                    .font(DS.mono(8)).kerning(0.7).foregroundStyle(DS.ash)
                    .padding(.bottom, 4)
            } else {
                HStack {
                    Text("TODAY · \(headerDate)")
                    Spacer()
                    Text("\(plan.count) EVENTS")
                }
                .font(DS.mono(9)).kerning(0.9).foregroundStyle(DS.ash)
                .padding(.bottom, 4)
            }

            ForEach(days, id: \.self) { day in
                if days.count > 1 {
                    Text(dayLabel(day))
                        .font(DS.mono(9)).kerning(0.9).foregroundStyle(DS.fog)
                        .padding(.top, 6)
                }
                ForEach(plan.filter { $0.start.hasPrefix(day) }) { item in
                    row(item)
                }
            }
        }
        .padding(14)
        .background(DS.cardGradient)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.cardStroke, lineWidth: 1))
    }

    private var weekHeader: some View {
        let total = days.map(plannedMins).reduce(0, +)
        let cat = plan.first { !$0.fixed }?.category ?? ""
        return HStack {
            Text("THIS WEEK")
            Spacer()
            Text("\(cat.replacingOccurrences(of: "_", with: " ").uppercased()) · \(hoursLabel(total)) TOTAL")
                .foregroundStyle(dayColor(days.first ?? ""))
        }
        .font(DS.mono(9)).kerning(0.9).foregroundStyle(DS.ash)
    }

    private var weekStrip: some View {
        let maxMins = max(days.map(plannedMins).max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 10) {
            ForEach(days, id: \.self) { day in
                let mins = plannedMins(day)
                let color = dayColor(day)
                VStack(spacing: 4) {
                    if plan.contains(where: { $0.fixed && $0.start.hasPrefix(day) }) {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(DS.smoke, lineWidth: 0.5)
                            .frame(height: 10)
                    }
                    if mins > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color.opacity(0.5))
                            .overlay(RoundedRectangle(cornerRadius: 4)
                                .stroke(color.opacity(0.8), lineWidth: 0.5))
                            .frame(height: 14 + 40 * CGFloat(mins) / CGFloat(maxMins))
                    }
                    Text(dayLabel(day)).font(DS.mono(8)).foregroundStyle(Color(hex: 0x62666D))
                    Text(mins > 0 ? hoursLabel(mins) : "—")
                        .font(DS.mono(8)).foregroundStyle(DS.ash)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func row(_ item: PlanItem) -> some View {
        let color = DS.category(item.category)
        return HStack(spacing: 10) {
                    Text(hhmm(item.start))
                        .font(DS.mono(10)).foregroundStyle(DS.ash)
                        .frame(width: 36, alignment: .trailing)
                    HStack(spacing: 7) {
                        if item.fixed {
                            RoundedRectangle(cornerRadius: 2).stroke(DS.smoke, lineWidth: 0.5)
                                .frame(width: 6, height: 6)
                            Text(item.title).font(DS.inter(11)).foregroundStyle(DS.fog)
                                .lineLimit(1)
                            Spacer()
                            Text("FIXED").font(DS.mono(8)).kerning(0.7)
                                .foregroundStyle(Color(hex: 0x4B4F55))
                                .layoutPriority(1)
                        } else {
                            Circle().fill(color).frame(width: 6, height: 6)
                            Text(item.title).font(DS.inter(12, .medium)).foregroundStyle(DS.paper)
                                .lineLimit(1)
                            Spacer()
                            Text("\(hhmm(item.start))–\(hhmm(item.end))")
                                .font(DS.mono(9)).foregroundStyle(Color.white.opacity(0.45))
                                .layoutPriority(1)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: item.fixed ? 24 : 32)
                    .background(item.fixed ? Color.clear : color.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .stroke(item.fixed ? Color(hex: 0x2C2E33) : color.opacity(0.45), lineWidth: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }
}

/// Minimal wrapping HStack for suggestion pills.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, frame) in layout(proposal: proposal, subviews: subviews).frames.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                              proposal: ProposedViewSize(frame.size))
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight), frames)
    }
}
