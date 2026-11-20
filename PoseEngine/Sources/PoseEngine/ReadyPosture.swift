import Foundation

/// 준비 자세 점검 항목 5종.
///
/// **동작 경고(``FormWarning``)와 다른 열거형이다** — 재는 순간(동작 전/중)과
/// 분모(세션당 1회 / rep마다)가 다르다.
public enum ReadyCheck: String, Sendable, CaseIterable {
    case facing, kneeStraight, stanceWidth, toeDirection, weightBalance
}

/// 준비 자세에서 걸린 문제.
///
/// 🔴 **전부 막는 항목이다.** 오탐하면 사용자가 앱을 **아예 쓸 수 없다.**
/// ⚠ 발 간격(`stanceTooNarrow`/`stanceTooWide`)은 막는 판정 중 유일하게 허용폭이
/// `provisional`이다. "시작이 안 된다"는 신고가 오면 **여기를 먼저 본다.**
public enum ReadyIssue: String, Sendable, CaseIterable {
    case turnToFront, turnToSide, faceSquarely
    case kneesBent
    case stanceTooNarrow, stanceTooWide
    case toesInward
    case weightOnOneSide

    public var check: ReadyCheck {
        switch self {
        case .turnToFront, .turnToSide, .faceSquarely: .facing
        case .kneesBent: .kneeStraight
        case .stanceTooNarrow, .stanceTooWide: .stanceWidth
        case .toesInward: .toeDirection
        case .weightOnOneSide: .weightBalance
        }
    }

    public var blocking: Bool { true }

    /// 선언 순서. Kotlin `ordinal`에 대응한다.
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// 기준 자세 측정을 시작해도 되는지 보는 사전 점검.
///
/// 실시간으로 갱신되고(최근 15프레임), **결과를 저장하지 않는다** — 허용폭이 잠정값인
/// 상태로 컬럼을 만들면 재계산할 수 없는 판정이 쌓인다.
public struct ReadyPosture: Sendable, Equatable {
    /// `발목 간격 / 어깨 너비`. 기준점이 1.0이다.
    public let stanceWidthByShoulder: Float?
    public let hipShiftRatio: Float?
    public let leftToeDirection: Float?
    public let rightToeDirection: Float?
    public let standingKneeFlexion: Float?
    public let estimatedView: CaptureQuality.EstimatedView?
    public let issues: [ReadyIssue]
    public let notJudged: [ReadyCheck: NotJudgedReason]
    public let framesUsed: Int

    /// **못 본 항목은 통과로 본다** — 안 그러면 측면 촬영으로는 영원히 시작할 수 없다.
    public var judged: Set<ReadyCheck> {
        Set(ReadyCheck.allCases).subtracting(notJudged.keys)
    }

    public var clean: Bool { framesUsed > 0 && !judged.isEmpty && issues.isEmpty }
    public var topIssue: ReadyIssue? { issues.first }
    public var blockingIssues: [ReadyIssue] { issues.filter(\.blocking) }
    public var readyToMeasure: Bool {
        framesUsed > 0 && !judged.isEmpty && blockingIssues.isEmpty
    }

    public enum NotJudgedReason: String, Sendable, CaseIterable {
        case cameraAngle, keypoints
    }

    public static let empty = ReadyPosture(
        stanceWidthByShoulder: nil, hipShiftRatio: nil,
        leftToeDirection: nil, rightToeDirection: nil, standingKneeFlexion: nil,
        estimatedView: nil, issues: [], notJudged: [:], framesUsed: 0
    )

    public static func from(
        frames: [(pose: Pose, aspectRatio: Float)],
        cameraAngle: CameraAngle,
        form: FormThresholds = FormThresholds(),
        ready: ReadyThresholds = ReadyThresholds(),
        minConfidence: Float = StandingCalibration.minConfidence
    ) -> ReadyPosture {
        if frames.isEmpty { return .empty }
        let front = cameraAngle == .front
        let samples = frames.map {
            measure(pose: $0.pose, aspect: $0.aspectRatio, front: front,
                    form: form, ready: ready, minConfidence: minConfidence)
        }
        let stance = median(samples.compactMap(\.stanceWidth))
        let hipShift = median(samples.compactMap(\.hipShift))
        let leftToe = median(samples.compactMap(\.leftToe))
        let rightToe = median(samples.compactMap(\.rightToe))
        let kneeFlexion = median(samples.compactMap(\.kneeFlexion))

        var viewCounts: [CaptureQuality.EstimatedView: Int] = [:]
        for sample in samples { if let view = sample.view { viewCounts[view, default: 0] += 1 } }
        let view = CaptureQuality.EstimatedView.allCases
            .filter { viewCounts[$0] != nil }
            .max { (viewCounts[$0] ?? 0) < (viewCounts[$1] ?? 0) }

        let facingIssue = facingIssue(cameraAngle: cameraAngle, view: view)
        var issues: [ReadyIssue] = []
        if let facingIssue { issues.append(facingIssue) }
        if let kneeFlexion, kneeFlexion > ready.maxStandingKneeFlexion { issues.append(.kneesBent) }
        // 방향이 어긋난 상태에서는 나머지 정면 전용 판정이 의미가 없다.
        if facingIssue == nil {
            if let stance {
                if stance < ready.stanceNarrowLimit { issues.append(.stanceTooNarrow) }
                else if stance > ready.stanceWideLimit { issues.append(.stanceTooWide) }
            }
            if [leftToe, rightToe].compactMap({ $0 }).contains(where: { $0 < 0 }) {
                issues.append(.toesInward)
            }
            if let hipShift, abs(hipShift) > form.hipShiftLimit { issues.append(.weightOnOneSide) }
        }
        issues.sort { $0.order < $1.order }

        return ReadyPosture(
            stanceWidthByShoulder: stance,
            hipShiftRatio: hipShift,
            leftToeDirection: leftToe,
            rightToeDirection: rightToe,
            standingKneeFlexion: kneeFlexion,
            estimatedView: view,
            issues: issues,
            notJudged: notJudged(
                front: front, facingMismatch: facingIssue != nil, view: view,
                stance: stance, toes: [leftToe, rightToe].compactMap { $0 },
                hipShift: hipShift, kneeFlexion: kneeFlexion
            ),
            framesUsed: frames.count
        )
    }

    // ── 내부 ────────────────────────────────────────────────

    private static func facingIssue(
        cameraAngle: CameraAngle, view: CaptureQuality.EstimatedView?
    ) -> ReadyIssue? {
        guard let view else { return nil }
        if view == .ambiguous { return .faceSquarely }
        if cameraAngle == .front && view == .side { return .turnToFront }
        if cameraAngle == .side && view == .front { return .turnToSide }
        return nil
    }

    private static func notJudged(
        front: Bool, facingMismatch: Bool, view: CaptureQuality.EstimatedView?,
        stance: Float?, toes: [Float], hipShift: Float?, kneeFlexion: Float?
    ) -> [ReadyCheck: NotJudgedReason] {
        var result: [ReadyCheck: NotJudgedReason] = [:]
        if view == nil { result[.facing] = .keypoints }
        if kneeFlexion == nil { result[.kneeStraight] = .keypoints }

        let frontReason: NotJudgedReason? = (!front || facingMismatch) ? .cameraAngle : nil
        func frontCheck(_ check: ReadyCheck, measured: Bool) {
            if let frontReason { result[check] = frontReason }
            else if !measured { result[check] = .keypoints }
        }
        frontCheck(.stanceWidth, measured: stance != nil)
        frontCheck(.toeDirection, measured: !toes.isEmpty)
        frontCheck(.weightBalance, measured: hipShift != nil)
        return result
    }

    private struct Sample {
        let stanceWidth, hipShift, leftToe, rightToe, kneeFlexion: Float?
        let view: CaptureQuality.EstimatedView?
    }

    private static func measure(
        pose: Pose, aspect: Float, front: Bool,
        form: FormThresholds, ready: ReadyThresholds, minConfidence: Float
    ) -> Sample {
        func p(_ type: KeypointType) -> Point2 { Geometry.point(pose, type, aspectRatio: aspect) }
        func ok(_ type: KeypointType) -> Bool { pose.isReliable(type, minConfidence: minConfidence) }

        let ankleSpread: Float? = (ok(.leftAnkle) && ok(.rightAnkle))
            ? Geometry.distance(p(.leftAnkle), p(.rightAnkle)) : nil
        // 두 발이 겹치면 분모가 무너진다.
        let usableSpread = ankleSpread.flatMap { $0 >= form.minStanceWidth ? $0 : nil }
        let shoulderWidth: Float? = (ok(.leftShoulder) && ok(.rightShoulder))
            ? Geometry.distance(p(.leftShoulder), p(.rightShoulder)) : nil

        var stanceWidth: Float?
        if front, let usableSpread, let shoulderWidth, shoulderWidth > Geometry.epsilon {
            stanceWidth = usableSpread / shoulderWidth
        }

        let hipCenter: Point2? = (ok(.leftHip) && ok(.rightHip))
            ? Geometry.midpoint(p(.leftHip), p(.rightHip)) : nil
        let ankleCenter: Point2? = ankleSpread != nil
            ? Geometry.midpoint(p(.leftAnkle), p(.rightAnkle)) : nil

        var hipShift: Float?
        if front, let hipCenter, let ankleCenter, let usableSpread {
            hipShift = (hipCenter.x - ankleCenter.x) / usableSpread
        }

        /// 발끝이 바깥을 향하면 양수. 음수면 안쪽을 향한 것이다.
        func toeDirection(_ side: Side) -> Float? {
            guard front else { return nil }
            let heel = Geometry.heel(side)
            guard ok(heel),
                  let toe = Geometry.toeCenter(pose, side, aspectRatio: aspect,
                                               minConfidence: minConfidence),
                  let footLength = Geometry.footLength(pose, side, aspectRatio: aspect,
                                                       minConfidence: minConfidence),
                  let legLength = legLength(pose: pose, side: side, aspect: aspect,
                                            minConfidence: minConfidence) else { return nil }
            // 발이 너무 짧게 잡히면(원근으로 압축) 방향을 믿을 수 없다.
            guard footLength / legLength >= ready.minFootLengthRatio else { return nil }
            let outwardSign: Float = side == .left ? 1 : -1
            return (toe.x - p(heel).x) * outwardSign / footLength
        }

        let kneeFlexion = Side.allCases.compactMap {
            Geometry.kneeFlexion(pose, $0, aspectRatio: aspect, minConfidence: minConfidence)
        }.max()

        return Sample(
            stanceWidth: stanceWidth, hipShift: hipShift,
            leftToe: toeDirection(.left), rightToe: toeDirection(.right),
            kneeFlexion: kneeFlexion,
            view: CaptureQuality.estimateView(pose: pose, aspectRatio: aspect,
                                              minConfidence: minConfidence)
        )
    }

    private static func legLength(
        pose: Pose, side: Side, aspect: Float, minConfidence: Float
    ) -> Float? {
        let joints = [Geometry.hip(side), Geometry.knee(side), Geometry.ankle(side)]
        guard joints.allSatisfy({ pose.isReliable($0, minConfidence: minConfidence) }) else {
            return nil
        }
        func p(_ type: KeypointType) -> Point2 { Geometry.point(pose, type, aspectRatio: aspect) }
        let length = Geometry.distance(p(joints[0]), p(joints[1]))
            + Geometry.distance(p(joints[1]), p(joints[2]))
        return length > Geometry.epsilon ? length : nil
    }

    static func median(_ values: [Float]) -> Float? {
        if values.isEmpty { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }
}
