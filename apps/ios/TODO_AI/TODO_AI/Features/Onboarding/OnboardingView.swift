import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    // 0 welcome · 1 T&C · 2 connect · 3 role · 4 rhythm · 5 role pack · 6 notifications
    @State private var step = 0
    @State private var denied = false  // design 4b: recoverable OAuth failure
    @State private var role: String?
    @State private var wake = "7:00"
    @State private var sleep = "23:00"
    @State private var peak = "Morning"
    @State private var lunch = "12:30"
    @State private var workout = "Morning"
    // developer pack (1e)
    @State private var deepWorkBlock = "90 min"
    @State private var meetingDays: Set<String> = ["Tue", "Thu"]
    @State private var codeReview = "After lunch"
    @State private var onCall = false
    // student pack (2a)
    @State private var studyBlock = "45 min"
    @State private var studyTime = "Evening"
    @State private var breaks = "Short & often"
    @State private var deadlineBuffer = "2 days"
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if denied {
                        deniedView
                    } else {
                        switch step {
                        case 0: welcome
                        case 1: terms
                        case 2: connect
                        case 3: rolePicker
                        case 4: rhythm
                        case 5: role == "student" ? AnyView(studentPack) : AnyView(developerPack)
                        default: notifications
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.top, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            bottomButtons
        }
        .background(DS.void.ignoresSafeArea())
    }

    // ── 0 · welcome (1a) ────────────────────────────────────────────

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 9) {
                Rectangle().fill(DS.bone).frame(width: 10, height: 10)
                    .cornerRadius(2).rotationEffect(.degrees(45))
                Text("TODO_AI").font(DS.inter(15, .semibold)).foregroundStyle(DS.paper)
            }
            .padding(.top, 40)
            Text("Type your day.\nIt schedules itself.")
                .font(DS.inter(34, .medium)).foregroundStyle(DS.paper)
                .lineSpacing(2)
            Text("Any message becomes a scheduled, color-coded event on your Google Calendar.")
                .font(DS.inter(15)).foregroundStyle(DS.fog)
            VStack(spacing: 0) {
                promiseRow("01", "Reads your calendar first — never double-books")
                promiseRow("02", "Asks before it guesses a time")
                promiseRow("03", "Nothing is written until you approve")
                DS.hairline.frame(height: 0.5)
            }
            .padding(.top, 8)
        }
    }

    private func promiseRow(_ num: String, _ text: String) -> some View {
        VStack(spacing: 0) {
            DS.hairline.frame(height: 0.5)
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(num).font(DS.mono(10)).foregroundStyle(DS.ash)
                Text(text).font(DS.inter(13)).foregroundStyle(DS.mist)
                Spacer()
            }
            .padding(.vertical, 13)
        }
    }

    // ── 1 · T&C consent (4c) ────────────────────────────────────────

    private var terms: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepLabel("TERMS · PLAIN ENGLISH")
            Text("We keep the data,\nnot the person")
                .font(DS.inter(24, .medium)).foregroundStyle(DS.paper)
            TermsSections()
        }
    }

    // ── 2 · connect (1b) + denied (4b) ──────────────────────────────

    private var connect: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepLabel("01 / 04")
            Text("Connect Google Calendar")
                .font(DS.inter(24, .medium)).foregroundStyle(DS.paper)
            Text("One account. The calendar you connect is the one this app controls.")
                .font(DS.inter(14)).foregroundStyle(DS.fog)

            HStack(spacing: 14) {
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .light)).foregroundStyle(DS.mist)
                    .frame(width: 40, height: 40)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(DS.smoke, lineWidth: 0.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Google Calendar").font(DS.inter(14, .medium)).foregroundStyle(DS.bone)
                    Text("Read & write · this account only").font(DS.inter(11)).foregroundStyle(DS.ash)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.cardGradient)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.cardStroke, lineWidth: 1))

            VStack(alignment: .leading, spacing: 10) {
                bullet("Existing events are read, never overwritten")
                bullet("Only events this app creates can be edited by chat")
                bullet("Times use this device's time zone")
            }
            .padding(.horizontal, 4)
        }
    }

    private var deniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 24, weight: .light)).foregroundStyle(DS.ash)
                .frame(width: 52, height: 52)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.cardStroke, lineWidth: 1))
                .padding(.bottom, 4)
            Text("ERR · ACCESS_DENIED")
                .font(DS.mono(9)).kerning(0.9).foregroundStyle(DS.coral)
            Text("Calendar access declined")
                .font(DS.inter(24, .medium)).foregroundStyle(DS.paper)
            Text("TODO_AI can't plan without reading your calendar. It only ever edits events it creates — yours stay untouched.")
                .font(DS.inter(14)).foregroundStyle(DS.fog)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120).padding(.horizontal, 12)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("—").foregroundStyle(Color(hex: 0x383B3F))
            Text(text).foregroundStyle(DS.fog)
        }
        .font(DS.inter(12.5))
    }

    // ── 3 · role picker (1c) ────────────────────────────────────────

    private var rolePicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepLabel("02 / 04")
            Text("How do you plan?").font(DS.inter(24, .medium)).foregroundStyle(DS.paper)
            Text("Picks the questions that follow. Change it anytime.")
                .font(DS.inter(14)).foregroundStyle(DS.fog)
            roleCard("developer", "Developer",
                     "Deep-work blocks, meeting-heavy days, on-call, code review.")
            roleCard("student", "Student",
                     "Class schedule from chat, study windows, deadlines.")
        }
    }

    private func roleCard(_ key: String, _ title: String, _ subtitle: String) -> some View {
        let selected = role == key
        return Button {
            role = key
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title).font(DS.inter(15, .medium))
                        .foregroundStyle(selected ? DS.paper : DS.mist)
                    Spacer()
                    Circle()
                        .fill(selected ? DS.acidLime : Color.clear)
                        .overlay(Circle().stroke(selected ? DS.acidLime : DS.smoke, lineWidth: 0.5))
                        .frame(width: 8, height: 8)
                }
                Text(subtitle).font(DS.inter(12.5)).foregroundStyle(DS.fog)
            }
            .padding(.horizontal, 16).padding(.vertical, 18)
            .background(selected ? Color.white.opacity(0.02) : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? DS.acidLime.opacity(0.55) : DS.graphite, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // ── 4 · rhythm (1d) ─────────────────────────────────────────────

    private var rhythm: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepLabel("03 / 04")
            Text("Your rhythm").font(DS.inter(24, .medium)).foregroundStyle(DS.paper)
            Text("Anchors the scheduler plans around.")
                .font(DS.inter(14)).foregroundStyle(DS.fog)
            PillGroup(label: "WAKE", options: ["6:00", "6:30", "7:00", "7:30"], selection: $wake)
            PillGroup(label: "SLEEP", options: ["22:30", "23:00", "23:30"], selection: $sleep)
            PillGroup(label: "ENERGY PEAK", options: ["Morning", "Afternoon", "Evening"], selection: $peak)
            PillGroup(label: "LUNCH", options: ["12:00", "12:30", "13:00"], selection: $lunch)
            PillGroup(label: "WORKOUT", options: ["Morning", "Evening", "Varies"], selection: $workout)
        }
    }

    // ── 5 · role packs (1e / 2a) ────────────────────────────────────

    private var developerPack: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepLabel("04 / 04")
            Text("Developer setup").font(DS.inter(24, .medium)).foregroundStyle(DS.paper)
            Text("Deep work goes in your peak. Admin goes in the dips.")
                .font(DS.inter(14)).foregroundStyle(DS.fog)
            PillGroup(label: "DEEP-WORK BLOCK", options: ["60 min", "90 min", "120 min"],
                      selection: $deepWorkBlock)
            MultiPillGroup(label: "MEETING-HEAVY DAYS",
                           options: ["Mon", "Tue", "Wed", "Thu", "Fri"], selection: $meetingDays)
            PillGroup(label: "CODE REVIEW", options: ["Morning", "After lunch", "End of day"],
                      selection: $codeReview)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("On-call rotation").font(DS.inter(13.5)).foregroundStyle(DS.bone)
                    Text("Keeps on-call weeks lighter").font(DS.inter(11)).foregroundStyle(DS.ash)
                }
                Spacer()
                Toggle("", isOn: $onCall).labelsHidden().tint(DS.smoke)
            }
            .padding(.vertical, 14)
            .overlay(alignment: .top) { DS.hairline.frame(height: 0.5) }
            .overlay(alignment: .bottom) { DS.hairline.frame(height: 0.5) }
        }
    }

    private var studentPack: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepLabel("04 / 04")
            Text("Student setup").font(DS.inter(24, .medium)).foregroundStyle(DS.paper)
            Text("Study goes in your peak. Classes stay fixed.")
                .font(DS.inter(14)).foregroundStyle(DS.fog)
            PillGroup(label: "STUDY BLOCK", options: ["30 min", "45 min", "90 min"],
                      selection: $studyBlock)
            PillGroup(label: "BEST STUDY TIME", options: ["Morning", "Afternoon", "Evening"],
                      selection: $studyTime)
            PillGroup(label: "BREAKS", options: ["Short & often", "Long & few"], selection: $breaks)
            PillGroup(label: "DEADLINE BUFFER", options: ["Night before", "2 days", "A week"],
                      selection: $deadlineBuffer)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 15, weight: .light)).foregroundStyle(DS.fog)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Class schedule? Just type it.")
                        .font(DS.inter(13, .medium)).foregroundStyle(DS.bone)
                    Text("One chat message creates the whole semester as fixed anchors.")
                        .font(DS.inter(12)).foregroundStyle(DS.fog)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.cardGradient)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.cardStroke, lineWidth: 1))
        }
    }

    // ── 6 · notifications (4d) ──────────────────────────────────────

    private var notifications: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepLabel("ONE LAST THING")
            Text("Two nudges a day").font(DS.inter(24, .medium)).foregroundStyle(DS.paper)
            Text("No streaks, no badges, no spam. Just these:")
                .font(DS.inter(14)).foregroundStyle(DS.fog)
            nudgeCard("7:15", "Ready to plan your day?", "Morning brain-dump prompt")
            nudgeCard("21:30", "6 of 8 done — wrap up?", "Evening recap, feeds the learning loop")
        }
    }

    private func nudgeCard(_ time: String, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(time).font(DS.mono(9)).foregroundStyle(DS.ash)
                .frame(width: 38, alignment: .leading).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(DS.inter(13.5, .medium)).foregroundStyle(DS.bone)
                Text(subtitle).font(DS.inter(12)).foregroundStyle(DS.ash)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.cardGradient)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.cardStroke, lineWidth: 1))
    }

    private func stepLabel(_ text: String) -> some View {
        Text(text).font(DS.mono(10)).kerning(1).foregroundStyle(DS.ash)
    }

    // ── bottom buttons ──────────────────────────────────────────────

    private var primaryTitle: String {
        if denied { return "Try again" }
        switch step {
        case 0: return "Get started"
        case 1: return "Agree & continue"
        case 2: return busy ? "Connecting…" : "Connect"
        case 5: return "Continue"
        case 6: return busy ? "Finishing…" : "Enable notifications"
        default: return "Continue"
        }
    }

    private var caption: String? {
        if denied { return nil }
        switch step {
        case 0: return "V0.1 · PRIVATE TEST"
        case 1: return "Full terms at todoai.app/terms"
        case 2: return "Opens Google sign-in"
        default: return nil
        }
    }

    private var bottomButtons: some View {
        VStack(spacing: 12) {
            Button(action: primaryAction) {
                Text(primaryTitle)
                    .font(DS.inter(15, .medium)).foregroundStyle(Color(hex: 0x08090A))
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(DS.limeGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(busy || (step == 3 && role == nil))
            .opacity(busy || (step == 3 && role == nil) ? 0.5 : 1)

            if denied {
                Button {
                    signIn(ephemeral: true)
                } label: {
                    Text("Use a different account")
                        .font(DS.inter(14)).foregroundStyle(DS.mist)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(DS.graphite, lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else if step == 6 {
                Button {
                    finish()
                } label: {
                    Text("Not now")
                        .font(DS.inter(14)).foregroundStyle(DS.fog)
                        .frame(maxWidth: .infinity).frame(height: 48)
                }
                .buttonStyle(.plain)
            } else if let caption {
                Text(caption)
                    .font(step == 0 ? DS.mono(9) : DS.inter(11))
                    .kerning(step == 0 ? 0.7 : 0)
                    .foregroundStyle(step == 0 ? Color(hex: 0x383B3F) : DS.ash)
            }
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
    }

    private func primaryAction() {
        if denied {
            signIn(ephemeral: false)
            return
        }
        switch step {
        case 2:
            signIn(ephemeral: false)
        case 6:
            busy = true
            Task {
                _ = await Nudges.enable()
                finish()
            }
        default:
            step += 1
        }
    }

    private func signIn(ephemeral: Bool) {
        busy = true
        Task {
            do {
                Keychain.sessionToken = try await GoogleAuth.shared.signIn(ephemeral: ephemeral)
                denied = false
                step = 3
            } catch {
                denied = true  // design 4b
            }
            busy = false
        }
    }

    private func finish() {
        var profile = Profile()
        profile.role = role
        profile.wake = pad(wake)
        profile.sleep = pad(sleep)
        profile.energyPeak = peak.lowercased()
        profile.lunch = pad(lunch)
        profile.workout = workout == "Varies" ? nil : workout.lowercased()
        if role == "student" {
            profile.studyBlockMinutes = Int(studyBlock.split(separator: " ")[0])
            profile.studyTime = studyTime.lowercased()
            profile.breaks = breaks.lowercased()
            profile.deadlineBuffer = deadlineBuffer.lowercased()
        } else {
            profile.deepWorkMinutes = Int(deepWorkBlock.split(separator: " ")[0])
            profile.meetingDays = meetingDays.sorted()
            profile.codeReview = codeReview.lowercased()
            profile.onCall = onCall
        }
        Task {
            try? await API.saveProfile(profile)
            hasOnboarded = true
            busy = false
        }
    }

    private func pad(_ t: String) -> String {
        t.count == 4 ? "0\(t)" : t
    }
}

// ── T&C sections (4c) — reused by Settings' Terms screen ────────────

struct TermsSections: View {
    private let sections: [(String, String)] = [
        ("WHAT WE KEEP", "Your chat messages are retained and used to improve planning."),
        ("WHAT WE DECOUPLE", "Retained chat is separated from your name, email, and Google account. Your account is identified only to control your calendar."),
        ("DURING THE TEST", "Messages run through a free model endpoint that logs sessions. Don't paste sensitive personal data."),
        ("YOUR CALENDAR", "OAuth tokens are stored encrypted and never logged. Only events this app creates are ever edited."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(sections.enumerated()), id: \.offset) { i, section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.0).font(DS.mono(9)).kerning(1.1).foregroundStyle(DS.fog)
                    Text(section.1).font(DS.inter(13.5)).foregroundStyle(DS.mist)
                }
                .padding(.bottom, i == sections.count - 1 ? 0 : 16)
                .overlay(alignment: .bottom) {
                    if i < sections.count - 1 { DS.hairline.frame(height: 0.5) }
                }
            }
        }
    }
}

// ── pill selectors ──────────────────────────────────────────────────

struct PillGroup: View {
    let label: String
    let options: [String]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(label).font(DS.mono(10)).kerning(1).foregroundStyle(DS.ash)
            FlowLayout(spacing: 8) {
                ForEach(options, id: \.self) { opt in
                    selectPill(opt, selected: selection == opt) { selection = opt }
                }
            }
        }
    }
}

struct MultiPillGroup: View {
    let label: String
    let options: [String]
    @Binding var selection: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(label).font(DS.mono(10)).kerning(1).foregroundStyle(DS.ash)
            FlowLayout(spacing: 8) {
                ForEach(options, id: \.self) { opt in
                    selectPill(opt, selected: selection.contains(opt)) {
                        if selection.contains(opt) {
                            selection.remove(opt)
                        } else {
                            selection.insert(opt)
                        }
                    }
                }
            }
        }
    }
}

func selectPill(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title)
            .font(DS.inter(13, selected ? .medium : .regular))
            .foregroundStyle(selected ? Color(hex: 0x08090A) : DS.fog)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(selected ? DS.bone : Color.clear)
            .overlay(Capsule().stroke(selected ? Color.clear : DS.graphite, lineWidth: 0.5))
            .clipShape(Capsule())
    }
    .buttonStyle(.plain)
}
