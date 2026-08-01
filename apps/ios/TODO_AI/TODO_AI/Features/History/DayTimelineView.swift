import SwiftUI

struct DayTimelineView: View {
    let date: String
    @Environment(\.dismiss) private var dismiss
    @State private var payload: DayPayload?
    @State private var focusBlock: Block?
    @State private var note: NoteItem?

    private let pph: CGFloat = 44  // points per hour, from frame 1j

    private struct Block: Identifiable {
        let id: String
        let title: String
        let startMin: Int
        let endMin: Int
        let category: String?
        let fixed: Bool
        let status: String?
        let taskId: Int?
    }

    private var blocks: [Block] {
        guard let p = payload else { return [] }
        var out: [Block] = p.tasks.map {
            Block(id: "t\($0.id)", title: $0.title,
                  startMin: minutesSinceMidnight($0.startTs), endMin: minutesSinceMidnight($0.endTs),
                  category: $0.category, fixed: false, status: $0.status, taskId: $0.id)
        }
        out += p.anchors.map {
            Block(id: "a\($0.taskId)", title: $0.title,
                  startMin: minutesSinceMidnight($0.start), endMin: minutesSinceMidnight($0.end),
                  category: $0.category, fixed: false, status: nil, taskId: nil)
        }
        out += p.fixed.map {
            Block(id: "f\($0.id)", title: $0.title,
                  startMin: minutesSinceMidnight($0.start), endMin: minutesSinceMidnight($0.end),
                  category: nil, fixed: true, status: nil, taskId: nil)
        }
        return out.sorted { $0.startMin < $1.startMin }
    }

    private var startHour: Int { min(7, blocks.map { $0.startMin / 60 }.min() ?? 7) }
    private var endHour: Int { max(22, blocks.map { ($0.endMin + 59) / 60 }.max() ?? 22) }
    private var done: Int { payload?.tasks.filter { $0.status == "completed" }.count ?? 0 }
    private var total: Int { payload?.tasks.count ?? 0 }
    private var isToday: Bool { date == todayYMD }
    private var isPast: Bool { date < todayYMD }

    var body: some View {
        VStack(spacing: 0) {
            header
            // day note (7q): quiet card above the timeline
            if let note {
                HStack(spacing: 12) {
                    MoodGlyph(mood: note.mood)
                    Text("\u{201C}\(note.text)\u{201D}")
                        .font(DS.inter(13)).italic().foregroundStyle(Color(hex: 0xB4B8BD))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if note.hasPhoto, let img = NotePhotoStore.load(note.date) {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }
                .padding(13)
                .background(DS.cardGradient)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.cardStroke, lineWidth: 1))
                .padding(.horizontal, 16).padding(.bottom, 10)
            }
            ScrollView {
                TimelineView(.everyMinute) { context in
                    canvas(now: context.date)
                }
            }
        }
        .background(DS.pageGradient)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            payload = try? await API.day(date)
            note = ((try? await API.notes()) ?? []).first { $0.date == date }
        }
        .fullScreenCover(item: $focusBlock) { block in
            let next = blocks.first { $0.startMin >= block.endMin }
            FocusSessionView(title: block.title, category: block.category,
                             endMin: block.endMin, taskId: block.taskId,
                             next: next.map {
                                 "\($0.title.uppercased()) \(String(format: "%d:%02d", $0.startMin / 60, $0.startMin % 60))"
                             },
                             onStatus: setStatus)
        }
    }

    private func canvas(now: Date) -> some View {
        let nowMin = Calendar.current.component(.hour, from: now) * 60
            + Calendar.current.component(.minute, from: now)
        let nextTaskId = isToday
            ? blocks.first(where: { !$0.fixed && $0.taskId != nil && $0.startMin > nowMin })?.id
            : nil

        return ZStack(alignment: .topLeading) {
            ForEach(startHour...endHour, id: \.self) { h in
                HStack(spacing: 8) {
                    Text("\(h):00")
                        .font(DS.mono(9)).foregroundStyle(Color(hex: 0x383B3F))
                        .frame(width: 36, alignment: .trailing)
                    Color(hex: 0x16181A).frame(height: 0.5)
                }
                .offset(y: CGFloat(h - startHour) * pph)
            }
            ForEach(blocks) { block in
                blockView(block, nowMin: nowMin, highlighted: block.id == nextTaskId)
                    .frame(height: max(18, CGFloat(block.endMin - block.startMin) / 60 * pph))
                    .padding(.leading, 48).padding(.trailing, 4)
                    .offset(y: CGFloat(block.startMin - startHour * 60) / 60 * pph)
            }
            // now-line (design 3e) — lime dot + hairline at the current minute
            if isToday, nowMin >= startHour * 60, nowMin <= endHour * 60 {
                HStack(spacing: 0) {
                    Circle().fill(DS.acidLime).frame(width: 5, height: 5)
                    DS.acidLime.opacity(0.55).frame(height: 1)
                }
                .padding(.leading, 36)
                .offset(y: CGFloat(nowMin - startHour * 60) / 60 * pph - 2)
                .zIndex(2)
            }
        }
        .frame(height: CGFloat(endHour - startHour + 1) * pph + 24, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 16).padding(.top, 8)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(DS.mist)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(DS.graphite, lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(isToday ? "Today" : displayDate(date))
                    .font(DS.inter(19, .medium)).foregroundStyle(DS.paper)
                Text(isToday
                     ? "\(done) OF \(total) DONE · \(nowHHMM)"
                     : "\(done) OF \(total) DONE")
                    .font(DS.mono(9)).kerning(0.7).foregroundStyle(DS.ash)
            }

            Spacer()

            if total > 0 {
                Button {
                    shareCard()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(DS.mist)
                        .frame(width: 34, height: 34)
                        .overlay(Circle().stroke(DS.graphite, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }

            ZStack {
                Circle().stroke(DS.graphite, lineWidth: 2.5)
                Circle().trim(from: 0, to: total == 0 ? 0 : CGFloat(done) / CGFloat(total))
                    .stroke(isToday ? DS.acidLime : DS.mist,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 26, height: 26)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    /// Day share card: render the summary as an image → system share sheet.
    private func shareCard() {
        guard let payload else { return }
        let renderer = ImageRenderer(content: ShareCardView(
            dateLabel: isToday ? "TODAY · \(displayDate(date).uppercased())"
                               : displayDate(date).uppercased(),
            done: done, total: total, tasks: payload.tasks))
        renderer.scale = 3
        guard let image = renderer.uiImage else { return }
        let sheet = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController?.present(sheet, animated: true)
    }

    private var nowHHMM: String {
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        return f.string(from: Date())
    }

    @ViewBuilder
    private func blockView(_ block: Block, nowMin: Int, highlighted: Bool) -> some View {
        let color = DS.category(block.category)
        let missed = block.status == "missed"
        let completed = block.status == "completed"
        let fixedNow = isToday && block.fixed && block.startMin <= nowMin && nowMin < block.endMin
        let dimmed = isPast || missed || completed
        let content = HStack(spacing: 7) {
            if block.fixed {
                Text(block.title).font(DS.inter(10)).foregroundStyle(fixedNow ? DS.mist : DS.fog)
                Spacer()
                Text(fixedNow ? "FIXED · NOW" : "FIXED")
                    .font(DS.mono(7)).kerning(0.6)
                    .foregroundStyle(fixedNow ? DS.ash : Color(hex: 0x4B4F55))
            } else {
                Text(block.title)
                    .font(DS.inter(11, .medium)).foregroundStyle(DS.paper)
                    .strikethrough(missed)
                Spacer()
                if completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                } else if missed {
                    Text("MISSED").font(DS.mono(7)).kerning(0.6)
                        .foregroundStyle(Color.white.opacity(0.5))
                } else {
                    Text(String(format: "%d:%02d", block.startMin / 60, block.startMin % 60))
                        .font(DS.mono(8)).foregroundStyle(Color.white.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(block.fixed ? Color.clear : color.opacity(highlighted ? 0.16 : 0.14))
        .overlay(RoundedRectangle(cornerRadius: 5)
            .stroke(block.fixed ? (fixedNow ? DS.smoke : Color(hex: 0x2C2E33))
                                : color.opacity(highlighted ? 0.8 : 0.5),
                    lineWidth: highlighted ? 1 : 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .opacity(block.fixed ? (fixedNow ? 1 : 0.6) : (dimmed ? 0.45 : 1))

        if let taskId = block.taskId {
            Menu {
                // focus session (5h): only the block happening right now
                if isToday, block.startMin <= nowMin, nowMin < block.endMin {
                    Button { focusBlock = block } label: {
                        Label("Start focus", systemImage: "timer")
                    }
                }
                Button("Completed") { setStatus(taskId, "completed") }
                Button("Missed") { setStatus(taskId, "missed") }
                Button("Planned") { setStatus(taskId, "planned") }
            } label: {
                content
            }
        } else {
            content
        }
    }

    private func setStatus(_ taskId: Int, _ status: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            try? await API.setStatus(taskId: taskId, status: status)
            payload = try? await API.day(date)
        }
    }
}

// ── day share card (rendered to an image, never shown in-app) ───────

private struct ShareCardView: View {
    let dateLabel: String
    let done: Int
    let total: Int
    let tasks: [TaskItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(DS.acidLime)
                    .frame(width: 10, height: 10)
                    .cornerRadius(2)
                    .rotationEffect(.degrees(45))
                Text("TODO_AI").font(DS.inter(14, .semibold)).foregroundStyle(DS.paper)
                Spacer()
                Text(dateLabel).font(DS.mono(9)).kerning(0.8).foregroundStyle(DS.ash)
            }
            Text("\(done) of \(total) landed.")
                .font(DS.inter(26, .medium)).foregroundStyle(DS.paper)
            VStack(alignment: .leading, spacing: 9) {
                ForEach(tasks.prefix(8)) { task in
                    HStack(spacing: 9) {
                        Circle().fill(DS.category(task.category)).frame(width: 6, height: 6)
                        Text(task.title)
                            .font(DS.inter(13)).foregroundStyle(DS.mist)
                            .strikethrough(task.status == "missed")
                            .lineLimit(1)
                        Spacer()
                        if task.status == "completed" {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(DS.acidLime)
                        } else {
                            Text(hhmm(task.startTs)).font(DS.mono(9)).foregroundStyle(DS.ash)
                        }
                    }
                }
                if tasks.count > 8 {
                    Text("+ \(tasks.count - 8) more")
                        .font(DS.mono(9)).foregroundStyle(DS.ash)
                }
            }
            DS.hairline.frame(height: 0.5)
            Text("PLANNED BY VOICE · SYNCED TO CALENDAR")
                .font(DS.mono(8)).kerning(0.8).foregroundStyle(DS.ash)
        }
        .padding(24)
        .frame(width: 360)
        .background(DS.pageGradient)
    }
}
