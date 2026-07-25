import SwiftUI

struct HistoryView: View {
    var planToday: () -> Void = {}
    @State private var days: [HistoryDay] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("History").font(DS.inter(24, .medium)).foregroundStyle(DS.paper)
                    Spacer()
                    Text("LAST 30 DAYS").font(DS.mono(9)).kerning(0.8).foregroundStyle(DS.ash)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)

                if loaded, days.isEmpty {
                    emptyState
                } else {
                    ScrollView {
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
            .background(DS.void)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { DayTimelineView(date: $0) }
        }
        .task { await load() }
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
        loaded = true
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
