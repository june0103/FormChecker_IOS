import AVFoundation
import CoreImage
import Foundation
import Observation
import PoseEngine
import Storage
import SwiftUI

/// 완주한 rep과 그때의 벽시계 시각.
struct RecordedRep: Sendable {
    let rep: CompletedRep
    let recordedAt: Int64
}

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
    private(set) var recorded: [RecordedRep] = []
    private(set) var savedSessionId: String?
    /// 번들 영상 경로에서만 쓴다. 카메라는 프리뷰 레이어가 직접 그린다.
    private(set) var previewImage: CGImage?
    private(set) var usingCamera = false
    private(set) var cameraDenied = false
    /// 카메라 세션이 끊겼는가(전화·다른 앱·화면 분할). **왜 멈췄는지 말해야 한다** —
    /// 말하지 않으면 마지막 프레임에 멈춘 화면이 "앱이 죽었다"로 읽힌다.
    private(set) var cameraInterrupted = false

    private let pipeline: PosePipeline
    private let audio = AudioCues()
    private var source: FrameSource?
    private let work = DispatchQueue(label: "com.mist.formchecker.pipeline", qos: .userInitiated)
    private let gate = FrameGate()
    private let repository = WorkoutRepository()
    private let sessionId = UUID().uuidString
    private var sessionStartedAt = Int64(Date().timeIntervalSince1970 * 1000)
    private(set) var droppedByBackpressure = 0
    /// `CIContext`는 스레드 안전하다(애플 문서). 프레임 변환은 파이프라인 큐에서 돈다.
    private nonisolated(unsafe) let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var lastPreviewMs: Int64 = 0

    private(set) var cameraSource: CameraFrameSource?

    /// 🔴 **자세 기준 완화는 세션이 시작될 때 한 번 읽는다.** 도중에 바뀌면 같은 세션
    /// 안에서 다른 기준으로 센 rep이 섞이고, 나중에 임계값을 재분석할 수 없다.
    init(relaxedForm: Bool = AppSettings.shared.relaxedForm) {
        pipeline = PosePipeline(relaxedForm: relaxedForm)
        // 스플래시가 미리 읽어 둔 엔진이 있으면 그걸 쓴다. 가져가면서 비우므로
        // 두 번째 세션은 직접 읽는다.
        pipeline.preloadedEngine = {
            ModelPreloader.shared.take().map {
                PreloadedEngine(engine: $0.engine, loadMs: $0.loadMs)
            }
        }
    }

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
                    camera.onInterruption = { [weak self] interrupted in
                        Task { @MainActor in self?.cameraInterrupted = interrupted }
                    }
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
                pipeline.process(pixelBuffer: packet.pixelBuffer, timestampMs: packet.timestampMs)
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
            // 벽시계 시각은 **여기서** 찍는다 — 상태머신의 시각은 단조 시계라 날짜가 없다.
            let recordedAt = Int64(Date().timeIntervalSince1970 * 1000)
            Task { @MainActor in
                self?.recorded.append(RecordedRep(rep: rep, recordedAt: recordedAt))
            }
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

    /// 🔴 **백프레셔로 버린 프레임도 분모에 넣는다.** 추론이 실패한 것만 세면
    /// 느려서 버린 프레임이 통계에서 사라져, 느릴수록 좋아 보이는 지표가 된다.
    nonisolated func countDropped() {
        work.async { [pipeline] in pipeline.countBackpressureDrop() }
        Task { @MainActor in self.droppedByBackpressure += 1 }
    }

    /// 🔴 **iOS는 두 번째 권한 요청이 불가능하다.** 한 번 거부되면 앱이 다시 물을 수
    /// 없고, 사용자가 설정에서 직접 켜야 한다 — 그 길을 앱이 열어 줘야 한다.
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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

    /// 세션을 끝낸다.
    ///
    /// 🔴 **0회로 끝낸 세션은 저장하지 않는다** — 사용자에게는 기록이 아니라 **잘못 누른
    /// 흔적**이고, 기록 목록과 홈 세션 수에 그대로 쌓인다. 거르는 것은 **여기(호출부)의
    /// 몫이다** — 저장소는 부르면 그대로 저장한다.
    ///
    /// - Returns: 저장했으면 세션 id, 0회라 묻는 중이면 nil.
    @discardableResult
    func finishSession() -> String? {
        guard canSave else { return nil }
        audio.play(.sessionEnd)
        return persist()
    }

    /// 파이프라인은 전용 큐에 갇혀 있다. **세션 끝에 한 번만** 건너와 읽는다 —
    /// 매 프레임이 아니라 종료 시 한 번이라 `sync`의 대기(최대 추론 1회)가 문제되지 않는다.
    private var performanceSamples: PerformanceSamples { work.sync { pipeline.samples } }
    private var modelLoadMs: Int64? { work.sync { pipeline.modelLoadMs } }

    private func persist() -> String? {
        // 판정에 실제로 쓴 임계값을 그대로 적는다 — `relaxed()`를 썼다면 그 값이다.
        let relaxed = pipeline.relaxedForm
        let thresholds = relaxed ? FormThresholds().relaxed() : FormThresholds()
        let session = WorkoutSession(
            id: sessionId,
            userId: nil,
            exerciseType: "squat",
            deviceModel: UIDevice.current.model,
            osVersion: "iOS " + UIDevice.current.systemVersion,
            poseModel: modelName,
            startedAt: sessionStartedAt,
            endedAt: Int64(Date().timeIntervalSince1970 * 1000),
            // 형식을 정하지 않은 것이 의도다 — 임계값을 새로 추가한 사람이 여기를
            // 고쳐야 하는 줄 모르는 상황을 막는다.
            formThresholds: String(describing: thresholds)
        )

        let reps = recorded.map { item -> RepRecord in
            let rep = item.rep
            let checks = RepScorer.checksFor(rep.summary.cameraAngle)
            return RepRecord(
                id: UUID().uuidString,
                setId: "",                       // 저장 시점에 채워진다
                repNumber: rep.summary.repIndex,
                recordedAt: item.recordedAt,
                durationMs: rep.summary.durationMs,
                depthScore: rep.score.depthScore.map(Double.init),
                formScore: nil,                  // ⚠ 항상 nil — 점수 대신 사실을 센다
                checkedCount: rep.score.checkedCount,
                warnedCount: rep.score.warnedCount,
                isValid: true,
                errorFlags: RepRecordMapping.errorFlags(rep.warnings, checks: checks),
                cameraAngle: rep.summary.cameraAngle.rawValue,
                depthLevel: rep.depth?.rawValue,
                depthBasis: rep.depthBasis?.rawValue,
                depthRatio: rep.depthValue.map(Double.init),
                minKneeAngle: rep.summary.aggregate.minKneeAngle.map(Double.init),
                maxTorsoLean: rep.summary.aggregate.maxTorsoLeanDegrees.map(Double.init),
                validFrameRatio: Double(rep.summary.aggregate.validFrameRatio),
                kneeToeSide: rep.kneeToeSide?.rawValue,
                warningPhases: RepRecordMapping.phases(rep.warningPhases),
                // 어느 기준으로 판정했는지를 rep마다 남긴다 — 세션 도중에도 바뀔 수 있는 값이다.
                relaxedForm: relaxed,
                kneeTolerance: Double(thresholds.kneeToeToleranceRatio),
                shallowTolerance: Double(thresholds.shallowToleranceRatio)
            )
        }

        // 🔴 **대표값은 평균이 아니라 p95다.** 평균 10ms여도 20프레임에 한 번 60ms가
        //    걸리면 그 프레임에서 rep이 끊긴다. 화면에 띄우는 값(EMA)과 기록용 원표본은
        //    다른 것이라, p95는 `PerformanceSamples`가 따로 모은다.
        let samples = performanceSamples
        let metrics = samples.isEmpty ? nil : PerformanceMetrics(
            id: UUID().uuidString,
            sessionId: sessionId,
            modelLoadMs: modelLoadMs,
            avgInferenceMs: samples.averageMs,
            p95InferenceMs: samples.p95Ms,
            droppedFrameRatio: samples.droppedRatio,
            avgFps: snapshot.analysisFps,
            // 지금은 CPU 경로뿐이다. delegate를 붙이면 **측정한 뒤에** 이름이 바뀐다.
            delegateType: "cpu",
            analyzedFrameCount: samples.analyzed,
            createdAt: Int64(Date().timeIntervalSince1970 * 1000)
        )

        do {
            try repository.save(session: session, reps: reps, metrics: metrics)
            savedSessionId = sessionId
            return sessionId
        } catch {
            // 저장 실패가 운동 흐름을 막지 않는다. 사용자에게는 알린다.
            engineError = "기록을 저장하지 못했어요"
            return nil
        }
    }

    var canSave: Bool { !recorded.isEmpty }
}
