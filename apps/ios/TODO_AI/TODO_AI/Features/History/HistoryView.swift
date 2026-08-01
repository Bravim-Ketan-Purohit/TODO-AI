import SwiftUI

struct HistoryView: View {
    var planToday: () -> Void = {}
    @State private var days: [HistoryDay] = []
    @State private var notes: [NoteItem] = []
    @State private var wrapped: WrappedData?
    @State private var showWrapped = false
    @State private var mode = "Days"
    @State private var loaded = false
    @AppStorage("lastWrappedSeen") private var lastWrappedSeen = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("History").font(DS.inter(24, .medium)).foregroundStyle(DS.paper)
                    Spacer()
                    Text(mode == "Notes" ? "\(notes.count) NOTES" : "LAST 30 DAYS")
                        .font(DS.mono(9)).kerning(0.8).foregroundStyle(DS.ash)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)

                if let wrapped, lastWrappedSeen != wrapped.monthKey {
                    wrappedBanner(wrapped)
                }

                if !notes.isEmpty || mode == "Notes" {
                    segmented
                }

                if mode == "Notes" {
                    notesList
                } else if loaded, days.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        if !days.isEmpty {
                            DotMatrixCard(days: days)
                                .padding(.horizontal, 20).padding(.bottom, 6)
                        }
                        LazyVStack(spacing: 0) {
                            ForEach(days) { day in
                                NavigationLink(value: day.date) {
                                    HistoryRow(day: day)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .refreshable { await load() }
                }
            }
            .background(DS.pageGradient)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { DayTimelineView(date: $0) }
            .fullScreenCover(isPresented: $showWrapped) {
                if let wrapped {
                    WrappedView(data: wrapped) {
                        lastWrappedSeen = wrapped.monthKey
                        showWrapped = false
                    }
                }
            }
        }
        .task { await load() }
    }

    // ── wrapped entry banner (design 7h) ────────────────────────────

    private func wrappedBanner(_ data: WrappedData) -> some View {
        Button {
            showWrapped = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(DS.carbon)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DS.smoke, lineWidth: 1))
                        .frame(width: 40, height: 40)
                    Rectangle().fill(DS.acidLime).frame(width: 13, height: 13)
                        .cornerRadius(2).rotationEffect(.degrees(45))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(data.month), in time.")
                        .font(DS.inter(14.5, .medium)).foregroundStyle(DS.paper)
                    Text("YOUR MONTH IS READY · 45 SEC")
                        .font(DS.mono(9)).kerning(0.7).foregroundStyle(DS.fog)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(DS.acidLime)
            }
            .padding(16)
            .background(
                LinearGradient(colors: [Color(hex: 0x101114), Color(hex: 0x0F1011),
                                        Color(hex: 0x121308)],
                               startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(alignment: .topTrailing) {
                Rectangle().fill(DS.acidLime.opacity(0.07))
                    .frame(width: 64, height: 64)
                    .rotationEffect(.degrees(45))
                    .offset(x: 14, y: -14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(DS.acidLime.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20).padding(.bottom, 14)
    }

    // ── days / notes toggle (design 7r) ─────────────────────────────

    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(["Days", "Notes"], id: \.self) { tab in
                Button {
                    mode = tab
                } label: {
                    Text(tab)
                        .font(DS.inter(12.5, mode == tab ? .medium : .regular))
                        .foregroundStyle(mode == tab ? Color(hex: 0x08090A) : DS.fog)
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(mode == tab ? DS.bone : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(DS.carbon)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0x1E2023), lineWidth: 1))
        .padding(.horizontal, 20).padding(.bottom, 6)
    }

    // ── notes archive (design 7r) ───────────────────────────────────

    private var notesList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(notes) { note in
                    NavigationLink(value: note.date) {
                        HStack(alignment: .top, spacing: 12) {
                            MoodGlyph(mood: note.mood).padding(.top, 3)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(displayDate(note.date).uppercased()) · \(note.done)/\(note.total)")
                                    .font(DS.mono(9)).kerning(0.6).foregroundStyle(DS.ash)
                                Text(note.text)
                                    .font(DS.inter(13.5)).foregroundStyle(DS.mist)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer()
                            if note.hasPhoto, let img = NotePhotoStore.load(note.date) {
                                Image(uiImage: img)
                                    .resizable().scaledToFill()
                                    .frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(.vertical, 14)
                        .overlay(alignment: .bottom) { Color(hex: 0x16181A).frame(height: 0.5) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if notes.isEmpty {
                    Text("No notes yet — the evening prompt starts tonight.")
                        .font(DS.inter(13)).foregroundStyle(DS.ash)
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    /// Design 3h — dashed skeleton rows fading out + call to action.
    private var emptyState: some View {
        VStack(spacing: 0) {
            ForEach(Array([0.35, 0.22, 0.12].enumerated()), id: \.offset) { i, opacity in
                HStack(spacing: 12) {
                    Circle()
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(DS.graphite)
                        .frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x16181A))
                            .frame(width: [82, 74, 88][i], height: 8)
                        RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x121415))
                            .frame(width: [52, 46, 40][i], height: 6)
                    }
                    Spacer()
                }
                .padding(.vertical, 14)
                .opacity(opacity)
                .overlay(alignment: .bottom) {
                    if i < 2 { Color(hex: 0x16181A).frame(height: 0.5) }
                }
            }
            Spacer()
            VStack(spacing: 12) {
                Text("No days yet").font(DS.inter(15, .medium)).foregroundStyle(DS.bone)
                Text("Approve your first plan in chat and it lands here as a color-coded day.")
                    .font(DS.inter(13)).foregroundStyle(DS.ash)
                    .multilineTextAlignment(.center)
                Button(action: planToday) {
                    Text("Plan today")
                        .font(DS.inter(12.5, .medium)).foregroundStyle(DS.paper)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Color.white.opacity(0.06))
                        .overlay(Capsule().stroke(DS.smoke, lineWidth: 0.5))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 40).padding(.bottom, 80)
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private func load() async {
        days = (try? await API.history()) ?? days
        notes = (try? await API.notes()) ?? notes
        wrapped = (try? await API.wrapped())?.wrapped
        loaded = true
    }
}

// ── mood glyphs (geometric, never emoji) ────────────────────────────

struct MoodGlyph: View {
    let mood: String

    var body: some View {
        switch mood {
        case "good":
            Rectangle().fill(DS.acidLime).frame(width: 13, height: 13)
                .cornerRadius(2).rotationEffect(.degrees(45))
        case "rough":
            Triangle().fill(DS.coral).frame(width: 14, height: 12)
        default:
            Circle().fill(DS.fog).frame(width: 13, height: 13)
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// ── 7-day dot-matrix strip (design 6c — chosen) ─────────────────────

private struct DotMatrixCard: View {
    let days: [HistoryDay]

    // oldest → newest, last 7 days incl. today
    private var week: [HistoryDay] {
        Array(days.prefix(7)).reversed()
    }

    private var weekDone: Int { week.map(\.done).reduce(0, +) }
    private var weekTotal: Int { week.map(\.total).reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("LAST 7 DAYS · DOT = TASK")
                    .font(DS.mono(9)).kerning(0.9).foregroundStyle(DS.ash)
                Spacer()
                Text("\(weekDone)/\(weekTotal)")
                    .font(DS.mono(9)).foregroundStyle(DS.fog)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(week) { day in
                    let isToday = day.date == todayYMD
                    HStack(spacing: 10) {
                        Text(dayLetter(day.date))
                            .font(DS.mono(8))
                            .foregroundStyle(isToday ? DS.acidLime : Color(hex: 0x4B4F55))
                            .frame(width: 18, alignment: .leading)
                        HStack(spacing: 5) {
                            ForEach(Array(day.dots.prefix(12).enumerated()), id: \.offset) { _, dot in
                                if dot.current {
                                    Circle()
                                        .stroke(DS.acidLime, lineWidth: 1)
                                        .frame(width: 9, height: 9)
                                        .shadow(color: DS.acidLime.opacity(0.5), radius: 3)
                                        .modifier(Pulse())
                                } else if dot.done {
                                    Circle().fill(DS.category(dot.category))
                                        .frame(width: 9, height: 9)
                                } else {
                                    Circle().stroke(Color(hex: 0x2C2E33), lineWidth: 1)
                                        .frame(width: 9, height: 9)
                                }
                            }
                        }
                        Spacer()
                        Text(isToday ? "\(day.done)/\(day.total) · LIVE" : "\(day.done)/\(day.total)")
                            .font(DS.mono(8))
                            .foregroundStyle(isToday ? DS.acidLime : DS.ash)
                    }
                }
            }
            Text("FILLED = DONE · HOLLOW = OPEN · GLOWING = CURRENT BLOCK")
                .font(DS.mono(8)).kerning(0.5).foregroundStyle(Color(hex: 0x4B4F55))
        }
        .padding(14)
        .background(DS.cardGradient)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.cardStroke, lineWidth: 1))
    }

    private func dayLetter(_ ymd: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: ymd) else { return "" }
        return String(d.formatted(.dateTime.weekday(.abbreviated)).uppercased().prefix(2))
    }
}

struct Pulse: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(on ? 0.5 : 1)
            .scaleEffect(on ? 0.85 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

private struct HistoryRow: View {
    let day: HistoryDay

    private var isToday: Bool { day.date == todayYMD }
    private var fraction: CGFloat {
        day.total == 0 ? 0 : CGFloat(day.done) / CGFloat(day.total)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(DS.graphite, lineWidth: 2.5)
                Circle().trim(from: 0, to: fraction)
                    .stroke(isToday ? DS.acidLime : DS.mist,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(isToday ? "Today" : displayDate(day.date))
                    .font(DS.inter(14, .medium))
                    .foregroundStyle(isToday ? DS.paper : DS.bone)
                Text(isToday ? "\(day.done)/\(day.total) · IN PROGRESS"
                             : "\(day.done)/\(day.total) DONE")
                    .font(DS.mono(9)).kerning(0.6).foregroundStyle(DS.ash)
            }

            Spacer()

            if day.hasNote {
                Rectangle().fill(DS.acidLime.opacity(0.8)).frame(width: 6, height: 6)
                    .cornerRadius(1).rotationEffect(.degrees(45))
            }

            HStack(spacing: 3) {
                ForEach(day.categories.prefix(4), id: \.self) { cat in
                    Circle().fill(DS.category(cat)).frame(width: 5, height: 5)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.smoke)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Color(hex: 0x16181A).frame(height: 0.5) }
        .contentShape(Rectangle())
    }
}
