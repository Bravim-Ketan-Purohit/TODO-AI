import AVFoundation
import Combine
import Speech
import SwiftUI

/// On-device speech-to-text (design 5i). Transcription stays on the phone —
/// the transcript only goes to the composer; the user still hits send.
@MainActor
final class SpeechRecorder: ObservableObject {
    @Published var transcript = ""
    @Published var level: CGFloat = 0
    @Published var elapsed = 0
    @Published var denied = false

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timer: Timer?

    func start() {
        SFSpeechRecognizer.requestAuthorization { auth in
            AVAudioApplication.requestRecordPermission { granted in
                Task { @MainActor in
                    guard auth == .authorized, granted else {
                        self.denied = true
                        return
                    }
                    self.begin()
                }
            }
        }
    }

    func restart() {
        stop()
        transcript = ""
        elapsed = 0
        start()
    }

    private func begin() {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            denied = true
            return
        }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request = req

        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024,
                         format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            // RMS → waveform level
            guard let data = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += data[i] * data[i] }
            let rms = sqrt(sum / Float(max(n, 1)))
            Task { @MainActor in self?.level = CGFloat(min(1, rms * 14)) }
        }
        engine.prepare()
        try? engine.start()

        task = recognizer.recognitionTask(with: req) { [weak self] result, _ in
            if let text = result?.bestTranscription.formattedString {
                Task { @MainActor in self?.transcript = text }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsed += 1 }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        request?.endAudio()
        task?.cancel()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

struct VoiceRantView: View {
    let onAccept: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var rec = SpeechRecorder()
    @State private var bars: [CGFloat] = Array(repeating: 0.08, count: 28)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Talk your day.")
                    .font(DS.inter(24, .medium)).foregroundStyle(DS.paper)
                Text("Ramble — I'll sort it into tasks. Nothing leaves your phone until you send.")
                    .font(DS.inter(14)).foregroundStyle(DS.fog)
            }
            .padding(.top, 28)

            if rec.denied {
                deniedCard.padding(.top, 24)
            } else {
                transcriptCard.padding(.top, 24)
            }

            Spacer()
            waveform
            controls.padding(.top, 24).padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(DS.void)
        .onAppear { rec.start() }
        .onDisappear { rec.stop() }
        .onChange(of: rec.level) { _, new in
            bars.removeFirst()
            bars.append(max(0.08, new))
        }
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 7) {
                    Circle().fill(DS.acidLime).frame(width: 5, height: 5)
                    Text("LISTENING · ON-DEVICE")
                        .font(DS.mono(9)).kerning(0.8).foregroundStyle(DS.ash)
                }
                Spacer()
                Text(String(format: "%d:%02d", rec.elapsed / 60, rec.elapsed % 60))
                    .font(DS.mono(10)).foregroundStyle(DS.ash)
            }
            ScrollView {
                (Text(rec.transcript.isEmpty ? "…" : rec.transcript)
                    .foregroundStyle(rec.transcript.isEmpty ? DS.ash : DS.bone)
                    + Text(" ▍").foregroundStyle(DS.acidLime))
                    .font(DS.inter(15))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
        }
        .padding(16)
        .background(DS.carbon)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.graphite, lineWidth: 1))
    }

    private var deniedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mic or speech access is off.")
                .font(DS.inter(14, .medium)).foregroundStyle(DS.paper)
            Text("Enable both for TODO_AI in Settings to talk your day.")
                .font(DS.inter(13)).foregroundStyle(DS.fog)
            pillButton("Open Settings", highlighted: true) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.carbon)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.graphite, lineWidth: 1))
    }

    private var waveform: some View {
        HStack(spacing: 4) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, h in
                Capsule()
                    .fill(DS.acidLime.opacity(0.35 + 0.65 * h))
                    .frame(width: 3, height: 6 + h * 38)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.12), value: bars)
    }

    private var controls: some View {
        HStack {
            Button {
                rec.stop()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium)).foregroundStyle(DS.mist)
                    .frame(width: 52, height: 52)
                    .overlay(Circle().stroke(DS.graphite, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                rec.restart()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 16, weight: .medium)).foregroundStyle(DS.mist)
                    .frame(width: 52, height: 52)
                    .overlay(Circle().stroke(DS.graphite, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                rec.stop()
                let text = rec.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { onAccept(text) }
                dismiss()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(hex: 0x08090A))
                    .frame(width: 64, height: 64)
                    .background(DS.acidLime)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(rec.transcript.isEmpty)
            .opacity(rec.transcript.isEmpty ? 0.35 : 1)
        }
        .padding(.horizontal, 12)
    }
}
