import CoreVideo
import Foundation
import PoseEngine

/// 한 프레임을 처리한 결과. **값 타입이라 스레드를 건너가도 안전하다.**
struct WorkoutSnapshot: Sendable {
    var pose: Pose?
    var frameWidth: Int = 0
    var frameHeight: Int = 0

    var stage: CalibrationStage = .none
    var prepRemainingMs: Int64 = 0
    var measureRemainingMs: Int64 = 0
    var calibrated = false
    var cameraAngle: CameraAngle = .side
    var readyIssues: [ReadyIssue] = []
    var calibrationProblems: [StandingCalibration.Problem] = []

    var countingEnabled = false
    var repCount = 0
    var repState: RepState = .idle
    var lastRepDepth: DepthLevel?
    var lastAbortReason: RepEvent.AbortReason?

    var heldWarnings: [HeldWarning] = []
    var depth: DepthLevel?
    var kneeAngle: Float?

    var inferenceMs: Double = 0
    var analysisFps: Double = 0
    var droppedFrames = 0
}

enum CalibrationStage: String, Sendable {
    case none, preparing, measuring, ready, failed
}

/// rep 하나가 끝났을 때 나오는 사실. 세션 리포트의 재료다.
struct CompletedRep: Sendable {
    let summary: RepSummary
    let warnings: Set<FormWarning>
    let score: RepScore
    let depth: DepthLevel?
    let kneeToeSide: Side?
}

/// 카메라 프레임 → 추론 → 특징 → 판정 → 카운팅.
///
/// 🔴 **판정 로직은 전부 여기(와 `PoseEngine`)에 있다. 화면에 두지 않는다** — 두면 화면이
/// 둘일 때 서로 다른 답을 낸다. Android가 사용자용·개발용 화면이 같은 ViewModel을 공유하게
/// 만든 이유가 이것이다.
///
/// 이 객체는 **전용 직렬 큐에서만** 동작한다. 결과는 값으로 복사해 메인으로 보낸다.
/// `@unchecked Sendable`: **모든 메서드는 호출부가 지정한 하나의 직렬 큐에서만 돈다.**
/// 이 규약을 깨고 두 스레드에서 부르면 경합이 생긴다.
final class PosePipeline: @unchecked Sendable {

    private let config = SquatAnalyzerConfig()
    private let analyzer: SquatFormAnalyzer
    private let counting: CountingThresholds
    private var engine: RTMPoseEngine?

    private let ema: AngleEma
    private var median: MedianWindow
    private let hold = FeedbackHold()
    private var stateMachine: RepStateMachine!

    private var stage: CalibrationStage = .none
    private var prepEndsMs: Int64 = 0
    private var measureEndsMs: Int64 = 0
    private var calibrationFrames: [(pose: Pose, aspectRatio: Float)] = []
    private var readyFrames: [(pose: Pose, aspectRatio: Float)] = []
    private var calibration: StandingCalibration?
    private var view: CaptureView = .sideLeft
    private var activeSide: Side?
    private var readyIssues: [ReadyIssue] = []
    private var calibrationProblems: [StandingCalibration.Problem] = []

    private var repCount = 0
    private var lastRepDepth: DepthLevel?
    private var lastAbortReason: RepEvent.AbortReason?
    private var frameWarningsInRep: Set<FormWarning> = []
    private var kneeOverToeInRep: [Float] = []
    private var depthAtBottom: DepthLevel?
    private var depthValueAtBottom: Float?
    private var depthBasisAtBottom: DepthBasis?
    private var kneeToeSideInRep: Side?

    private var droppedFrames = 0
    private var frameTimes: [Int64] = []
    private var lastInferenceMs: Double = 0

    /// 준비 시간. 설정으로 바뀐다 — 화면은 버튼 문구에만 쓴다.
    var prepSeconds: Int = 5
    /// 기준 자세 측정 창. 약 3초.
    private let measureMs: Int64 = 3_000
    /// 준비 자세는 최근 15프레임으로 실시간 갱신한다.
    private let readyWindow = 15

    var onSnapshot: (@Sendable (WorkoutSnapshot) -> Void)?
    var onRepCompleted: (@Sendable (CompletedRep) -> Void)?
    var onCue: (@Sendable (AudioCue) -> Void)?

    init() {
        analyzer = SquatFormAnalyzer(config: config)
        counting = .default
        ema = AngleEma(timeConstantMs: config.smoothing.emaTimeConstantMs)
        median = MedianWindow(size: MedianWindow.sizeFor(
            targetSpanMs: config.smoothing.medianWindowMs, fps: 30))
        stateMachine = RepStateMachine(thresholds: counting) { [weak self] in
            self?.view.cameraAngle ?? .side
        }
    }

    /// 반드시 백그라운드에서. 모델 로드가 수백 ms 걸린다.
    func loadEngine() throws {
        guard let url = RTMPoseEngine.bundledModelURL else {
            throw NSError(domain: "PosePipeline", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "모델이 번들에 없습니다"])
        }
        engine = try RTMPoseEngine(modelPath: url.path)
    }

    var modelName: String { engine?.modelName ?? "-" }

    // ── 기준 자세 ───────────────────────────────────────────

    func beginCalibration(nowMs: Int64) {
        stage = .preparing
        prepEndsMs = nowMs + Int64(prepSeconds) * 1000
        calibrationFrames.removeAll()
        calibrationProblems.removeAll()
        calibration = nil
        resetCounting()
    }

    func cancelCalibration() {
        stage = .none
        calibrationFrames.removeAll()
    }

    private func resetCounting() {
        stateMachine.reset()
        ema.reset()
        median.reset()
        hold.reset()
        repCount = 0
        lastRepDepth = nil
        lastAbortReason = nil
        clearRepAccumulators()
    }

    private func clearRepAccumulators() {
        frameWarningsInRep.removeAll()
        kneeOverToeInRep.removeAll()
        depthAtBottom = nil
        depthValueAtBottom = nil
        depthBasisAtBottom = nil
        kneeToeSideInRep = nil
    }

    // ── 프레임 ──────────────────────────────────────────────

    func process(_ packet: FramePacket) {
        let pixelBuffer = packet.pixelBuffer
        let timestampMs = packet.timestampMs
        guard let engine else { return }
        guard let pose = engine.analyze(pixelBuffer: pixelBuffer) else {
            droppedFrames += 1
            return
        }
        lastInferenceMs = Double(pose.inferenceTimeNanos) / 1e6
        trackFps(nowMs: timestampMs)

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let aspect = Float(width) / Float(height)

        advanceCalibration(pose: pose, aspect: aspect, nowMs: timestampMs)

        let features = FrameFeatures.from(
            pose: pose, aspectRatio: aspect, calibration: calibration,
            view: view, activeSide: activeSide, minConfidence: config.minConfidence
        )
        let form = analyzer.analyze(pose: pose, frameAspectRatio: aspect,
                                    cameraAngle: view.cameraAngle, features: features)

        // 🔴 **기준 자세를 다 잰 뒤에만 센다.** 걸어가며 자리를 잡는 동안 유령 rep이
        //    세어지던 문제 때문이다. 막는 대신 왜 안 세는지 숫자 아래에 알린다.
        let countingEnabled = (stage == .ready && calibration != nil)
        if countingEnabled {
            step(form: form, features: features, nowMs: timestampMs)
        }

        emit(pose: pose, width: width, height: height, form: form,
             countingEnabled: countingEnabled, nowMs: timestampMs)
    }

    private func advanceCalibration(pose: Pose, aspect: Float, nowMs: Int64) {
        switch stage {
        case .preparing:
            // 준비 시간 동안 준비 자세를 실시간으로 본다 — 카운트다운이 끝나기 전에
            // 사용자가 자기 위치를 고칠 수 있어야 한다.
            pushReady(pose: pose, aspect: aspect)
            if nowMs >= prepEndsMs {
                stage = .measuring
                measureEndsMs = nowMs + measureMs
                calibrationFrames.removeAll()
            }

        case .measuring:
            pushReady(pose: pose, aspect: aspect)
            calibrationFrames.append((pose: pose, aspectRatio: aspect))
            if nowMs >= measureEndsMs { finishCalibration() }

        case .none, .ready, .failed:
            if stage != .ready { pushReady(pose: pose, aspect: aspect) }
        }
    }

    private func pushReady(pose: Pose, aspect: Float) {
        readyFrames.append((pose: pose, aspectRatio: aspect))
        if readyFrames.count > readyWindow { readyFrames.removeFirst() }
        readyIssues = ReadyPosture.from(frames: readyFrames, cameraAngle: view.cameraAngle,
                                        form: config.form, ready: config.ready).issues
    }

    private func finishCalibration() {
        // 🔴 촬영 방향은 **측정 창의 다수결**로 정한다. 프레임 단위로 판별하면 실측
        //    오분류 0.5%가 rep 안에서 판정을 뒤집는다. 45도면 막는다.
        let estimated = CaptureQuality.estimateView(frames: calibrationFrames,
                                                    thresholds: config.angleDetection)
        guard let estimated, estimated != .ambiguous else {
            stage = .failed
            calibrationProblems = [.ambiguousView]
            onCue?(.failed)
            return
        }

        guard let made = StandingCalibration.from(frames: calibrationFrames) else {
            stage = .failed
            calibrationProblems = [.tooFewFrames]
            onCue?(.failed)
            return
        }
        let result = made.validate()
        calibrationProblems = result.problems
        guard result.passed else {
            stage = .failed
            onCue?(.failed)
            return
        }

        if estimated == .front {
            view = .front
            activeSide = nil
        } else {
            let side = StandingCalibration.nearerSide(frames: calibrationFrames) ?? .left
            view = side == .left ? .sideLeft : .sideRight
            activeSide = side
        }
        calibration = made
        stage = .ready
        resetCounting()
        onCue?(.calibrated)
    }

    // ── 판정·카운팅 ─────────────────────────────────────────

    private func step(form: SquatForm, features: FrameFeatures, nowMs: Int64) {
        let raw = form.kneeAngles.representative
        let smoothed = ema.update(raw, timestampMs: nowMs)
        let med = median.push(raw)

        let frame = RepFrame(
            timestampMs: nowMs,
            rawKneeAngle: raw,
            smoothedKneeAngle: smoothed,
            medianKneeAngle: med,
            leftKneeAngle: form.kneeAngles.left,
            rightKneeAngle: form.kneeAngles.right,
            hipAngle: form.hipAngles.representative,
            torsoLeanDegrees: form.torsoLeanDegrees,
            kneeAsymmetryDegrees: form.asymmetryDegrees,
            kneeSpreadRatio: form.kneeSpreadRatio,
            leftFoot: nil, rightFoot: nil,
            minLegConfidence: features.minConfidence
        )
        let event = stateMachine.update(frame)
        let inRep = stateMachine.state.isInRep

        // 🔴 **선 자세에서는 판정하지 않는다.** 임계값이 최저점 분포에서 나왔기 때문이다.
        //    게이트가 없어 "가만히 서 있어도 경고가 뜬다"는 신고가 있었다.
        if inRep {
            frameWarningsInRep.formUnion(form.warnings)
            if let value = form.kneeOverToe { kneeOverToeInRep.append(value) }
            if form.kneeAlignment != .good, let side = form.kneeToeSide {
                kneeToeSideInRep = side
            }
            if stateMachine.state == .bottom || depthAtBottom == nil {
                depthAtBottom = form.depth
                depthValueAtBottom = form.depthRatio ?? features.shinDepthRatio
                depthBasisAtBottom = form.depthBasis
            }
        }

        let visible = inRep ? form.warnings : []
        _ = hold.update(warnings: visible, side: form.kneeToeSide, nowMs: nowMs)

        guard let event else { return }
        switch event {
        case .started:
            clearRepAccumulators()
        case .aborted(_, let reason, _):
            lastAbortReason = reason
            clearRepAccumulators()
        case .completed(let summary):
            complete(summary: summary, nowMs: nowMs)
        }
    }

    private func complete(summary: RepSummary, nowMs: Int64) {
        let kneePastToe = config.form.kneePastToe(of: kneeOverToeInRep)
        let warnings = RepWarnings.of(frameWarnings: frameWarningsInRep,
                                      depth: depthAtBottom, kneePastToe: kneePastToe)
        let score = RepScorer.score(cameraAngle: summary.cameraAngle, warnings: warnings,
                                    depthValue: depthValueAtBottom,
                                    depthBasis: depthBasisAtBottom, thresholds: config.form)
        repCount = stateMachine.completedReps
        lastRepDepth = depthAtBottom
        lastAbortReason = nil

        // rep 단위 경고는 **다 일어선 뒤**에 떠야 읽힌다. 그 자리가 2초 hold가 겨냥한 곳이다.
        let repLevel = warnings.filter(\.isRepLevel)
        if !repLevel.isEmpty {
            _ = hold.update(warnings: Array(repLevel), side: kneeToeSideInRep, nowMs: nowMs)
        }
        // rep 끝에 **한 번만** 울린다. 인정/경고가 서로 구분되는 짝이어야 한다.
        onCue?(score.warnedCount > 0 ? .repWarned : .repDone)

        onRepCompleted?(CompletedRep(summary: summary, warnings: warnings, score: score,
                                     depth: depthAtBottom, kneeToeSide: kneeToeSideInRep))
        clearRepAccumulators()
    }

    // ── 보고 ────────────────────────────────────────────────

    private func trackFps(nowMs: Int64) {
        frameTimes.append(nowMs)
        if frameTimes.count > 30 { frameTimes.removeFirst() }
    }

    private var fps: Double {
        guard frameTimes.count >= 2, let first = frameTimes.first, let last = frameTimes.last,
              last > first else { return 0 }
        return Double(frameTimes.count - 1) * 1000 / Double(last - first)
    }

    private func emit(pose: Pose, width: Int, height: Int, form: SquatForm,
                      countingEnabled: Bool, nowMs: Int64) {
        var snapshot = WorkoutSnapshot()
        snapshot.pose = pose
        snapshot.frameWidth = width
        snapshot.frameHeight = height
        snapshot.stage = stage
        snapshot.prepRemainingMs = max(0, prepEndsMs - nowMs)
        snapshot.measureRemainingMs = max(0, measureEndsMs - nowMs)
        snapshot.calibrated = calibration != nil
        snapshot.cameraAngle = view.cameraAngle
        snapshot.readyIssues = readyIssues
        snapshot.calibrationProblems = calibrationProblems
        snapshot.countingEnabled = countingEnabled
        snapshot.repCount = repCount
        snapshot.repState = stateMachine.state
        snapshot.lastRepDepth = lastRepDepth
        snapshot.lastAbortReason = lastAbortReason
        snapshot.heldWarnings = hold.update(warnings: [], side: nil, nowMs: nowMs)
        snapshot.depth = form.depth
        snapshot.kneeAngle = form.kneeAngles.representative
        snapshot.inferenceMs = lastInferenceMs
        snapshot.analysisFps = fps
        snapshot.droppedFrames = droppedFrames
        onSnapshot?(snapshot)
    }
}
