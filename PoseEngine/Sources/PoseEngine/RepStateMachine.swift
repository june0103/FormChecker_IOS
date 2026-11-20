import Foundation

public enum RepState: String, Sendable, CaseIterable {
    case idle, standing, descending, bottom, ascending

    public var isInRep: Bool {
        switch self {
        case .descending, .bottom, .ascending: true
        case .idle, .standing: false
        }
    }
}

public enum RepEvent: Sendable {
    case started(repIndex: Int, timestampMs: Int64)
    case completed(RepSummary)
    case aborted(repIndex: Int, reason: AbortReason, timestampMs: Int64)

    public enum AbortReason: String, Sendable, CaseIterable {
        case notDeepEnough, tooFast, timeout, poseLost
    }
}

/// 상태머신 한 프레임 입력.
public struct RepFrame: Sendable {
    public let timestampMs: Int64
    /// 스무딩 전 각도. nil이면 **포즈 소실**로 본다.
    public let rawKneeAngle: Float?
    /// EMA. **상태 전이의 입력**이다.
    public let smoothedKneeAngle: Float?
    /// 중앙값 창. **극값(최저점) 탐색의 입력**이다 — EMA는 위상 지연이 있어 최저점이 밀린다.
    public let medianKneeAngle: Float?
    public let leftKneeAngle: Float?
    public let rightKneeAngle: Float?
    public let hipAngle: Float?
    public let torsoLeanDegrees: Float?
    public let kneeAsymmetryDegrees: Float?
    public let kneeSpreadRatio: Float?
    public let leftFoot: FootSample?
    public let rightFoot: FootSample?
    public let minLegConfidence: Float

    public init(
        timestampMs: Int64, rawKneeAngle: Float?, smoothedKneeAngle: Float?,
        medianKneeAngle: Float?, leftKneeAngle: Float? = nil, rightKneeAngle: Float? = nil,
        hipAngle: Float? = nil, torsoLeanDegrees: Float? = nil,
        kneeAsymmetryDegrees: Float? = nil, kneeSpreadRatio: Float? = nil,
        leftFoot: FootSample? = nil, rightFoot: FootSample? = nil, minLegConfidence: Float = 1
    ) {
        self.timestampMs = timestampMs
        self.rawKneeAngle = rawKneeAngle
        self.smoothedKneeAngle = smoothedKneeAngle
        self.medianKneeAngle = medianKneeAngle
        self.leftKneeAngle = leftKneeAngle
        self.rightKneeAngle = rightKneeAngle
        self.hipAngle = hipAngle
        self.torsoLeanDegrees = torsoLeanDegrees
        self.kneeAsymmetryDegrees = kneeAsymmetryDegrees
        self.kneeSpreadRatio = kneeSpreadRatio
        self.leftFoot = leftFoot
        self.rightFoot = rightFoot
        self.minLegConfidence = minLegConfidence
    }
}

/// rep 카운팅 상태머신.
///
/// ```
/// idle ──(≥155°)──▶ standing ──(<145°)──▶ descending
///                      ▲                       │
///                      │                  (<130°)
///                      │                       ▼
///                      └──(≥155°)── ascending ◀─▶ bottom
///                                      (≥130°)
/// ```
///
/// **얕은 스쿼트도 센다.** 세지 않으면 사용자에게는 카운터가 멈춘 것처럼 보인다 —
/// 세고, 경고한다.
public final class RepStateMachine {

    private let thresholds: CountingThresholds
    private let cameraAngle: () -> CameraAngle

    public private(set) var state: RepState = .idle
    public private(set) var completedReps = 0

    private var repIndex = 0
    private var pendingState: RepState?
    private var pendingSinceMs: Int64 = 0
    private var lastMissingStartMs: Int64?
    private var repStartMs: Int64 = 0
    private var frameCountInRep = 0
    private var validFrameCountInRep = 0
    private var minKnee: Float?
    private var maxKnee: Float?
    private var minHip: Float?
    private var maxHip: Float?
    private var maxTorsoLean: Float?
    private var maxAngularVelocity: Float?
    private var previousAngle: Float?
    private var previousAngleMs: Int64?
    private var reachedBottom = false
    private var topPosture: RepPosture?
    private var bottomPosture: RepPosture?
    private var bottomMedianAngle: Float?

    public init(
        thresholds: CountingThresholds = .default,
        cameraAngle: @escaping () -> CameraAngle = { .side }
    ) {
        self.thresholds = thresholds
        self.cameraAngle = cameraAngle
    }

    public func update(_ frame: RepFrame) -> RepEvent? {
        guard frame.rawKneeAngle != nil else { return handleMissing(nowMs: frame.timestampMs) }
        lastMissingStartMs = nil
        guard let angle = frame.smoothedKneeAngle else { return nil }

        if state != .idle && state != .standing {
            accumulate(frame)
            if let event = timeoutCheck(nowMs: frame.timestampMs) { return event }
        }

        switch state {
        case .idle:
            if settled(.standing, angle >= thresholds.standingEnterAngle, nowMs: frame.timestampMs) {
                state = .standing
                captureTop(frame)
            }
            return nil

        case .standing:
            if angle > (topPosture?.kneeAngle ?? -.greatestFiniteMagnitude) { captureTop(frame) }
            if settled(.descending, angle < thresholds.standingExitAngle, nowMs: frame.timestampMs) {
                startRep(frame)
                return .started(repIndex: repIndex, timestampMs: frame.timestampMs)
            }
            return nil

        case .descending:
            updateBottomCandidate(frame)
            if settled(.bottom, angle < thresholds.repBottomAngle, nowMs: frame.timestampMs) {
                state = .bottom
                reachedBottom = true
                return nil
            }
            if settled(.standing, angle >= thresholds.standingEnterAngle, nowMs: frame.timestampMs) {
                return abort(.notDeepEnough, nowMs: frame.timestampMs)
            }
            return nil

        case .bottom:
            updateBottomCandidate(frame)
            if settled(.ascending, angle >= thresholds.repBottomAngle, nowMs: frame.timestampMs) {
                state = .ascending
            }
            return nil

        case .ascending:
            if settled(.standing, angle >= thresholds.standingEnterAngle, nowMs: frame.timestampMs) {
                return completeRep(frame)
            }
            if settled(.bottom, angle < thresholds.repBottomAngle, nowMs: frame.timestampMs) {
                state = .bottom
            }
            return nil
        }
    }

    public func reset() {
        state = .idle
        pendingState = nil
        lastMissingStartMs = nil
        clearRep()
        topPosture = nil
    }

    // ── 내부 ────────────────────────────────────────────────

    /// 조건이 `minHoldMs` 동안 유지돼야 전이한다 — 노이즈로 상태가 진동하지 않게.
    private func settled(_ target: RepState, _ condition: Bool, nowMs: Int64) -> Bool {
        guard condition else {
            if pendingState == target { pendingState = nil }
            return false
        }
        if pendingState != target {
            pendingState = target
            pendingSinceMs = nowMs
            return thresholds.minHoldMs <= 0
        }
        return nowMs - pendingSinceMs >= thresholds.minHoldMs
    }

    private func handleMissing(nowMs: Int64) -> RepEvent? {
        let since = lastMissingStartMs ?? {
            lastMissingStartMs = nowMs
            return nowMs
        }()
        if state == .idle || state == .standing {
            if nowMs - since >= thresholds.maxMissingMs { state = .idle }
            return nil
        }
        if nowMs - since >= thresholds.maxMissingMs {
            return abort(.poseLost, nowMs: nowMs)
        }
        frameCountInRep += 1
        return nil
    }

    private func timeoutCheck(nowMs: Int64) -> RepEvent? {
        nowMs - repStartMs > thresholds.maxRepDurationMs ? abort(.timeout, nowMs: nowMs) : nil
    }

    private func startRep(_ frame: RepFrame) {
        repIndex += 1
        state = .descending
        repStartMs = frame.timestampMs
        clearRepAccumulators()
        accumulate(frame)
    }

    private func accumulate(_ frame: RepFrame) {
        frameCountInRep += 1
        validFrameCountInRep += 1
        guard let angle = frame.medianKneeAngle ?? frame.smoothedKneeAngle else { return }
        minKnee = minOfNullable(minKnee, angle)
        maxKnee = maxOfNullable(maxKnee, angle)
        if let hip = frame.hipAngle {
            minHip = minOfNullable(minHip, hip)
            maxHip = maxOfNullable(maxHip, hip)
        }
        if let lean = frame.torsoLeanDegrees { maxTorsoLean = maxOfNullable(maxTorsoLean, lean) }

        if let prev = previousAngle, let prevMs = previousAngleMs {
            let dtSec = Double(frame.timestampMs - prevMs) / 1000.0
            if dtSec > 0 {
                let velocity = Float(Double(abs(angle - prev)) / dtSec)
                maxAngularVelocity = maxOfNullable(maxAngularVelocity, velocity)
            }
        }
        previousAngle = angle
        previousAngleMs = frame.timestampMs
    }

    private func updateBottomCandidate(_ frame: RepFrame) {
        guard let median = frame.medianKneeAngle else { return }
        if bottomMedianAngle == nil || median < bottomMedianAngle! {
            bottomMedianAngle = median
            bottomPosture = posture(from: frame, frameIndex: frameCountInRep)
        }
    }

    private func captureTop(_ frame: RepFrame) {
        topPosture = posture(from: frame, frameIndex: 0)
    }

    private func completeRep(_ frame: RepFrame) -> RepEvent {
        let duration = frame.timestampMs - repStartMs
        if !reachedBottom { return abort(.notDeepEnough, nowMs: frame.timestampMs) }
        if duration < thresholds.minRepDurationMs { return abort(.tooFast, nowMs: frame.timestampMs) }

        let bottom = bottomPosture
        let summary = RepSummary(
            repIndex: repIndex,
            startTimeMs: repStartMs,
            endTimeMs: frame.timestampMs,
            aggregate: RepAggregate(
                minKneeAngle: minKnee,
                maxKneeAngle: maxKnee,
                minHipAngle: minHip,
                maxHipAngle: maxHip,
                maxTorsoLeanDegrees: maxTorsoLean,
                descentDurationMs: bottom.map { $0.timestampMs - repStartMs },
                ascentDurationMs: bottom.map { frame.timestampMs - $0.timestampMs },
                maxAngularVelocityDegPerSec: maxAngularVelocity,
                validFrameRatio: frameCountInRep > 0
                    ? Float(validFrameCountInRep) / Float(frameCountInRep) : 0,
                analyzedFrameCount: frameCountInRep
            ),
            top: topPosture,
            bottom: bottom,
            cameraAngle: cameraAngle()
        )
        state = .standing
        completedReps += 1
        clearRep()
        captureTop(frame)
        return .completed(summary)
    }

    private func abort(_ reason: RepEvent.AbortReason, nowMs: Int64) -> RepEvent {
        let index = repIndex
        state = reason == .poseLost ? .idle : .standing
        clearRep()
        return .aborted(repIndex: index, reason: reason, timestampMs: nowMs)
    }

    private func clearRep() {
        clearRepAccumulators()
        bottomPosture = nil
        bottomMedianAngle = nil
        pendingState = nil
    }

    private func clearRepAccumulators() {
        frameCountInRep = 0
        validFrameCountInRep = 0
        minKnee = nil; maxKnee = nil; minHip = nil; maxHip = nil
        maxTorsoLean = nil; maxAngularVelocity = nil
        previousAngle = nil; previousAngleMs = nil
        reachedBottom = false
    }

    private func posture(from frame: RepFrame, frameIndex: Int) -> RepPosture {
        RepPosture(
            frameIndex: frameIndex,
            timestampMs: frame.timestampMs,
            kneeAngle: frame.medianKneeAngle ?? frame.smoothedKneeAngle,
            leftKneeAngle: frame.leftKneeAngle,
            rightKneeAngle: frame.rightKneeAngle,
            hipAngle: frame.hipAngle,
            torsoLeanDegrees: frame.torsoLeanDegrees,
            kneeAsymmetryDegrees: frame.kneeAsymmetryDegrees,
            kneeSpreadRatio: frame.kneeSpreadRatio,
            leftFoot: frame.leftFoot,
            rightFoot: frame.rightFoot,
            minLegConfidence: frame.minLegConfidence,
            framesUsed: 1
        )
    }

    private func minOfNullable(_ current: Float?, _ value: Float) -> Float {
        guard let current else { return value }
        return value < current ? value : current
    }

    private func maxOfNullable(_ current: Float?, _ value: Float) -> Float {
        guard let current else { return value }
        return value > current ? value : current
    }
}
