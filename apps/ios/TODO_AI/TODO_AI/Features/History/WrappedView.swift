import SwiftUI
import UIKit

/// Wrapped (design 7i-7n): the month as an auto-advancing story.
/// Tap right ⅔ = next, left ⅓ = back, hold to pause. No confetti —
/// the month is the reward.
struct WrappedView: View {
    let data: WrappedData
    let onDone: () -> Void

    @State private var card = 0
    @State private var paused = false
    @State private var progress: CGFloat = 0

    private var cardCount: Int { data.change == nil ? 4 : 5 }

    var body: some View {
        ZStack {
            DS.pageGradient.ignoresSafeArea()

            Group {
                switch cardIndexKind {
                case .opening: opening
                case .bigNumber: bigNumber
                case .rhythm: rhythm
                case .change: changeCard
                case .closing: closing
                }
            }
            .id(card)
            .transition(.opacity)

            // story progress bars
            VStack {
                HStack(spacing: 4) {
                    ForEach(0..<cardCount, id: \.self) { i in
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(hex: 0x1E2023))
                                Capsule().fill(DS.acidLime)
                                    .frame(width: i < card ? geo.size.width
                                           : i == card ? geo.size.width * progress : 0)
                            }
                        }
                        .frame(height: 2.5)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 14)
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { location in
            if location.x < UIScreen.main.bounds.width / 3 {
                back()
            } else {
                next()
            }
        }
        .onLongPressGesture(minimumDuration: 0.2, perform: {},
                            onPressingChanged: { paused = $0 })
        .task(id: card) {
            progress = 0
            while progress < 1, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                if !paused { progress += 0.05 / 6.0 }  // 6s per card
            }
            if !Task.isCancelled { next() }
        }
    }

    private enum Kind { case opening, bigNumber, rhythm, change, closing }
    private var cardIndexKind: Kind {
        switch card {
        case 0: .opening
        case 1: .bigNumber
        case 2: .rhythm
        case 3: data.change == nil ? .closing : .change
        default: .closing
        }
    }

    private func next() {
        if card < cardCount - 1 {
            withAnimation(.easeOut(duration: 0.25)) { card += 1 }
        }
    }

    private func back() {
        if card > 0 { withAnimation(.easeOut(duration: 0.25)) { card -= 1 } }
    }

    // ── cards ───────────────────────────────────────────────────────

    private var opening: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Rectangle().fill(DS.acidLime).frame(width: 13, height: 13)
                .cornerRadius(2).rotationEffect(.degrees(45))
            Text("\(data.month),\nin time.")
                .font(DS.inter(46, .medium)).foregroundStyle(DS.paper)
                .lineSpacing(2)
            Text("\(data.rangeLabel) · \(data.plannedDays) PLANNED DAYS")
                .font(DS.mono(10)).kerning(1.2).foregroundStyle(DS.ash)
            Spacer()
            Text("TAP RIGHT TO CONTINUE · LEFT TO GO BACK")
                .font(DS.mono(9)).kerning(1.0).foregroundStyle(Color(hex: 0x4B4F55))
                .frame(maxWidth: .infinity)
                .padding(.bottom, 40)
        }
        .padding(.horizontal, 30)
    }

    private var bigNumber: some View {
        ZStack(alignment: .bottom) {
            // ghost bars behind the type
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array([0.34, 0.52, 0.44, 0.78, 0.6].enumerated()), id: \.offset) { _, h in
                    UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4)
                        .fill(DS.category("deep_work"))
                        .frame(height: 500 * h)
                }
            }
            .padding(.horizontal, 24)
            .opacity(0.08)

            VStack(alignment: .leading, spacing: 16) {
                Spacer()
                Text("DEEP WORK")
                    .font(DS.mono(9)).kerning(1.3)
                    .foregroundStyle(DS.category("deep_work"))
                Text("\(data.deepHours) hours\nof deep work.")
                    .font(DS.inter(42, .medium)).foregroundStyle(DS.paper)
                    .lineSpacing(2)
                if let delta = data.deepDelta, delta != 0 {
                    Text(delta > 0 ? "That's \(delta) more than last month."
                                   : "That's \(-delta) fewer than last month.")
                        .font(DS.inter(15)).foregroundStyle(DS.fog)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 30)
        }
    }

    private var rhythm: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            Text("Your best weeks started with a planned Monday.")
                .font(DS.inter(32, .medium)).foregroundStyle(DS.paper)
                .lineSpacing(4)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(data.weeks.enumerated()), id: \.offset) { i, week in
                    HStack(spacing: 12) {
                        Text("WK \(i + 1)")
                            .font(DS.mono(8)).foregroundStyle(Color(hex: 0x4B4F55))
                            .frame(width: 34, alignment: .leading)
                        HStack(spacing: 7) {
                            ForEach(0..<7, id: \.self) { d in
                                Circle()
                                    .fill(d == 0 && week.plannedMonday ? DS.acidLime
                                          : d < 5 ? Color(hex: 0x383B3F) : Color(hex: 0x26282B))
                                    .frame(width: 10, height: 10)
                            }
                        }
                        Spacer()
                        Text("\(week.pct)%")
                            .font(DS.mono(9)).foregroundStyle(DS.fog)
                    }
                }
            }
            Text("LIME = PLANNED MONDAY MORNING · % = WEEK COMPLETION")
                .font(DS.mono(8)).kerning(0.8).foregroundStyle(Color(hex: 0x4B4F55))
            Spacer()
        }
        .padding(.horizontal, 30)
    }

    private var changeCard: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            Text("Your \(niceCategory) tasks turned a corner.")
                .font(DS.inter(32, .medium)).foregroundStyle(DS.paper)
                .lineSpacing(4)
            if let change = data.change {
                HStack(spacing: 1) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FIRST HALF")
                            .font(DS.mono(8)).kerning(1.0).foregroundStyle(DS.ash)
                        Text("\(change.beforePct)%")
                            .font(DS.inter(34, .medium)).foregroundStyle(DS.fog)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.carbon)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SECOND HALF")
                            .font(DS.mono(8)).kerning(1.0).foregroundStyle(DS.fog)
                        Text("\(change.afterPct)%")
                            .font(DS.inter(34, .medium)).foregroundStyle(DS.acidLime)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0x121308))
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0x1E2023), lineWidth: 1))
                Text("Completion went \(change.beforePct)% → \(change.afterPct)%. Something clicked.")
                    .font(DS.inter(15)).foregroundStyle(DS.fog)
            }
            Spacer()
        }
        .padding(.horizontal, 30)
    }

    private var niceCategory: String {
        (data.change?.category ?? "").replacingOccurrences(of: "_", with: " ")
    }

    private var closing: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer().frame(height: 90)
            Rectangle().fill(DS.acidLime).frame(width: 13, height: 13)
                .cornerRadius(2).rotationEffect(.degrees(45))
            Text(data.landedPct >= 70 ? "Your strongest month yet." : "The month, on the record.")
                .font(DS.inter(38, .medium)).foregroundStyle(DS.paper)
                .lineSpacing(2)
            Text("\(data.totalTasks) TASKS · \(data.landedPct)% LANDED · \(data.deepHours)H DEEP")
                .font(DS.mono(9)).kerning(1.0).foregroundStyle(DS.ash)
            Spacer()
            VStack(spacing: 10) {
                Button {
                    share()
                } label: {
                    Text("Share")
                        .font(DS.inter(15, .medium)).foregroundStyle(Color(hex: 0x08090A))
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(DS.limeGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                Button {
                    onDone()
                } label: {
                    Text("Close")
                        .font(DS.inter(13.5)).foregroundStyle(DS.fog).frame(height: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 30)
    }

    private func share() {
        let renderer = ImageRenderer(content:
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 7) {
                    Rectangle().fill(DS.acidLime).frame(width: 9, height: 9)
                        .cornerRadius(2).rotationEffect(.degrees(45))
                    Text("TODO_AI").font(DS.mono(8)).kerning(1.2).foregroundStyle(DS.fog)
                }
                Spacer()
                Text(data.rangeLabel).font(DS.mono(8)).kerning(1.0).foregroundStyle(DS.ash)
                Text("\(data.month),\nin time.")
                    .font(DS.inter(40, .medium)).foregroundStyle(DS.paper)
                Text("\(data.totalTasks) TASKS · \(data.landedPct)% LANDED · \(data.deepHours)H DEEP")
                    .font(DS.mono(9)).kerning(0.8).foregroundStyle(DS.ash)
                Spacer()
                Text("PLANNED BY VOICE · SYNCED TO CALENDAR")
                    .font(DS.mono(7)).kerning(0.8).foregroundStyle(Color(hex: 0x4B4F55))
            }
            .padding(28)
            .frame(width: 360, height: 640, alignment: .leading)
            .background(LinearGradient(colors: [Color(hex: 0x101114), Color(hex: 0x0A0B0D)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)))
        renderer.scale = 3
        guard let image = renderer.uiImage else { return }
        let sheet = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController?.present(sheet, animated: true)
    }
}
