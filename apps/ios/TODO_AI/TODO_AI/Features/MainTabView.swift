import SwiftUI

enum AppTab: String, CaseIterable {
    case chat = "Chat"
    case history = "History"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .chat: "bubble.left"
        case .history: "clock"
        case .settings: "slider.horizontal.3"
        }
    }
}

struct MainTabView: View {
    @State private var tab: AppTab = .chat
    @State private var disconnected = false

    var body: some View {
        VStack(spacing: 0) {
            // ZStack keeps each tab's state alive across switches
            ZStack {
                ChatView().opacity(tab == .chat ? 1 : 0).allowsHitTesting(tab == .chat)
                HistoryView(planToday: { tab = .chat })
                    .opacity(tab == .history ? 1 : 0).allowsHitTesting(tab == .history)
                SettingsView().opacity(tab == .settings ? 1 : 0).allowsHitTesting(tab == .settings)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                ForEach(AppTab.allCases, id: \.self) { t in
                    Button {
                        tab = t
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: t.icon)
                                .font(.system(size: 17, weight: .light))
                            Text(t.rawValue)
                                .font(DS.inter(10, tab == t ? .medium : .regular))
                        }
                        .foregroundStyle(tab == t ? DS.acidLime : DS.ash)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
            .background(Color(hex: 0x0B0C0D))
            .overlay(alignment: .top) { DS.hairline.frame(height: 0.5) }
        }
        .background(DS.void.ignoresSafeArea())
        .onReceive(NotificationCenter.default.publisher(for: .calendarDisconnected)) { _ in
            disconnected = true
        }
        .fullScreenCover(isPresented: $disconnected) {
            DisconnectedView { disconnected = false }
        }
    }
}

/// Design 3g — Google token expired; blocking until reconnected.
private struct DisconnectedView: View {
    let done: () -> Void
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "calendar.badge.minus")
                    .font(.system(size: 24, weight: .light)).foregroundStyle(DS.ash)
                    .frame(width: 52, height: 52)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.graphite, lineWidth: 1))
                    .padding(.bottom, 4)
                Text("ERR · GOOGLE_TOKEN_EXPIRED")
                    .font(DS.mono(9)).kerning(0.9).foregroundStyle(DS.coral)
                Text("Calendar disconnected")
                    .font(DS.inter(24, .medium)).foregroundStyle(DS.paper)
                Text("Your Google session expired. Plans can't be read or synced until you reconnect.")
                    .font(DS.inter(14)).foregroundStyle(DS.fog)
                    .multilineTextAlignment(.center)
                Text("Your preferences and history are safe.")
                    .font(DS.inter(12)).foregroundStyle(DS.ash)
            }
            .padding(.horizontal, 36)
            Spacer()
            VStack(spacing: 12) {
                Button {
                    busy = true
                    Task {
                        if let token = try? await GoogleAuth.shared.signIn() {
                            Keychain.sessionToken = token
                            done()
                        }
                        busy = false
                    }
                } label: {
                    Text(busy ? "Connecting…" : "Reconnect Google")
                        .font(DS.inter(15, .medium)).foregroundStyle(Color(hex: 0x08090A))
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(DS.acidLime)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(busy)
                Text("Opens Google sign-in · same account")
                    .font(DS.inter(11)).foregroundStyle(DS.ash)
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
        .background(DS.void.ignoresSafeArea())
    }
}
