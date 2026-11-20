import Foundation

/// 선 자세에서 잰 기준선.
///
/// **정규화된 특징(깊이 비율, 상체 숙임, 뒤꿈치 들림)은 전부 이 값을 분모로 쓴다.**
/// 없으면 그 특징을 계산할 수 없다 — 각도만으로는 대체되지 않는다.
public struct StandingCalibration: Sendable, Equatable {
    public let femurLength: Float
    public let tibiaLength: Float
    public let hipWidth: Float
    public let shoulderWidth: Float
    public let trunkLength: Float
    public let footLength: Float
    public let standingKneeFlexion: Float
    public let standingAnkleAngle: Float
    public let standingHipY: Float
    public let standingHeelY: Float
    public let standingLeftHeelLift: Float?
    public let standingRightHeelLift: Float?
    public let framesUsed: Int
    /// 측정 중 떨림. 크면 사람이 움직였다는 뜻이다.
    public let jitter: Float

    public var legLength: Float { femurLength + tibiaLength }

    public func standingHeelLift(_ side: Side) -> Float? {
        side == .left ? standingLeftHeelLift : standingRightHeelLift
    }

    /// 발 가시성 게이트의 재료 (발 길이 / 정강이).
    public var footTibiaRatio: Float {
        tibiaLength > Geometry.epsilon ? footLength / tibiaLength : 0
    }

    public var femurTibiaRatio: Float { femurLength / tibiaLength }

    // ── 측정 ────────────────────────────────────────────────

    public static let required: [KeypointType] = [
        .leftShoulder, .rightShoulder, .leftHip, .rightHip,
        .leftKnee, .rightKnee, .leftAnkle, .rightAnkle,
    ]

    /// 기준 자세 측정 창의 프레임들로 기준선을 만든다.
    ///
    /// - Parameter frames: (포즈, 프레임 종횡비) 쌍.
    /// - Returns: 쓸 만한 프레임이 `minFrames`에 못 미치면 nil.
    public static func from(
        frames: [(pose: Pose, aspectRatio: Float)],
        minConfidence: Float = StandingCalibration.minConfidence,
        minFrames: Int = StandingCalibration.minFrames
    ) -> StandingCalibration? {
        let usable = frames.filter { entry in
            required.allSatisfy { entry.pose.isReliable($0, minConfidence: minConfidence) }
        }
        guard usable.count >= minFrames else { return nil }

        let samples = usable.map {
            measure(pose: $0.pose, aspect: $0.aspectRatio, minConfidence: minConfidence)
        }
        return StandingCalibration(
            femurLength: average(samples.map(\.femur)),
            tibiaLength: average(samples.map(\.tibia)),
            hipWidth: average(samples.map(\.hipWidth)),
            shoulderWidth: average(samples.map(\.shoulderWidth)),
            trunkLength: average(samples.map(\.trunkLength)),
            footLength: average(samples.map(\.footLength)),
            standingKneeFlexion: average(samples.map(\.kneeFlexion)),
            standingAnkleAngle: average(samples.map(\.ankleAngle)),
            standingHipY: average(samples.map(\.hipY)),
            standingHeelY: average(samples.map(\.heelY)),
            standingLeftHeelLift: averageOrNil(samples.compactMap(\.leftHeelLift)),
            standingRightHeelLift: averageOrNil(samples.compactMap(\.rightHeelLift)),
            framesUsed: samples.count,
            jitter: jitter(of: samples)
        )
    }

    /// 카메라에 가까운 쪽. **측면 판정은 이 한쪽만 본다.**
    public static func nearerSide(frames: [(pose: Pose, aspectRatio: Float)]) -> Side? {
        if frames.isEmpty { return nil }
        func meanConfidence(_ side: Side) -> Double {
            let joints = [Geometry.hip(side), Geometry.knee(side), Geometry.ankle(side)]
            let total = frames.reduce(0.0) { sum, entry in
                sum + joints.reduce(0.0) { $0 + Double(entry.pose[$1].confidence) } / Double(joints.count)
            }
            return total / Double(frames.count)
        }
        return meanConfidence(.left) >= meanConfidence(.right) ? .left : .right
    }

    // ── 검증 ────────────────────────────────────────────────

    public func validate() -> Result {
        var problems: [Problem] = []
        if framesUsed < Self.minFrames { problems.append(.tooFewFrames) }
        if legLength < Self.minLegLength { problems.append(.subjectTooSmall) }
        if jitter > Self.maxJitter { problems.append(.unstable) }
        if standingKneeFlexion > Self.maxStandingFlexion { problems.append(.notStandingStraight) }
        if footLength <= 0 { problems.append(.footNotVisible) }
        return Result(problems: problems)
    }

    public struct Result: Sendable, Equatable {
        public let problems: [Problem]
        public var passed: Bool { !problems.contains { $0.blocking } }
    }

    public enum Problem: String, Sendable, CaseIterable {
        case tooFewFrames, subjectTooSmall, unstable, notStandingStraight, ambiguousView, footNotVisible

        /// 측정을 막는가. **발이 안 보이는 것은 막지 않는다** — 발 관련 항목만 빠진다.
        public var blocking: Bool { self != .footNotVisible }

        public var message: String {
            switch self {
            case .tooFewFrames: "자세를 유지한 시간이 짧았어요 — 다시 해볼까요?"
            case .subjectTooSmall: "카메라를 더 가까이 두세요 — 머리부터 발까지 화면에 크게 담겨야 해요"
            case .unstable: "움직임이 있었어요 — 잠깐 그대로 서 계세요"
            case .notStandingStraight: "무릎을 곧게 펴고 서 주세요"
            case .ambiguousView: "카메라를 똑바로 마주 보거나 옆으로 서 주세요 (지금은 비스듬해요)"
            case .footNotVisible: "발이 보이지 않습니다 — 발 관련 항목은 기록되지 않습니다"
            }
        }
    }

    // ── 상수 ────────────────────────────────────────────────

    /// 프레임 판정(0.3)보다 높다 — 기준선이 틀리면 모든 특징이 틀린다.
    public static let minConfidence: Float = 0.5
    public static let minFrames = 20
    static let minLegLength: Float = 0.15
    static let maxJitter: Float = 0.01
    public static let maxStandingFlexion: Float = 20

    // ── 내부 ────────────────────────────────────────────────

    private struct Sample {
        let femur, tibia, hipWidth, shoulderWidth, trunkLength, footLength: Float
        let kneeFlexion, ankleAngle, hipY, heelY: Float
        let leftHeelLift, rightHeelLift: Float?
    }

    private static func measure(pose: Pose, aspect: Float, minConfidence: Float) -> Sample {
        func p(_ type: KeypointType) -> Point2 {
            Geometry.point(pose, type, aspectRatio: aspect)
        }
        let leftFemur = Geometry.distance(p(.leftHip), p(.leftKnee))
        let rightFemur = Geometry.distance(p(.rightHip), p(.rightKnee))
        let leftTibia = Geometry.distance(p(.leftKnee), p(.leftAnkle))
        let rightTibia = Geometry.distance(p(.rightKnee), p(.rightAnkle))
        let shoulderCenter = Geometry.midpoint(p(.leftShoulder), p(.rightShoulder))
        let hipCenter = Geometry.midpoint(p(.leftHip), p(.rightHip))

        let footLengths = Side.allCases.compactMap {
            Geometry.footLength(pose, $0, aspectRatio: aspect, minConfidence: minConfidence)
        }
        let kneeFlexions = Side.allCases.compactMap {
            Geometry.kneeFlexion(pose, $0, aspectRatio: aspect, minConfidence: minConfidence)
        }
        let ankleAngles = Side.allCases.compactMap {
            Geometry.ankleAngle(pose, $0, aspectRatio: aspect, minConfidence: minConfidence)
        }
        let heels = [KeypointType.leftHeel, .rightHeel]
            .filter { pose.isReliable($0, minConfidence: minConfidence) }
            .map(\.self).map { pose[$0].y }

        func heelLift(_ side: Side) -> Float? {
            let heel = Geometry.heel(side)
            guard pose.isReliable(heel, minConfidence: minConfidence),
                  let toe = Geometry.toeCenter(pose, side, aspectRatio: aspect,
                                               minConfidence: minConfidence) else { return nil }
            return toe.y - pose[heel].y
        }

        return Sample(
            femur: (leftFemur + rightFemur) / 2,
            tibia: (leftTibia + rightTibia) / 2,
            hipWidth: Geometry.distance(p(.leftHip), p(.rightHip)),
            shoulderWidth: Geometry.distance(p(.leftShoulder), p(.rightShoulder)),
            trunkLength: Geometry.distance(shoulderCenter, hipCenter),
            footLength: footLengths.isEmpty ? 0 : average(footLengths),
            kneeFlexion: kneeFlexions.isEmpty ? 0 : average(kneeFlexions),
            ankleAngle: ankleAngles.isEmpty ? 0 : average(ankleAngles),
            hipY: hipCenter.y,
            heelY: heels.isEmpty ? 0 : average(heels),
            leftHeelLift: heelLift(.left),
            rightHeelLift: heelLift(.right)
        )
    }

    private static func jitter(of samples: [Sample]) -> Float {
        [samples.map(\.femur), samples.map(\.tibia),
         samples.map(\.hipWidth), samples.map(\.trunkLength)]
            .map(standardDeviation).max() ?? 0
    }

    private static func standardDeviation(_ values: [Float]) -> Float {
        if values.count < 2 { return 0 }
        let mean = values.reduce(0.0) { $0 + Double($1) } / Double(values.count)
        let variance = values.reduce(0.0) { $0 + (Double($1) - mean) * (Double($1) - mean) }
            / Double(values.count)
        return Float(variance.squareRoot())
    }

    /// Kotlin `List<Float>.average()`가 Double로 누적하므로 같은 방식으로 맞춘다.
    static func average(_ values: [Float]) -> Float {
        if values.isEmpty { return 0 }
        return Float(values.reduce(0.0) { $0 + Double($1) } / Double(values.count))
    }

    static func averageOrNil(_ values: [Float]) -> Float? {
        values.isEmpty ? nil : average(values)
    }
}
