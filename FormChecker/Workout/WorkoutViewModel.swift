import AVFoundation
import CoreImage
import Foundation
import Observation
import PoseEngine
import SwiftUI

/// `CGImage`는 Sendable로 표시돼 있지 않지만 **불변 객체**다. 만들어서 한 번 넘길 뿐이라
/// 경합이 없다.
private struct CGImageBox: @unchecked Sendable { let image: CGImage }

/// 한 번에 한 프레임만 통과시킨다. 통과하지 못한 프레임은 **버린다** — 쌓아두면
/// 지연만 늘고 보여줄 수 있는 것은 어차피 최신 프레임 하나다.
private final class FrameGate: @unchecked Sendable {
    private let lock = NSLock()
    private var busy = false

    func take() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if busy { return false }
        busy = true
        return true
    }

    func release() {
        lock.lock()
        busy = false
        lock.unlock()
    }
}

@MainActor
@Observable
final class WorkoutViewModel {

    private(set) var snapshot = WorkoutSnapshot()
    private(set) var engineReady = false
    private(set) var engineError: String?
    private(set) var modelName = "-"
    private(set) var sourceLabel = "-"
    private(set) var completedReps: [CompletedRep] = []
    /// 번들 영상 경로에서만 쓴다. 카메라는 프리뷰 레이어가 직접 그린다.
    private(set) var previewImage: CGImage?
    private(set) var usingCamera = false
    private(set) var cameraDenied = false

    private let pipeline = PosePipeline()
    private let audio = AudioCues()
    private var source: FrameSource?
    private let work = DispatchQueue(label: "com.mist.formchecker.pipeline", qos: .userInitiated)
    private let gate = FrameGate()
    private(set) var droppedByBackpressure = 0
    /// `CIContext`는 스레드 안전하다(애플 문서). 프레임 변환은 파이프라인 큐에서 돈다.
    private nonisolated(unsafe) let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var lastPreviewMs: Int64 = 0

    private(set) var cameraSource: CameraFrameSource?

    // ── 수명 ────────────────────────────────────────────────

    func start() async {
        // 운동 중 화면이 꺼지면 안 된다 — 폰을 세워두고 떨어져서 쓴다.
        UIApplication.shared.isIdleTimerDisabled = true
        audio.start()
        wireCallbacks()

        if !engineReady {
            await loadEngine()
            guard engineReady else { return }
        }
        await startSource()
    }

    func stop() {
        source?.stop()
        source = nil
        audio.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func loadEngine() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            work.async { [pipeline] in
                do {
                    try pipeline.loadEngine()
                    Task { @MainActor in
                        self.engineReady = true
                        self.modelName = pipeline.modelName
                        continuation.resume()
                    }
                } catch {
                    Task { @MainActor in
                        self.engineError = error.localizedDescription
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func startSource() async {
        if CameraFrameSource.isAvailable {
            let granted = await requestCameraAccess()
            if granted {
                let camera = CameraFrameSource()
                if camera.configure() {
                    cameraSource = camera
                    usingCamera = true
                    attach(camera)
                    return
                }
            } else {
                // 🔴 iOS는 두 번째 요청이 불가능하다 — 설정으로 보내는 길을 줘야 한다.
                cameraDenied = true
            }
        }
        // 시뮬레이터에는 카메라가 없다. 같은 파이프라인에 번들 영상을 넣는다.
        if let video = VideoFrameSource() {
            usingCamera = false
            attach(video)
        } else {
            engineError = "프레임을 받을 곳이 없습니다"
        }
    }

    private func attach(_ newSource: FrameSource) {
        source = newSource
        sourceLabel = newSource.label
        let pipeline = self.pipeline
        let work = self.work
        let gate = self.gate
        newSource.onFrame = { [weak self] packet in
            // 🔴 **처리 중이면 버린다.** `work.async`는 무제한 버퍼라, 프레임이 추론보다
            //    빨리 들어오면 큐가 끝없이 자라고 조작(기준 자세 재기)까지 그 뒤에 줄을
            //    선다. Android `STRATEGY_KEEP_ONLY_LATEST`가 카메라 단에서 하던 일을
            //    여기서도 해야 한다.
            guard gate.take() else {
                self?.countDropped()
                return
            }
            work.async {
                pipeline.process(packet)
                self?.publishPreview(packet.pixelBuffer)
                gate.release()
            }
        }
        newSource.start()
    }

    private func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    private func wireCallbacks() {
        pipeline.onSnapshot = { [weak self] snapshot in
            Task { @MainActor in self?.snapshot = snapshot }
        }
        pipeline.onRepCompleted = { [weak self] rep in
            Task { @MainActor in self?.completedReps.append(rep) }
        }
        pipeline.onCue = { [weak self] cue in
            Task { @MainActor in self?.audio.play(cue) }
        }
    }

    /// 영상 경로에서만 화면에 그릴 이미지를 만든다. 카메라는 프리뷰 레이어가 맡는다.
    private nonisolated func publishPreview(_ buffer: CVPixelBuffer) {
        let image = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else { return }
        let box = CGImageBox(image: cgImage)
        Task { @MainActor in
            guard !self.usingCamera else { return }
            self.previewImage = box.image
        }
    }

    // ── 조작 ────────────────────────────────────────────────

    nonisolated func countDropped() {
        Task { @MainActor in self.droppedByBackpressure += 1 }
    }

    /// 전면 카메라는 프리뷰가 거울처럼 보인다 — **그릴 때만** 뒤집는다.
    var mirrorPreview: Bool { usingCamera && cameraSource?.position == .front }

    func toggleCamera() {
        guard let camera = cameraSource else { return }
        camera.togglePosition()
        // 렌즈가 바뀌면 기준선이 무효다. 다시 재게 한다.
        work.async { [pipeline] in pipeline.cancelCalibration() }
    }

    func beginCalibration(prepSeconds: Int) {
        work.async { [pipeline] in
            pipeline.prepSeconds = prepSeconds
            pipeline.beginCalibration(nowMs: Monotonic.nowMs)
        }
    }

    func finishSession() {
        // 🔴 **0회로 끝낸 세션은 저장하지 않는다** — 사용자에게는 기록이 아니라 잘못 누른 흔적이다.
        //    (저장소는 Phase 3에서 붙는다. 지금은 판단만 같은 자리에 둔다.)
        audio.play(.sessionEnd)
    }

    var canSave: Bool { snapshot.repCount > 0 }
}
