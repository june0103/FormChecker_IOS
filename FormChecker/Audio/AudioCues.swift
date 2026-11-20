import AVFoundation
import Foundation
import PoseEngine

/// 소리 신호.
///
/// **폰을 세워두고 2~3m 떨어져 쓰는 앱이라 소리가 주 피드백 채널이다.** 화면을 못 볼 수도
/// 있다는 전제로 설계한다.
///
/// iOS에는 Android `ToneGenerator`에 해당하는 것이 없어 짧은 톤을 직접 합성한다.
/// 🔴 **인정(ACK)과 경고(NACK)는 사람 귀에 확실히 구분돼야 한다** — 거리를 두고 듣는다.
/// 그래서 음높이뿐 아니라 **개수와 방향**(올라감/내려감)까지 다르게 만든다.
final class AudioCues {

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffers: [AudioCue: AVAudioPCMBuffer] = [:]
    private var started = false

    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        buffers = Self.makeBuffers(format: format)
    }

    func start() {
        guard !started else { return }
        do {
            // 운동 중 음악을 듣는 사용자가 많다 — **다른 앱 소리를 끊지 않는다.**
            // `.playback`이라 무음 스위치에서도 들린다(소리가 주 채널이므로 그쪽을 택한다).
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            player.play()
            started = true
        } catch {
            // 소리가 안 나는 것은 하드 에러가 아니다. 화면 피드백은 그대로 동작한다.
            started = false
        }
    }

    func stop() {
        guard started else { return }
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        started = false
    }

    func play(_ cue: AudioCue) {
        guard started, let buffer = buffers[cue] else { return }
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    // ── 합성 ────────────────────────────────────────────────

    private struct Tone {
        let frequency: Double
        let durationMs: Double
        let gapMs: Double
    }

    private static func recipe(for cue: AudioCue) -> [Tone] {
        switch cue {
        // 카운트다운 틱은 **줄어들 때만** 울린다 → 침묵이 "아직 안 세고 있다"는 신호가 된다.
        case .countdown: [Tone(frequency: 660, durationMs: 60, gapMs: 0)]
        // 기준 자세 완료 — 올라가는 두 음.
        case .calibrated: [Tone(frequency: 660, durationMs: 90, gapMs: 20),
                           Tone(frequency: 990, durationMs: 140, gapMs: 0)]
        // 실패 — 낮고 둔탁하게.
        case .failed: [Tone(frequency: 220, durationMs: 260, gapMs: 0)]
        // ACK — 짧고 높은 한 번.
        case .repDone: [Tone(frequency: 880, durationMs: 90, gapMs: 0)]
        // NACK — 낮게 두 번 **내려간다**. ACK와 개수·방향·음높이가 전부 다르다.
        case .repWarned: [Tone(frequency: 494, durationMs: 120, gapMs: 40),
                          Tone(frequency: 370, durationMs: 180, gapMs: 0)]
        case .sessionEnd: [Tone(frequency: 523, durationMs: 120, gapMs: 30),
                           Tone(frequency: 392, durationMs: 220, gapMs: 0)]
        }
    }

    private static func makeBuffers(format: AVAudioFormat) -> [AudioCue: AVAudioPCMBuffer] {
        var result: [AudioCue: AVAudioPCMBuffer] = [:]
        for cue in AudioCue.allCases {
            let tones = recipe(for: cue)
            let totalMs = tones.reduce(0) { $0 + $1.durationMs + $1.gapMs }
            let frames = AVAudioFrameCount(format.sampleRate * totalMs / 1000)
            guard frames > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
                  let channel = buffer.floatChannelData?[0] else { continue }
            buffer.frameLength = frames

            var index = 0
            for tone in tones {
                let toneFrames = Int(format.sampleRate * tone.durationMs / 1000)
                let gapFrames = Int(format.sampleRate * tone.gapMs / 1000)
                for i in 0..<toneFrames where index < Int(frames) {
                    let t = Double(i) / format.sampleRate
                    // 양끝을 짧게 페이드해 클릭 잡음을 없앤다.
                    let fade = min(1.0, min(Double(i), Double(toneFrames - i)) / (format.sampleRate * 0.005))
                    channel[index] = Float(sin(2 * .pi * tone.frequency * t) * 0.35 * fade)
                    index += 1
                }
                for _ in 0..<gapFrames where index < Int(frames) {
                    channel[index] = 0
                    index += 1
                }
            }
            result[cue] = buffer
        }
        return result
    }
}
