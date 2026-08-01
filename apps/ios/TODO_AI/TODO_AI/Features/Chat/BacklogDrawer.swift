import SwiftUI

/// Left drawer (hamburger in the chat header): everything parked without a
/// day. Each item schedules two ways — Auto (first free slot in the next
/// 7 days) or a picked date + time via the native wheels.
struct BacklogDrawer: View {
    @Binding var isOpen: Bool
    let onScheduled: (String) -> Void  // confirmation line for the chat

    @State private var items: [BacklogItem] = []
    @State private var loaded = false
    @State private var pickerFor: BacklogItem?
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Backlog").font(DS.inter(19, .medium)).foregroundStyle(DS.paper)
                Spacer()
                Button {
                    isOpen = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(DS.mist)
                        .frame(width: 30, height: 30)
                        .overlay(Circle().stroke(DS.graphite, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)

            Text("NO DAY YET · NEVER LOST")
                .font(DS.mono(8)).kerning(0.8).foregroundStyle(DS.ash)
                .padding(.horizontal, 18).padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if loaded, items.isEmpty {
                        Text("Nothing parked.\nSay \"sometime this week…\" in chat.")
                            .font(DS.inter(13)).foregroundStyle(DS.ash)
                            .padding(.top, 20)
                    }
                    ForEach(items) { item in
                        itemCard(item)
                    }
                    if let note {
                        Text(note).font(DS.inter(12)).foregroundStyle(DS.coral.opacity(0.9))
                    }
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.carbon)
        .overlay(alignment: .trailing) { DS.hairline.frame(width: 0.5) }
        .task { await reload() }
        .sheet(item: $pickerFor) { item in
            SchedulePickSheet(item: item) { date in
                schedule(item, at: date)
            }
        }
    }

    private func itemCard(_ item: BacklogItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(DS.category(item.category)).frame(width: 6, height: 6)
                Text(item.title).font(DS.inter(13.5, .medium)).foregroundStyle(DS.paper)
                Spacer()
                Button {
                    remove(item)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(DS.ash)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            Text("\(item.durationMinutes) MIN · \(item.category.replacingOccurrences(of: "_", with: " ").uppercased())")
                .font(DS.mono(8)).kerning(0.6).foregroundStyle(DS.ash)
            HStack(spacing: 8) {
                Button {
                    schedule(item, at: nil)
                } label: {
                    Text("Auto")
                        .font(DS.inter(12.5, .medium)).foregroundStyle(Color(hex: 0x08090A))
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(DS.limeGradient)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Button {
                    pickerFor = item
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar").font(.system(size: 10))
                        Text("Pick time")
                    }
                    .font(DS.inter(12.5)).foregroundStyle(DS.mist)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .overlay(Capsule().stroke(DS.graphite, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.02))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DS.graphite, lineWidth: 0.5))
    }

    private func reload() async {
        items = (try? await API.backlog()) ?? []
        loaded = true
    }

    private func schedule(_ item: BacklogItem, at date: Date?) {
        note = nil
        Task {
            do {
                let iso = date.map { ISO8601DateFormatter().string(from: $0) }
                let r = try await API.scheduleBacklog(id: item.id, at: iso)
                items.removeAll { $0.id == item.id }
                onScheduled("\(r.title) → \(displayWhen(r.start)). Synced.")
            } catch {
                note = error.localizedDescription
            }
        }
    }

    private func remove(_ item: BacklogItem) {
        Task {
            try? await API.dropBacklog(id: item.id)
            items.removeAll { $0.id == item.id }
        }
    }

    private func displayWhen(_ iso: String) -> String {
        let day = String(iso.prefix(10))
        let time = hhmm(iso)
        if day == todayYMD { return "today \(time)" }
        guard let d = DateFormatter.ymd.date(from: day) else { return "\(day) \(time)" }
        return "\(d.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }
}

private extension DateFormatter {
    static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// Native date + time wheels for scheduling a parked item exactly.
private struct SchedulePickSheet: View {
    let item: BacklogItem
    let onPick: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        VStack(spacing: 14) {
            Text(item.title)
                .font(DS.inter(15, .medium)).foregroundStyle(DS.paper)
                .padding(.top, 18)
            Text("PICK A DAY AND TIME · \(item.durationMinutes) MIN")
                .font(DS.mono(9)).kerning(0.8).foregroundStyle(DS.ash)
            DatePicker("", selection: $date, in: Date()...,
                       displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .tint(DS.acidLime)
                .labelsHidden()
                .padding(.horizontal, 12)
            Button {
                onPick(date)
                dismiss()
            } label: {
                Text("Schedule")
                    .font(DS.inter(15, .medium)).foregroundStyle(Color(hex: 0x08090A))
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(DS.limeGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20).padding(.bottom, 16)
        }
        .presentationDetents([.large])
        .presentationBackground(DS.carbon)
    }
}
