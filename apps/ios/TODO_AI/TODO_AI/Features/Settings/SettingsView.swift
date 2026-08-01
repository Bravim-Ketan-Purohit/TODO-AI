import SwiftUI

struct SettingsView: View {
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var me: Me?

    private var maskedEmail: String {
        guard let email = me?.email, let at = email.firstIndex(of: "@") else { return "—" }
        return "\(email.prefix(1))•••\(email[at...])"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("Settings").font(DS.inter(24, .medium)).foregroundStyle(DS.paper)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.vertical, 12)

                ScrollView {
                    VStack(spacing: 20) {
                        group("PROFILE") {
                            row("Role", me?.profile?.role?.capitalized ?? "—")
                            divider
                            row("Rhythm", rhythmSummary)
                            divider
                            NavigationLink(value: "anchors") {
                                row("Schedule", anchorSummary)
                            }
                            .buttonStyle(.plain)
                            divider
                            NavigationLink(value: "budgets") {
                                row("Weekly budgets", "")
                            }
                            .buttonStyle(.plain)
                        }
                        group("CALENDAR") {
                            row("Google account", maskedEmail)
                            divider
                            row("Time zone", "Device · \(TimeZone.current.abbreviation() ?? "")", chevron: false)
                            divider
                            NavigationLink(value: "colors") {
                                HStack(spacing: 8) {
                                    Text("Category colors").font(DS.inter(14)).foregroundStyle(DS.bone)
                                    Spacer()
                                    HStack(spacing: 3) {
                                        ForEach(["deep_work", "health", "meals", "admin", "social"], id: \.self) {
                                            Circle().fill(DS.category($0)).frame(width: 5, height: 5)
                                        }
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .medium)).foregroundStyle(DS.smoke)
                                }
                                .frame(minHeight: 46)
                            }
                            .buttonStyle(.plain)
                        }
                        group("DATA & PRIVACY") {
                            row("Chat retention", "De-identified", chevron: false)
                            divider
                            NavigationLink(value: "terms") {
                                row("Terms & privacy", "")
                            }
                            .buttonStyle(.plain)
                            divider
                            Button {
                                Keychain.sessionToken = nil
                                hasOnboarded = false
                            } label: {
                                HStack {
                                    Text("Sign out").font(DS.inter(14)).foregroundStyle(DS.coral)
                                    Spacer()
                                }
                                .frame(minHeight: 46)
                            }
                            .buttonStyle(.plain)
                        }
                        Text("TODO_AI V0.1 · PRIVATE TEST")
                            .font(DS.mono(9)).kerning(0.7).foregroundStyle(Color(hex: 0x383B3F))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .background(DS.pageGradient)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { destination in
                switch destination {
                case "anchors": ScheduleView(me: me)
                case "budgets": BudgetsView()
                case "colors": CategoryColorsView()
                default: TermsView()
                }
            }
        }
        .task { me = try? await API.me() }
    }

    private var rhythmSummary: String {
        guard let p = me?.profile else { return "—" }
        return "Wake \(p.wake) · Peak \(p.energyPeak.prefix(2).uppercased())"
    }

    private var anchorSummary: String {
        let blocks = me?.anchors?.classes ?? 0
        return blocks > 0 ? "\(blocks) recurring" : "Add blocks"
    }

    private var divider: some View { DS.hairline.frame(height: 0.5) }

    private func group(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(DS.mono(9)).kerning(1.1).foregroundStyle(DS.ash)
            VStack(spacing: 0, content: content)
                .padding(.horizontal, 14)
                .background(DS.cardGradient)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.cardStroke, lineWidth: 1))
        }
    }

    private func row(_ title: String, _ value: String, chevron: Bool = true) -> some View {
        HStack(spacing: 8) {
            Text(title).font(DS.inter(14)).foregroundStyle(DS.bone)
            Spacer()
            if !value.isEmpty {
                Text(value).font(DS.inter(13)).foregroundStyle(DS.fog)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(DS.smoke)
            }
        }
        .frame(minHeight: 46)
    }
}
