import SwiftUI
import UIKit

/// The Sunday Review (design 7a-7g): a 5-step swipeable ritual — numbers,
/// budgets, insight, dropped tasks, share card. Ninety seconds, mostly taps.
struct SundayReviewView: View {
    let review: WeekReview
    let onFinished: () -> Void

    @State private var step = 0
    @State private var counted = 0
    @State private var budgets: [String: Double] = [:]
    @State private var insightAccepted: Bool?
    @State private var decisions: [Int: String] = [:]  // task id → carry|backlog|letgo
    @State private var resolved = false

    private var weekLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -6, to: end) ?? end
        return "\(f.string(from: start))–\(f.string(from: end))".uppercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            // segmented progress (fills ahead of the page)
            HStack(spacing: 5) {
                ForEach(0..<5) { i in
                    Capsule()
                        .fill(i <= step ? DS.acidLime : Color(hex: 0x1E2023))
                        .frame(height: 3)
                }
            }
            .padding(.horizontal, 20).padding(.top, 14)
            .animation(.easeOut(duration: 0.2), value: step)

            TabView(selection: $step) {
                numbers.tag(0)
                scoreboard.tag(1)
                insightStep.tag(2)
                dropped.tag(3)
                finish.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(DS.pageGradient)
        .onAppear {
            for c in review.categories {
                budgets[c.category] = c.budgetHours ?? c.suggestedBudget ?? 0
            }
        }
        .onChange(of: step) { _, new in
            if new == 4 { finishRitual() }
        }
    }

    private func header(_ label: String) -> some View {
        HStack {
            Text(label).font(DS.mono(9)).kerning(1.1).foregroundStyle(DS.ash)
            Spacer()
            Text(weekLabel).font(DS.mono(9)).kerning(0.7).foregroundStyle(Color(hex: 0x4B4F55))
        }
        .padding(.horizontal, 24).padding(.top, 16)
    }

    private func footer(_ n: Int) -> some View {
        HStack {
            Button("Skip") { step = 4 }
                .font(DS.inter(13)).foregroundStyle(DS.ash).buttonStyle(.plain)
            Spacer()
            Text("SWIPE · \(n) / 5")
                .font(DS.mono(9)).kerning(1.0).foregroundStyle(Color(hex: 0x4B4F55))
        }
        .padding(.horizontal, 24).padding(.bottom, 40)
    }

    // ── step 1 · the numbers (count-up + floating lime) ─────────────

    private var numbers: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("TODO_AI · WEEK REVIEW")
            Spacer()
            VStack(alignment: .leading, spacing: 18) {
                Text("\(counted) of \(review.total)\nlanded.")
                    .font(DS.inter(44, .medium))
                    .foregroundStyle(DS.paper)
                    .lineSpacing(2)
                    .contentTransition(.numericText())
                Text([review.avgSlipMin.map { "\($0 >= 0 ? "+" : "")\($0) MIN AVG SLIP" },
                      review.bestDay.map { "BEST DAY \($0.uppercased())" }]
                    .compactMap(\.self).joined(separator: " · "))
                    .font(DS.mono(9)).kerning(0.9).foregroundStyle(DS.ash)
            }
            .padding(.horizontal, 28)
            .overlay(alignment: .topLeading) { Sparkles() }
            Spacer()
            footer(1)
        }
        .onAppear {
            counted = 0
            withAnimation(.easeOut(duration: 0.8)) { counted = review.done }
        }
    }

    // ── step 2 · the scoreboard (drag to set next week) ─────────────

    private var scoreboard: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("TODO_AI · WEEK REVIEW")
            VStack(alignment: .leading, spacing: 6) {
                Text("Against your budgets")
                    .font(DS.inter(26, .medium)).foregroundStyle(DS.paper)
                Text("Drag a bar to set next week's.")
                    .font(DS.inter(13)).foregroundStyle(DS.fog)
            }
            .padding(.horizontal, 24).padding(.top, 12)
            Spacer()
            VStack(alignment: .leading, spacing: 20) {
                ForEach(review.categories, id: \.self) { cat in
                    BudgetRow(cat: cat, budget: bindingFor(cat.category))
                }
                if review.categories.contains(where: { $0.budgetHours == nil }) {
                    Text("FIRST RUN: BUDGETS PROPOSED FROM LAST WEEK'S ACTUALS")
                        .font(DS.mono(8)).kerning(0.7).foregroundStyle(Color(hex: 0x4B4F55))
                }
            }
            .padding(.horizontal, 24)
            Spacer()
            footer(2)
        }
    }

    private func bindingFor(_ cat: String) -> Binding<Double> {
        Binding(get: { budgets[cat] ?? 0 }, set: { budgets[cat] = $0 })
    }

    // ── step 3 · the insight ────────────────────────────────────────

    private var insightStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("TODO_AI · ONE INSIGHT")
            Spacer()
            VStack(alignment: .leading, spacing: 24) {
                if let insight = review.insight {
                    Text(insight.text)
                        .font(DS.inter(30, .medium)).foregroundStyle(DS.paper)
                        .lineSpacing(4)
                    HStack(spacing: 8) {
                        Button {
                            withAnimation(.spring(duration: 0.3)) { insightAccepted = true }
                        } label: {
                            HStack(spacing: 7) {
                                if insightAccepted == true {
                                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                                }
                                Text(insightAccepted == true ? "Accepted" : "Accept")
                            }
                            .font(DS.inter(13.5, .medium))
                            .foregroundStyle(insightAccepted == true ? DS.acidLime : DS.paper)
                            .padding(.horizontal, 20).padding(.vertical, 11)
                            .background(insightAccepted == true ? DS.acidLime.opacity(0.12) : Color.white.opacity(0.06))
                            .overlay(Capsule().stroke(insightAccepted == true ? DS.acidLime : Color(hex: 0x43464C), lineWidth: insightAccepted == true ? 1 : 0.5))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        Button {
                            insightAccepted = false
                        } label: {
                            Text("Reject")
                                .font(DS.inter(13.5))
                                .foregroundStyle(insightAccepted == false ? DS.fog : Color(hex: 0x4B4F55))
                                .padding(.horizontal, 20).padding(.vertical, 11)
                                .overlay(Capsule().stroke(Color(hex: 0x1E2023), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    if insightAccepted == true {
                        HStack(spacing: 11) {
                            Circle().fill(DS.category(insight.category)).frame(width: 6, height: 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(insight.category.replacingOccurrences(of: "_", with: " ").capitalized) window → \(insight.suggestedWindow)")
                                    .font(DS.inter(12.5)).foregroundStyle(DS.paper)
                                Text("PREFERENCE UPDATED · APPLIES NEXT PLAN")
                                    .font(DS.mono(8)).kerning(0.7).foregroundStyle(DS.ash)
                            }
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(DS.fog)
                        }
                        .padding(13)
                        .background(DS.cardGradient)
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.cardStroke, lineWidth: 1))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                } else {
                    Text("No single pattern stood out this week. That's a kind of consistency.")
                        .font(DS.inter(26, .medium)).foregroundStyle(DS.paper)
                        .lineSpacing(4)
                }
            }
            .padding(.horizontal, 28)
            Spacer()
            footer(3)
        }
    }

    // ── step 4 · what got dropped (swipe rows) ──────────────────────

    private var dropped: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("TODO_AI · WEEK REVIEW")
            VStack(alignment: .leading, spacing: 6) {
                Text("\(review.dropped.count) didn't land")
                    .font(DS.inter(26, .medium)).foregroundStyle(DS.paper)
                Text("Right = next week · Left = let go · Tap = backlog")
                    .font(DS.inter(13)).foregroundStyle(DS.fog)
            }
            .padding(.horizontal, 24).padding(.top, 12)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(review.dropped) { task in
                        DroppedRow(task: task, decision: decisions[task.id]) { d in
                            withAnimation(.spring(duration: 0.35)) { decisions[task.id] = d }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                    }
                    if review.dropped.isEmpty {
                        Text("Everything landed. Nothing to triage.")
                            .font(DS.inter(13)).foregroundStyle(DS.ash)
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 16)
            }
            footer(4)
        }
    }

    // ── step 5 · the card ───────────────────────────────────────────

    private var finish: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("WEEK CLOSED").font(DS.mono(9)).kerning(1.1).foregroundStyle(DS.ash)
                Text("That's the ritual.")
                    .font(DS.inter(26, .medium)).foregroundStyle(DS.paper)
            }
            .padding(.horizontal, 24).padding(.top, 16)
            .overlay(alignment: .topTrailing) { Sparkles().padding(.trailing, 30) }
            Spacer()
            shareCardPreview
                .frame(maxWidth: .infinity)
            Spacer()
            VStack(spacing: 10) {
                Button {
                    shareCard()
                } label: {
                    Text("Share")
                        .font(DS.inter(15, .medium)).foregroundStyle(Color(hex: 0x08090A))
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(DS.limeGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: DS.acidLime.opacity(0.25), radius: 11, y: 5)
                }
                .buttonStyle(.plain)
                Button {
                    onFinished()
                } label: {
                    Text("Done — see you Monday")
                        .font(DS.inter(13.5)).foregroundStyle(DS.fog)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.bottom, 40)
        }
    }

    private var shareCardPreview: some View {
        ReviewShareCard(weekLabel: weekLabel, done: review.done, total: review.total)
            .frame(width: 210, height: 373)
            .background(
                LinearGradient(colors: [Color(hex: 0x101114), Color(hex: 0x0A0B0D)],
                               startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(DS.graphite, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 25, y: 10)
    }

    // ── actions ─────────────────────────────────────────────────────

    private func finishRitual() {
        guard !resolved else { return }
        resolved = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let carry = decisions.filter { $0.value == "carry" }.map(\.key)
        let backlog = decisions.filter { $0.value == "backlog" }.map(\.key)
        let letgo = decisions.filter { $0.value == "letgo" }.map(\.key)
        let accepted = insightAccepted == true ? review.insight : nil
        let newBudgets = budgets.filter { $0.value > 0 }
        Task {
            if !carry.isEmpty || !backlog.isEmpty || !letgo.isEmpty {
                try? await API.resolveReview(carry: carry, backlog: backlog, letgo: letgo)
            }
            if let me = try? await API.me(), var profile = me.profile {
                profile.weeklyBudgets = newBudgets
                if let accepted {
                    var windows = profile.categoryWindows ?? [:]
                    windows[accepted.category] = accepted.suggestedWindow
                    profile.categoryWindows = windows
                }
                try? await API.saveProfile(profile)
            }
        }
    }

    private func shareCard() {
        let renderer = ImageRenderer(content:
            ReviewShareCard(weekLabel: weekLabel, done: review.done, total: review.total)
                .frame(width: 360, height: 640)
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

// ── pieces ──────────────────────────────────────────────────────────

private struct BudgetRow: View {
    let cat: WeekCategory
    @Binding var budget: Double
    @State private var dragging = false

    var body: some View {
        let color = DS.category(cat.category)
        let done = cat.doneHours ?? 0
        let target = max(budget, 1)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(cat.category.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(DS.inter(13, dragging ? .medium : .regular))
                    .foregroundStyle(dragging ? DS.paper : DS.bone)
                Spacer()
                Text("\(String(format: "%.2g", done))/\(String(format: "%.2g", budget))H")
                    .font(DS.mono(10))
                    .foregroundStyle(done >= budget ? DS.fog : DS.coral)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0x16181A))
                    Capsule().fill(color.opacity(0.75))
                        .frame(width: geo.size.width * min(1, done / target))
                    if dragging {
                        Text("NEXT WK · \(String(format: "%.2g", budget))H")
                            .font(DS.mono(9, .medium)).foregroundStyle(Color(hex: 0x08090A))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(DS.acidLime)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .offset(x: max(0, min(geo.size.width - 80,
                                                  geo.size.width * budget / 14 - 40)),
                                    y: -26)
                    }
                    Circle().fill(DS.bone)
                        .frame(width: dragging ? 22 : 16, height: dragging ? 22 : 16)
                        .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                        .offset(x: max(0, min(geo.size.width - 16,
                                              geo.size.width * budget / 14 - 8)),
                                y: -5)
                }
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        dragging = true
                        let h = (v.location.x / geo.size.width * 14).rounded(toStep: 0.5)
                        if h != budget {
                            budget = max(0, min(14, h))
                            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
                        }
                    }
                    .onEnded { _ in dragging = false })
            }
            .frame(height: 6)
        }
        .padding(dragging ? 12 : 0)
        .background(dragging ? Color.white.opacity(0.02) : .clear)
        .cornerRadius(10)
        .animation(.spring(duration: 0.25), value: dragging)
    }
}

private struct DroppedRow: View {
    let task: DroppedTask
    let decision: String?
    let decide: (String) -> Void
    @State private var offset: CGFloat = 0

    var body: some View {
        ZStack {
            // revealed actions behind the row
            HStack {
                Text("CARRY → NEXT WEEK")
                    .font(DS.mono(9, .medium)).kerning(0.8).foregroundStyle(DS.acidLime)
                    .opacity(offset > 30 ? 1 : 0)
                Spacer()
                Text("LET GO")
                    .font(DS.mono(9, .medium)).kerning(0.8).foregroundStyle(DS.coral)
                    .opacity(offset < -30 ? 1 : 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(offset > 30 ? DS.acidLime.opacity(0.12)
                        : offset < -30 ? DS.coral.opacity(0.1) : .clear)
            .cornerRadius(10)

            HStack(spacing: 10) {
                Circle().fill(DS.category(task.category)).frame(width: 6, height: 6)
                Text(task.title)
                    .font(DS.inter(13.5))
                    .foregroundStyle(DS.paper)
                    .strikethrough(decision == "letgo")
                Spacer()
                Text(caption)
                    .font(DS.mono(9)).kerning(0.5)
                    .foregroundStyle(decision == nil ? DS.ash : captionColor)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(DS.carbon)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(Color(hex: 0x1E2023), lineWidth: 0.5))
            .opacity(decision == "letgo" ? 0.4 : 1)
            .offset(x: offset)
            .gesture(DragGesture()
                .onChanged { v in offset = v.translation.width }
                .onEnded { v in
                    if v.translation.width > 96 { decide("carry") }
                    else if v.translation.width < -96 { decide("letgo") }
                    withAnimation(.spring(duration: 0.4)) { offset = 0 }
                })
            .onTapGesture { decide("backlog") }
        }
    }

    private var caption: String {
        switch decision {
        case "carry": "NEXT WEEK"
        case "backlog": "BACKLOG"
        case "letgo": "LET GO"
        default: displayDate(task.date).prefix(3).uppercased()
        }
    }

    private var captionColor: Color {
        switch decision {
        case "carry": DS.acidLime
        case "backlog": DS.mist
        default: Color(hex: 0x4B4F55)
        }
    }
}

/// 9:16 share card (design 7f).
struct ReviewShareCard: View {
    let weekLabel: String
    let done: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Rectangle().fill(DS.acidLime).frame(width: 9, height: 9)
                    .cornerRadius(2).rotationEffect(.degrees(45))
                Text("TODO_AI").font(DS.mono(8)).kerning(1.2).foregroundStyle(DS.fog)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Text(weekLabel).font(DS.mono(8)).kerning(1.0).foregroundStyle(DS.ash)
                (Text("\(done)/\(total)\n").font(DS.inter(38, .medium)).foregroundStyle(DS.paper)
                    + Text("landed").font(DS.inter(17)).foregroundStyle(DS.fog))
                HStack(spacing: 6) {
                    ForEach(["deep_work", "health", "meals", "admin", "social"], id: \.self) {
                        Circle().fill(DS.category($0)).frame(width: 7, height: 7)
                    }
                }
            }
            Spacer()
            Text("PLANNED BY VOICE · SYNCED TO CALENDAR")
                .font(DS.mono(7)).kerning(0.8).foregroundStyle(Color(hex: 0x4B4F55))
        }
        .padding(22)
    }
}

/// Floating lime particles (7b/7f).
struct Sparkles: View {
    var body: some View {
        ZStack {
            sparkle(x: 46, y: -30, size: 5, delay: 0, round: false)
            sparkle(x: 120, y: -56, size: 4, delay: 0.4, round: true)
            sparkle(x: 250, y: -44, size: 5, delay: 0.8, round: false)
            sparkle(x: 290, y: 4, size: 3, delay: 0.2, round: true)
            sparkle(x: 80, y: 16, size: 4, delay: 0.6, round: false)
        }
        .allowsHitTesting(false)
    }

    private func sparkle(x: CGFloat, y: CGFloat, size: CGFloat,
                         delay: Double, round: Bool) -> some View {
        FloatDot(delay: delay) {
            Group {
                if round {
                    Circle().fill(DS.acidLime.opacity(0.5))
                } else {
                    Rectangle().fill(DS.acidLime.opacity(0.8))
                        .cornerRadius(1).rotationEffect(.degrees(28))
                }
            }
            .frame(width: size, height: size)
        }
        .offset(x: x, y: y)
    }
}

private struct FloatDot<Content: View>: View {
    let delay: Double
    @ViewBuilder let content: Content
    @State private var up = false

    var body: some View {
        content
            .offset(y: up ? -7 : 0)
            .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true).delay(delay),
                       value: up)
            .onAppear { up = true }
    }
}

private extension Double {
    func rounded(toStep step: Double) -> Double {
        (self / step).rounded() * step
    }
}
