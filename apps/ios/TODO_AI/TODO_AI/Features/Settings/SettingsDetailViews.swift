import SwiftUI

// ── shared sub-screen chrome (back circle + 19pt title, per 3j) ─────

struct SubScreen<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
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
                Text(title).font(DS.inter(19, .medium)).foregroundStyle(DS.paper)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content }
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(DS.void)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// ── anchors editor (3j) ─────────────────────────────────────────────

struct AnchorsView: View {
    let me: Me?

    var body: some View {
        SubScreen(title: "Anchors") {
            Text("Fixed points the scheduler never moves. Tasks fill the gaps.")
                .font(DS.inter(12.5)).foregroundStyle(DS.ash)

            card {
                anchorRow("Sleep", sleepDetail)
                divider
                anchorRow("Lunch", lunchDetail)
                divider
                anchorRow("Workout", workoutDetail)
                divider
                anchorRow(focusTitle, focusDetail, chevron: false)
            }

            card {
                anchorRow("Classes", classesDetail, chevron: (me?.anchors?.classes ?? 0) > 0)
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 14, weight: .light)).foregroundStyle(DS.fog)
                    .padding(.top, 1)
                Text("Faster in chat: \"move my lunch anchor to 1pm\"")
                    .font(DS.inter(12)).foregroundStyle(DS.fog)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.02))
            .cornerRadius(6)
        }
    }

    private var profile: Profile? { me?.profile }

    private var sleepDetail: String {
        guard let p = profile else { return "—" }
        return "\(p.sleep) – \(p.wake)"
    }

    private var lunchDetail: String {
        guard let p = profile else { return "—" }
        return "\(p.lunch) · 45 MIN"
    }

    private var workoutDetail: String {
        guard let w = profile?.workout else { return "NOT SET · VARIES" }
        return "\(w.uppercased()) · 60 MIN"
    }

    private var focusTitle: String {
        profile?.role == "student" ? "Study window" : "Deep-work window"
    }

    private var focusDetail: String {
        guard let p = profile else { return "—" }
        if p.role == "student" {
            let block = p.studyBlockMinutes ?? 45
            return "\((p.studyTime ?? p.energyPeak).uppercased()) · \(block) MIN BLOCKS"
        }
        let block = p.deepWorkMinutes ?? 90
        return "\(p.energyPeak.uppercased()) PEAK · \(block) MIN BLOCKS"
    }

    private var classesDetail: String {
        let count = me?.anchors?.classes ?? 0
        guard count > 0 else { return "NONE YET · ADD IN CHAT" }
        if let until = me?.anchors?.until {
            return "\(count) RECURRING · THROUGH \(displayDate(until).uppercased())"
        }
        return "\(count) RECURRING"
    }

    private var divider: some View { DS.hairline.frame(height: 0.5) }

    private func card(@ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 0, content: content)
            .padding(.horizontal, 14)
            .background(DS.carbon)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.graphite, lineWidth: 1))
    }

    private func anchorRow(_ title: String, _ detail: String, chevron: Bool = true) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DS.inter(14)).foregroundStyle(DS.bone)
                Text(detail).font(DS.mono(9)).kerning(0.5).foregroundStyle(DS.ash)
            }
            Spacer()
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(DS.smoke)
            }
        }
        .frame(minHeight: 52)
    }
}

// ── category colors (3k) ────────────────────────────────────────────

struct CategoryColorsView: View {
    private let categories: [(key: String, name: String)] = [
        ("deep_work", "Deep work"), ("health", "Health"), ("meals", "Meals"),
        ("admin", "Admin"), ("social", "Social"),
    ]
    @State private var expanded: String? = "meals"
    @State private var refresh = 0  // bump to re-read overrides

    var body: some View {
        SubScreen(title: "Category colors") {
            Text("Hue = category. Shade = status. Maps to Google Calendar's event palette.")
                .font(DS.inter(12.5)).foregroundStyle(DS.ash)

            VStack(spacing: 0) {
                ForEach(Array(categories.enumerated()), id: \.element.key) { i, cat in
                    categoryRow(cat.key, cat.name, isLast: i == categories.count - 1)
                }
            }
            .padding(.horizontal, 14)
            .background(DS.carbon)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.graphite, lineWidth: 1))

            statusPreview
        }
        .id(refresh)
    }

    @ViewBuilder
    private func categoryRow(_ key: String, _ name: String, isLast: Bool) -> some View {
        let hex = DS.categoryHex(key)
        let isOpen = expanded == key
        VStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expanded = isOpen ? nil : key
                }
            } label: {
                HStack(spacing: 10) {
                    Circle().fill(Color(hex: hex)).frame(width: 8, height: 8)
                    Text(name)
                        .font(DS.inter(14, isOpen ? .medium : .regular))
                        .foregroundStyle(isOpen ? DS.paper : DS.bone)
                    Spacer()
                    Text(DS.paletteNames[hex] ?? "CUSTOM")
                        .font(DS.mono(9)).kerning(0.5)
                        .foregroundStyle(isOpen ? DS.fog : DS.ash)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isOpen ? DS.fog : DS.smoke)
                }
                .frame(minHeight: 50)
            }
            .buttonStyle(.plain)

            if isOpen {
                HStack(spacing: 10) {
                    ForEach(DS.palette, id: \.self) { swatch in
                        Button {
                            DS.setCategoryHex(key, swatch)
                            refresh += 1
                        } label: {
                            Circle()
                                .fill(Color(hex: swatch))
                                .frame(width: 26, height: 26)
                                .opacity(swatch == hex ? 1 : 0.35)
                                .overlay {
                                    if swatch == hex {
                                        Circle().stroke(DS.void, lineWidth: 3)
                                        Circle().stroke(DS.mist, lineWidth: 1).padding(-2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.leading, 18).padding(.bottom, 14)
            }
        }
        .overlay(alignment: .bottom) {
            if !isLast { DS.hairline.frame(height: 0.5) }
        }
    }

    private var statusPreview: some View {
        let key = expanded ?? "meals"
        let color = Color(hex: DS.categoryHex(key))
        let name = categories.first { $0.key == key }?.name.uppercased() ?? "MEALS"
        return VStack(alignment: .leading, spacing: 10) {
            Text("STATUS PREVIEW · \(name)")
                .font(DS.mono(9)).kerning(0.9).foregroundStyle(DS.ash)
            HStack(spacing: 8) {
                statusChip("Planned", color: color, opacity: 1, struck: false)
                statusChip("Done", color: color, opacity: 0.45, struck: false)
                statusChip("Missed", color: color, opacity: 0.45, struck: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.carbon)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.graphite, lineWidth: 1))
    }

    private func statusChip(_ label: String, color: Color, opacity: Double, struck: Bool) -> some View {
        Text(label)
            .font(DS.inter(10, .medium)).foregroundStyle(DS.paper)
            .strikethrough(struck)
            .frame(maxWidth: .infinity).frame(height: 30)
            .background(color.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(color.opacity(0.45), lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .opacity(opacity)
    }
}

// ── terms (reuses 4c content) ───────────────────────────────────────

struct TermsView: View {
    var body: some View {
        SubScreen(title: "Terms & privacy") {
            Text("We keep the data,\nnot the person")
                .font(DS.inter(24, .medium)).foregroundStyle(DS.paper)
            TermsSections()
            Text("Full terms at todoai.app/terms")
                .font(DS.inter(11)).foregroundStyle(DS.ash)
                .padding(.top, 4)
        }
    }
}
