import ActivityKit
import AVFoundation
import SwiftUI
import UIKit

/// Soundscape engine: four synthesized ambient layers — rain, café murmur,
/// brown noise, fire crackle — all generated on-device (nothing bundled,
/// nothing licensed). Mixes with the user's own audio; plays while locked.
final class FocusSound {
    static let shared = FocusSound()
    static let layers = ["rain", "cafe", "brown", "fire"]
    private let engine = AVAudioEngine()
    private var attached = false

    /// layer id → 0…1. Written from the UI, read in the render callback.
    /// ponytail: unsynchronized Float reads; a torn frame is inaudible.
    var levels: [String: Float] = [:]

    private var brownLast: Float = 0
    private var rainBrown: Float = 0
    private var prevWhite: Float = 0
    private var fireEnv: Float = 0
    private var cafeLast: Float = 0
    private var cafeWobble: Float = 0

    private lazy var node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList in
        guard let self else { return noErr }
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let rain = levels["rain"] ?? 0
        let cafe = levels["cafe"] ?? 0
        let brown = levels["brown"] ?? 0
        let fire = levels["fire"] ?? 0
        for frame in 0..<Int(frameCount) {
            let white = Float.random(in: -1...1)
            var sample: Float = 0
            if brown > 0 {
                brownLast = (brownLast + 0.02 * white) / 1.02
                sample += brownLast * 3.5 * 0.3 * brown
            }
            if rain > 0 {  // bright hiss over a soft bed
                rainBrown = (rainBrown + 0.04 * white) / 1.04
                sample += ((white - prevWhite) * 0.12 + rainBrown * 1.4) * 0.5 * rain
            }
            if fire > 0 {  // low rumble + random crackle pops
                if Float.random(in: 0...1) < 0.00045 { fireEnv = 1 }
                fireEnv *= 0.994
                sample += (brownLast == 0 ? white * 0.02 : brownLast * 2.4 * 0.18) * fire
                sample += white * fireEnv * 0.5 * fire
            }
            if cafe > 0 {  // murmur: low-passed noise with a slow wobble
                cafeLast += 0.008 * (white - cafeLast)
                cafeWobble += 0.00002 * (Float.random(in: -1...1) - cafeWobble * 0.001)
                sample += cafeLast * (2.4 + cafeWobble * 60) * 0.55 * cafe
            }
            prevWhite = white
            for buffer in buffers {
                UnsafeMutableBufferPointer<Float>(buffer)[frame] = sample
            }
        }
        return noErr
    }

    var anyOn: Bool { levels.values.contains { $0 > 0.01 } }

    func apply(_ mix: [String: Float]) {
        levels = mix
        anyOn ? start() : stop()
    }

    func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        if !attached {
            engine.attach(node)
            let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
            engine.connect(node, to: engine.mainMixerNode,
                           format: AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
            attached = true
        }
        try? engine.start()
    }

    func stop() {
        engine.pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Per-category persisted mixes: the mix you build during a deep_work block
/// auto-engages on the next deep_work block.
enum SoundscapeStore {
    static func mix(for category: String) -> [String: Float] {
        guard let data = UserDefaults.standard.data(forKey: "soundscapeMixes"),
              let all = try? JSONDecoder().decode([String: [String: Float]].self, from: data)
        else { return [:] }
        return all[category] ?? all["_last"] ?? [:]
    }

    static func save(_ mix: [String: Float], for category: String) {
        var all = (UserDefaults.standard.data(forKey: "soundscapeMixes")
            .flatMap { try? JSONDecoder().decode([String: [String: Float]].self, from: $0) }) ?? [:]
        all[category] = mix
        all["_last"] = mix
        UserDefaults.standard.set(try? JSONEncoder().encode(all), forKey: "soundscapeMixes")
    }
}

/// Focus session (design 5h): a block that defends itself. Just a timer —
/// no system Focus mode, no blocking claims. Ends itself at the block's end.
struct FocusSessionView: View {
    let title: String
    let category: String?
    let endMin: Int
    let taskId: Int?
    var next: String?  // "LUNCH 12:30" — for the Live Activity (5g)
    let onStatus: (Int, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var activity: Activity<FocusActivityAttributes>?
    @State private var mix: [String: Float] = [:]
    @State private var showMixer = false

    private func remaining(at now: Date) -> Int {
        let nowMin = Calendar.current.component(.hour, from: now) * 60
            + Calendar.current.component(.minute, from: now)
        let nowSec = Calendar.current.component(.second, from: now)
        return max(0, endMin * 60 - (nowMin * 60 + nowSec))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = remaining(at: context.date)
            let color = DS.category(category)
            VStack(spacing: 0) {
                Spacer()
                HStack(spacing: 8) {
                    Circle().fill(color).frame(width: 6, height: 6)
                    Text("FOCUS · \((category ?? "task").replacingOccurrences(of: "_", with: " ").uppercased())")
                        .font(DS.mono(10)).kerning(1.0).foregroundStyle(DS.ash)
                }
                Text(String(format: "%d:%02d", left / 60, left % 60))
                    .font(DS.mono(64))
                    .foregroundStyle(DS.paper)
                    .monospacedDigit()
                    .padding(.top, 18)
                Text(title)
                    .font(DS.inter(16, .medium)).foregroundStyle(DS.mist)
                    .padding(.top, 6)
                Text("UNTIL \(String(format: "%d:%02d", endMin / 60, endMin % 60))")
                    .font(DS.mono(10)).kerning(0.8).foregroundStyle(DS.ash)
                    .padding(.top, 10)
                Button {
                    showMixer = true
                } label: {
                    let n = mix.values.filter { $0 > 0.01 }.count
                    HStack(spacing: 6) {
                        Image(systemName: n > 0 ? "speaker.wave.2.fill" : "speaker.slash")
                            .font(.system(size: 10, weight: .medium))
                        Text(n > 0 ? "SOUNDSCAPE · \(n) LAYER\(n == 1 ? "" : "S")" : "SOUNDSCAPE OFF")
                            .font(DS.mono(9)).kerning(0.8)
                    }
                    .foregroundStyle(n > 0 ? DS.acidLime : DS.ash)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .overlay(Capsule().stroke(n > 0 ? DS.acidLime.opacity(0.4) : DS.graphite,
                                              lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .padding(.top, 18)
                Spacer()
                if left == 0 {
                    Text("Block ended.")
                        .font(DS.inter(14)).foregroundStyle(DS.fog)
                        .padding(.bottom, 16)
                }
                Button {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    if let taskId { onStatus(taskId, "completed") }
                    dismiss()
                } label: {
                    Text(left == 0 ? "Mark done" : "Done early")
                        .font(DS.inter(15, .medium)).foregroundStyle(Color(hex: 0x08090A))
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(DS.limeGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                Button {
                    dismiss()
                } label: {
                    Text(left == 0 ? "Close" : "Leave focus")
                        .font(DS.inter(13)).foregroundStyle(DS.ash)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .padding(.top, 4).padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.pageGradient)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            startActivity()
            // the mix you built last time for this category auto-engages
            mix = SoundscapeStore.mix(for: category ?? "task")
            FocusSound.shared.apply(mix)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            FocusSound.shared.stop()
            SoundscapeStore.save(mix, for: category ?? "task")
            let current = activity
            Task { await current?.end(nil, dismissalPolicy: .immediate) }
        }
        .sheet(isPresented: $showMixer) {
            SoundscapeSheet(mix: $mix)
                .presentationDetents([.height(380)])
                .presentationBackground(DS.carbon)
        }
        .onChange(of: mix) { _, new in
            FocusSound.shared.apply(new)
        }
    }

    // lock screen + Dynamic Island companion (design 5g)
    private func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              let end = Calendar.current.date(bySettingHour: endMin / 60,
                                              minute: endMin % 60, second: 0, of: .now),
              end > .now else { return }
        activity = try? Activity.request(
            attributes: FocusActivityAttributes(title: title, category: category ?? "task"),
            content: .init(state: .init(endDate: end, next: next), staleDate: end))
    }
}

// ── soundscape mixer (user request: layered focus audio) ────────────

struct SoundscapeSheet: View {
    @Binding var mix: [String: Float]

    private let tiles: [(id: String, name: String, icon: String)] = [
        ("rain", "Rain", "cloud.rain"),
        ("cafe", "Café", "cup.and.saucer"),
        ("brown", "Deep", "waveform"),
        ("fire", "Fire", "flame"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Soundscape")
                .font(DS.inter(17, .medium)).foregroundStyle(DS.paper)
                .padding(.top, 20)
            Text("LAYERS MIX · SAVED PER CATEGORY · PLAYS WHILE LOCKED")
                .font(DS.mono(8)).kerning(0.7).foregroundStyle(DS.ash)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
                      spacing: 10) {
                ForEach(tiles, id: \.id) { tile in
                    let level = mix[tile.id] ?? 0
                    let active = level > 0.01
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: tile.icon)
                                .font(.system(size: 14))
                                .foregroundStyle(active ? DS.acidLime : DS.fog)
                            Text(tile.name)
                                .font(DS.inter(13, active ? .medium : .regular))
                                .foregroundStyle(active ? DS.paper : DS.fog)
                            Spacer()
                        }
                        if active {
                            Slider(value: Binding(
                                get: { Double(mix[tile.id] ?? 0) },
                                set: { mix[tile.id] = Float($0) }), in: 0.05...1)
                                .tint(DS.acidLime)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                    .background(active ? DS.acidLime.opacity(0.06) : Color.white.opacity(0.02))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(active ? DS.acidLime.opacity(0.4) : DS.graphite, lineWidth: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(duration: 0.25)) {
                            mix[tile.id] = active ? 0 : 0.6
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .animation(.spring(duration: 0.25), value: mix)
    }
}
