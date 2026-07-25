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
    var pending = false   // offline-held (3i)
    var undoHint = false  // "put it back" (3a)
    var suggestedCategories: [String] = []
}

struct ChatView: View {
    @AppStorage("nudgesOff") private var nudgesOff = false
    @AppStorage("lastRecapDate") private var lastRecapDate = ""
    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var sending = false
    @State private var offline = false
    @State private var pendingText: String?
    @State private var today: DayPayload?
    @FocusState private var inputFocused: Bool

    var body: some View {
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
                        }
                        if sending {
                            ThinkingView(fixedCount: today?.fixed.count ?? 0)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.immediately)
                .simultaneousGesture(TapGesture().onEnded { inputFocused = false })
                .onChange(of: messages.count) {
                    withAnimation { proxy.scrollTo("bottom") }
                }
            }
            inputBar
        }
        .background(DS.void)
        .task { await onAppear() }
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
            retry: { Task { await retryPending() } },
            discard: { pendingText = nil; offline = false }
        )
    }

    // ── lifecycle ───────────────────────────────────────────────────

    private func onAppear() async {
        // parallel — each is a full tunnel round-trip
        async let todayFetch = API.today()
        async let nudgeFetch = API.nudges()
        today = try? await todayFetch
        if !nudgesOff, let nudge = (try? await nudgeFetch)?.nudge {
            messages.append(ChatMessage(role: .ai, text: nudge.text,
                                        label: "TODO_AI · WEEKLY REVIEW", nudge: nudge))
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
    }

    // ── header / greeting / input ───────────────────────────────────

    private var header: some View {
        HStack(spacing: 8) {
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
                .background(DS.carbon)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.graphite, lineWidth: 1))
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
                send(input)
            } label: {
                Image(systemName: sending ? "stop.fill" : "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: 0x08090A))
                    .frame(width: 40, height: 40)
                    .background(DS.acidLime.opacity(sending ? 0.35 : 1))
                    .clipShape(Circle())
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

    private func handle(_ reply: ChatReply) {
        messages.append(ChatMessage(
            role: .ai, text: reply.text,
            questions: reply.questions, plan: reply.plan,
            approvable: reply.type == "proposal",
            edits: reply.edits,
            options: reply.type == "overflow" ? reply.options : [],
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
                    .background(copied ? Color(hex: 0x27A644).opacity(0.35) : DS.obsidian)
                    .clipShape(bubbleShape)
                    .overlay(bubbleShape.stroke(copied ? Color(hex: 0x27A644).opacity(0.6) : DS.graphite,
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

                if !msg.options.isEmpty, msg.nudge == nil {
                    if msg.options.contains(where: { $0.title == "Retry now" }) {
                        HStack(spacing: 8) {
                            pillButton("Retry now", highlighted: true) { actions.retry() }
                            pillButton("Discard", highlighted: false) { actions.discard() }
                        }
                    } else {
                        OverflowCard(options: msg.options, replan: actions.replan,
                                     adjust: actions.adjust)
                    }
                }

                if msg.approvable {
                    HStack(spacing: 8) {
                        Button(action: actions.approve) {
                            Text("Approve & sync")
                                .font(DS.inter(14, .medium))
                                .foregroundStyle(Color(hex: 0x08090A))
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .background(DS.acidLime)
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
        UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14,
                               bottomTrailingRadius: 4, topTrailingRadius: 14)
    }
}

func pillButton(_ title: String, highlighted: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title)
            .font(DS.inter(12.5, highlighted ? .medium : .regular))
            .foregroundStyle(highlighted ? DS.paper : DS.fog)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(highlighted ? Color.white.opacity(0.06) : .clear)
            .overlay(Capsule().stroke(highlighted ? DS.smoke : DS.graphite, lineWidth: 0.5))
            .clipShape(Capsule())
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
                        .background(DS.acidLime)
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
                    .background(DS.acidLime)
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
        .background(DS.carbon)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.graphite, lineWidth: 1))
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
            .background(DS.carbon)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.graphite, lineWidth: 1))
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
            .background(DS.carbon)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.graphite, lineWidth: 1))

            HStack(spacing: 8) {
                Button {
                    replan(options[selected])
                } label: {
                    Text("Re-plan")
                        .font(DS.inter(14, .medium)).foregroundStyle(Color(hex: 0x08090A))
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(DS.acidLime)
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
            .background(DS.carbon)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.graphite, lineWidth: 1))

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
            .background(DS.carbon)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.graphite, lineWidth: 1))

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

// ── proposal card (1h/1m) ───────────────────────────────────────────

private struct ProposalCard: View {
    let plan: [PlanItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TODAY · \(headerDate)")
                Spacer()
                Text("\(plan.count) EVENTS")
            }
            .font(DS.mono(9)).kerning(0.9).foregroundStyle(DS.ash)
            .padding(.bottom, 4)

            ForEach(plan) { item in
                let color = DS.category(item.category)
                HStack(spacing: 10) {
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
        .padding(14)
        .background(DS.carbon)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.graphite, lineWidth: 1))
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
