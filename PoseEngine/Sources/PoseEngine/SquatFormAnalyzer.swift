import Foundation

/// 한 프레임의 자세를 판정한다.
///
/// 🔴 **rep 단위 판정 2종(깊이 부족·무릎이 발끝을 넘음)은 여기서 프레임 경고로 내보내지
/// 않는다.** 하강은 `standing → shallow → parallel`을 지나므로 얕은 구간이 반드시 있는데,
/// 프레임마다 말하면 *아직 내려가는 중인 사람에게 "덜 앉았다"* 고 하는 것이 된다.
/// 그 둘은 ``RepWarnings/of(frameWarnings:depth:kneePastToe:)``가 rep이 끝난 뒤에 붙인다.
public final class SquatFormAnalyzer {

    private let config: SquatAnalyzerConfig
    private var form: FormThresholds { config.form }
    private var detection: AngleDetectionThresholds { config.angleDetection }
    private var minConfidence: Float { config.minConfidence }

    public init(config: SquatAnalyzerConfig = SquatAnalyzerConfig()) {
        self.config = config
    }

    public func analyze(
        pose: Pose,
        frameAspectRatio: Float,
        cameraAngle: CameraAngle,
        features: FrameFeatures? = nil
    ) -> SquatForm {
        let knees = JointAngles.knees(pose, frameAspectRatio: frameAspectRatio,
                                      minConfidence: minConfidence)
        let depthSupported = cameraAngle.supports(.depth)
        let depthRatio = depthSupported ? features?.depthRatio : nil
        let shinDepthRatio = depthSupported ? features?.shinDepthRatio : nil

        // 기준선이 있으면 엉덩이 높이로, 없으면 정강이로. **둘 다 없으면 nil이다** —
        // 각도로 대체하지 않는다(각도 경로는 깊이 부족을 한 번도 잡지 못해 제거했다).
        let depth: DepthLevel?
        let depthBasis: DepthBasis?
        if let depthRatio {
            depth = form.depthLevel(byRatio: depthRatio)
            depthBasis = .hipHeight
        } else if let shinDepthRatio {
            depth = form.depthLevel(byShinDepth: shinDepthRatio)
            depthBasis = .shinLength
        } else {
            depth = nil
            depthBasis = nil
        }

        let torsoLean = cameraAngle.supports(.torsoLean)
            ? (features?.trunkLean ?? torsoLean(pose: pose, frameAspectRatio: frameAspectRatio))
            : nil

        // 발 가시성 게이트 — 발 길이/정강이가 이 값 아래면 발 관련 판정을 하지 않는다.
        let footVisible = (features?.footTibiaRatio ?? 0) >= form.minHeelFootRatio

        let heelRise = (cameraAngle.supports(.heelLift) && footVisible) ? features?.heelRise : nil

        var kneeOverToe: Float?
        if cameraAngle.supports(.kneeOverToe), footVisible,
           (features?.shinDepthRatio ?? -.greatestFiniteMagnitude) >= form.kneeToeMinDepth {
            kneeOverToe = features?.kneeOverToe
        }

        let hipShiftRatio = cameraAngle.supports(.symmetry) ? features?.hipShiftRatio : nil

        let gateDepth = features?.shinDepthRatio
        let stanceWideEnough = (features?.ankleSpread ?? 0) >= form.minStanceWidth
        let kneeToeJudgeable = cameraAngle.supports(.kneeAlignment)
            && gateDepth != nil && gateDepth! >= form.kneeToeMinDepth && stanceWideEnough

        // 좌우 중 **더 크게 벗어난 쪽**을 본다.
        var worstKneeToe: (side: Side, value: Float)?
        if kneeToeJudgeable {
            let candidates: [(Side, Float)] = [
                features?.leftKneeToeDeviation.map { (Side.left, $0) },
                features?.rightKneeToeDeviation.map { (Side.right, $0) },
            ].compactMap { $0 }
            worstKneeToe = candidates.max { abs($0.1) < abs($1.1) }.map { (side: $0.0, value: $0.1) }
        }
        let kneeToeDeviation = worstKneeToe?.value
        let alignment = form.kneeAlignment(byToe: kneeToeDeviation)

        return SquatForm(
            cameraAngle: cameraAngle,
            visibility: visibility(of: pose),
            kneeAngles: knees,
            hipAngles: JointAngles.hips(pose, frameAspectRatio: frameAspectRatio,
                                        minConfidence: minConfidence),
            depth: depth,
            depthBasis: depthBasis,
            depthRatio: depthRatio,
            torsoLeanDegrees: torsoLean,
            heelRise: heelRise,
            kneeOverToe: kneeOverToe,
            kneeSpreadRatio: kneeSpreadRatio(of: pose),
            hipShiftRatio: hipShiftRatio,
            kneeToeDeviation: kneeToeDeviation,
            kneeAlignment: alignment,
            kneeToeSide: alignment != .good ? worstKneeToe?.side : nil,
            asymmetryDegrees: cameraAngle.supports(.symmetry) ? knees.asymmetry : nil,
            suggestedAngle: detectAngle(pose: pose, aspectRatio: frameAspectRatio)
                .flatMap { $0 != cameraAngle ? $0 : nil },
            warnings: warnings(
                depth: depth, torsoLeanDegrees: torsoLean, heelRise: heelRise,
                hipShiftRatio: hipShiftRatio, kneeAlignment: alignment
            )
        )
    }

    /// **프레임 단위 경고만** 낸다. 깊이·무릎–발끝은 여기 없다.
    private func warnings(
        depth: DepthLevel?,
        torsoLeanDegrees: Float?,
        heelRise: Float?,
        hipShiftRatio: Float?,
        kneeAlignment: KneeAlignment?
    ) -> [FormWarning] {
        var result: [FormWarning] = []
        if let heelRise, heelRise > form.heelRiseLimit { result.append(.heelRise) }
        if let torsoLeanDegrees, torsoLeanDegrees > form.torsoLeanLimitDegrees {
            result.append(.excessiveLean)
        }
        if let hipShiftRatio, abs(hipShiftRatio) > form.hipShiftLimit { result.append(.hipShift) }
        switch kneeAlignment {
        case .valgus: result.append(.kneeValgus)
        case .flared: result.append(.kneeFlared)
        default: break
        }
        return result
    }

    private func visibility(of pose: Pose) -> PoseVisibility {
        let torso: [KeypointType] = [.leftShoulder, .rightShoulder, .leftHip, .rightHip]
        guard torso.contains(where: { pose.isReliable($0, minConfidence: minConfidence) }) else {
            return .none
        }
        let legs: [(KeypointType, KeypointType, KeypointType)] = [
            (.leftHip, .leftKnee, .leftAnkle), (.rightHip, .rightKnee, .rightAnkle),
        ]
        let legVisible = legs.contains { hip, knee, ankle in
            pose.isReliable(hip, minConfidence: minConfidence)
                && pose.isReliable(knee, minConfidence: minConfidence)
                && pose.isReliable(ankle, minConfidence: minConfidence)
        }
        return legVisible ? .full : .upperBodyOnly
    }

    private func torsoLean(pose: Pose, frameAspectRatio: Float) -> Float? {
        guard let shoulder = midpoint(pose, .leftShoulder, .rightShoulder),
              let hip = midpoint(pose, .leftHip, .rightHip) else { return nil }
        let dx = (shoulder.x - hip.x) * frameAspectRatio
        let dy = hip.y - shoulder.y
        if dx == 0 && dy == 0 { return nil }
        return abs(Float(Geometry.toDegrees(atan2(Double(dx), Double(dy)))))
    }

    private func kneeSpreadRatio(of pose: Pose) -> Float? {
        guard let kneeSpread = horizontalSpread(pose, .leftKnee, .rightKnee),
              let ankleSpread = horizontalSpread(pose, .leftAnkle, .rightAnkle) else { return nil }
        // 두 발이 겹치면 분모가 무너진다.
        guard ankleSpread >= form.minStanceWidth else { return nil }
        return kneeSpread / ankleSpread
    }

    private func detectAngle(pose: Pose, aspectRatio: Float) -> CameraAngle? {
        switch CaptureQuality.estimateView(pose: pose, aspectRatio: aspectRatio,
                                           thresholds: detection, minConfidence: minConfidence) {
        case .front: .front
        case .side: .side
        case .ambiguous, nil: nil
        }
    }

    private func midpoint(_ pose: Pose, _ a: KeypointType, _ b: KeypointType) -> Point2? {
        guard pose.isReliable(a, minConfidence: minConfidence),
              pose.isReliable(b, minConfidence: minConfidence) else { return nil }
        return Point2((pose[a].x + pose[b].x) / 2, (pose[a].y + pose[b].y) / 2)
    }

    private func horizontalSpread(_ pose: Pose, _ a: KeypointType, _ b: KeypointType) -> Float? {
        guard pose.isReliable(a, minConfidence: minConfidence),
              pose.isReliable(b, minConfidence: minConfidence) else { return nil }
        return abs(pose[a].x - pose[b].x)
    }
}
