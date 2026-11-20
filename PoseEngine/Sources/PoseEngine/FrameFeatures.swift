import Foundation

/// 한 프레임에서 뽑은 특징.
///
/// 🔴 **모든 정규화 특징은 기준선(``StandingCalibration``)을 분모로 쓴다.** 기준선이 없으면
/// 그 특징은 nil이고, **각도로 대체되지 않는다.**
///
/// > ⚠ **분모를 의심할 것.** 측면에서 발 길이·어깨폭·힙폭은 원근으로 압축되고, 발목 간격은
/// > 두 발이 겹치면 무너진다. 이 프로젝트에서 정규화 실패가 반복해서 나왔다.
public struct FrameFeatures: Sendable, Equatable {
    public let leftKneeFlexion: Float?
    public let rightKneeFlexion: Float?
    public let leftHipFlexion: Float?
    public let rightHipFlexion: Float?
    public let leftAnkleDorsiflexion: Float?
    public let rightAnkleDorsiflexion: Float?
    /// `(hip.y − knee.y) / legLength`. 깊이 판정의 1차 경로.
    public let depthRatio: Float?
    public let thighAngle: Float?
    public let trunkLean: Float?
    public let shinAngle: Float?
    public let hipDropRatio: Float?
    public let hipTravelRatio: Float?
    public let leftHeelRise: Float?
    public let rightHeelRise: Float?
    /// 활성측만 본다.
    public let heelRise: Float?
    public let kneeOverToe: Float?
    public let stanceWidthRatio: Float?
    public let leftMedialKneeDisplacement: Float?
    public let rightMedialKneeDisplacement: Float?
    public let leftKneeToeDeviation: Float?
    public let rightKneeToeDeviation: Float?
    /// `(hip.y − knee.y) / (ankle.y − knee.y)`. 기준선 없을 때의 깊이 경로이자 각종 게이트.
    public let shinDepthRatio: Float?
    public let hipShiftRatio: Float?
    public let ankleSpread: Float?
    /// 발 가시성 게이트 (발 길이 / 정강이).
    public let footTibiaRatio: Float?
    public let pelvisTilt: Float?
    public let shoulderTilt: Float?
    public let trunkLateralLean: Float?
    public let leftFootRotation: Float?
    public let rightFootRotation: Float?
    public let minConfidence: Float

    public var kneeFlexionAsymmetry: Float? {
        guard let l = leftKneeFlexion, let r = rightKneeFlexion else { return nil }
        return abs(l - r)
    }

    public var representativeKneeFlexion: Float? {
        if let l = leftKneeFlexion, let r = rightKneeFlexion { return (l + r) / 2 }
        return leftKneeFlexion ?? rightKneeFlexion
    }

    // swiftlint:disable:next function_body_length
    public static func from(
        pose: Pose,
        aspectRatio: Float,
        calibration: StandingCalibration?,
        view: CaptureView,
        activeSide: Side?,
        minConfidence: Float = StandingCalibration.minConfidence
    ) -> FrameFeatures {
        func p(_ type: KeypointType) -> Point2 {
            Geometry.point(pose, type, aspectRatio: aspectRatio)
        }
        func ok(_ type: KeypointType) -> Bool {
            pose.isReliable(type, minConfidence: minConfidence)
        }
        let legLength = calibration?.legLength ?? 0
        let footLength = calibration?.footLength ?? 0

        func kneeFlexion(_ side: Side) -> Float? {
            Geometry.kneeFlexion(pose, side, aspectRatio: aspectRatio, minConfidence: minConfidence)
        }
        func hipFlexion(_ side: Side) -> Float? {
            Geometry.hipFlexion(pose, side, aspectRatio: aspectRatio, minConfidence: minConfidence)
        }
        /// 배측굴곡은 **기립 대비 변화량**이다. 절대값은 발 길이 추정과 신발에 좌우된다.
        func dorsiflexion(_ side: Side) -> Float? {
            guard let angle = Geometry.ankleAngle(pose, side, aspectRatio: aspectRatio,
                                                  minConfidence: minConfidence),
                  let calibration else { return nil }
            return calibration.standingAnkleAngle - angle
        }

        let sideHip = activeSide.map { Geometry.hip($0) }
        let sideKnee = activeSide.map { Geometry.knee($0) }
        let sideAnkle = activeSide.map { Geometry.ankle($0) }

        var depthRatio: Float?
        if view.isSide, let sideHip, let sideKnee, ok(sideHip), ok(sideKnee),
           legLength > Geometry.epsilon {
            depthRatio = (p(sideHip).y - p(sideKnee).y) / legLength
        }

        var thighAngle: Float?
        if view.isSide, let sideHip, let sideKnee, ok(sideHip), ok(sideKnee) {
            thighAngle = Geometry.angleFromHorizontal(from: p(sideHip), to: p(sideKnee))
        }

        var shinAngle: Float?
        if view.isSide, let sideKnee, let sideAnkle, ok(sideKnee), ok(sideAnkle) {
            shinAngle = Geometry.angleFromVertical(from: p(sideAnkle), to: p(sideKnee))
        }

        let hipCenter: Point2? = (ok(.leftHip) && ok(.rightHip))
            ? Geometry.midpoint(p(.leftHip), p(.rightHip)) : nil

        var hipReference: Point2?
        if view.isSide, let sideHip {
            hipReference = ok(sideHip) ? p(sideHip) : nil
        } else {
            hipReference = hipCenter
        }

        var trunkLean: Float?
        if view.isSide, let hipReference, ok(.neck) {
            trunkLean = Geometry.angleFromVertical(from: hipReference, to: p(.neck))
        }

        var hipDropRatio: Float?
        if view.isSide, let hipReference, let calibration, legLength > Geometry.epsilon {
            hipDropRatio = (hipReference.y - calibration.standingHipY) / legLength
        }

        var hipTravelRatio: Float?
        if view.isSide, let hipReference, let sideAnkle, ok(sideAnkle),
           legLength > Geometry.epsilon {
            hipTravelRatio = (hipReference.x - p(sideAnkle).x) / legLength
        }

        /// 기립 기준 대비 뒤꿈치 상승량을 정강이로 정규화한다.
        func heelRise(_ side: Side) -> Float? {
            guard view.isSide, let calibration else { return nil }
            let tibia = calibration.tibiaLength
            guard tibia > Geometry.epsilon,
                  let standing = calibration.standingHeelLift(side) else { return nil }
            let heel = Geometry.heel(side)
            guard ok(heel),
                  let toe = Geometry.toeCenter(pose, side, aspectRatio: aspectRatio,
                                               minConfidence: minConfidence) else { return nil }
            return ((toe.y - pose[heel].y) - standing) / tibia
        }

        /// 앞쪽은 `sign(발끝.x − 뒤꿈치.x)`로 **발이 스스로 가리킨다** — 촬영 좌/우를 몰라도 된다.
        func kneeOverToe(_ side: Side) -> Float? {
            guard view.isSide else { return nil }
            let knee = Geometry.knee(side)
            let heel = Geometry.heel(side)
            guard ok(knee), ok(heel),
                  let toe = Geometry.toeCenter(pose, side, aspectRatio: aspectRatio,
                                               minConfidence: minConfidence) else { return nil }
            let heelX = p(heel).x
            let footSpan = toe.x - heelX
            guard abs(footSpan) > Geometry.epsilon else { return nil }
            let forward: Float = footSpan > 0 ? 1 : -1
            return (p(knee).x - toe.x) * forward / abs(footSpan)
        }

        let ankleCenter: Point2? = (ok(.leftAnkle) && ok(.rightAnkle))
            ? Geometry.midpoint(p(.leftAnkle), p(.rightAnkle)) : nil
        let ankleSpread: Float? = (ok(.leftAnkle) && ok(.rightAnkle))
            ? Geometry.distance(p(.leftAnkle), p(.rightAnkle)) : nil

        var stanceWidthRatio: Float?
        if view.isFront, let ankleSpread, let calibration,
           calibration.hipWidth > Geometry.epsilon {
            stanceWidthRatio = ankleSpread / calibration.hipWidth
        }

        func medialKnee(_ side: Side) -> Float? {
            guard view.isFront, legLength > Geometry.epsilon else { return nil }
            let hip = Geometry.hip(side), knee = Geometry.knee(side), ankle = Geometry.ankle(side)
            guard ok(hip), ok(knee), ok(ankle),
                  let deviation = Geometry.horizontalDeviationFromLine(
                    lineStart: p(hip), lineEnd: p(ankle), point: p(knee)
                  ) else { return nil }
            let inwardSign: Float = side == .left ? -1 : 1
            return deviation * inwardSign / legLength
        }

        func kneeToeDeviation(_ side: Side) -> Float? {
            guard view.isFront, let ankleSpread, ankleSpread > Geometry.epsilon else { return nil }
            let knee = Geometry.knee(side)
            guard ok(knee) else { return nil }
            let toes = [Geometry.bigToe(side), Geometry.smallToe(side)]
                .filter { ok($0) }.map { p($0).x }
            guard !toes.isEmpty else { return nil }
            let toeX = StandingCalibration.average(toes)
            let inwardSign: Float = side == .left ? -1 : 1
            return (p(knee).x - toeX) * inwardSign / ankleSpread
        }

        var shinDepthRatio: Float?
        if let hipCenter, ok(.leftKnee), ok(.rightKnee), ok(.leftAnkle), ok(.rightAnkle) {
            let kneeY = (pose[.leftKnee].y + pose[.rightKnee].y) / 2
            let ankleY = (pose[.leftAnkle].y + pose[.rightAnkle].y) / 2
            let shin = ankleY - kneeY
            if shin > Geometry.epsilon { shinDepthRatio = (hipCenter.y - kneeY) / shin }
        }

        var hipShiftRatio: Float?
        if view.isFront, let hipCenter, let ankleCenter, let ankleSpread,
           ankleSpread > Geometry.epsilon {
            hipShiftRatio = (hipCenter.x - ankleCenter.x) / ankleSpread
        }

        var pelvisTilt: Float?
        if view.isFront, ok(.leftHip), ok(.rightHip) {
            pelvisTilt = Geometry.angleFromHorizontal(from: p(.leftHip), to: p(.rightHip))
        }

        var shoulderTilt: Float?
        if view.isFront, ok(.leftShoulder), ok(.rightShoulder) {
            shoulderTilt = Geometry.angleFromHorizontal(from: p(.leftShoulder), to: p(.rightShoulder))
        }

        var trunkLateralLean: Float?
        if view.isFront, let hipCenter, ok(.neck) {
            trunkLateralLean = Geometry.angleFromVertical(from: hipCenter, to: p(.neck))
        }

        func footRotation(_ side: Side) -> Float? {
            guard view.isFront, footLength > Geometry.epsilon else { return nil }
            let heel = Geometry.heel(side)
            guard ok(heel),
                  let toe = Geometry.toeCenter(pose, side, aspectRatio: aspectRatio,
                                               minConfidence: minConfidence) else { return nil }
            let outwardSign: Float = side == .left ? 1 : -1
            return (toe.x - p(heel).x) * outwardSign / footLength
        }

        return FrameFeatures(
            leftKneeFlexion: kneeFlexion(.left),
            rightKneeFlexion: kneeFlexion(.right),
            leftHipFlexion: hipFlexion(.left),
            rightHipFlexion: hipFlexion(.right),
            leftAnkleDorsiflexion: dorsiflexion(.left),
            rightAnkleDorsiflexion: dorsiflexion(.right),
            depthRatio: depthRatio,
            thighAngle: thighAngle,
            trunkLean: trunkLean,
            shinAngle: shinAngle,
            hipDropRatio: hipDropRatio,
            hipTravelRatio: hipTravelRatio,
            leftHeelRise: heelRise(.left),
            rightHeelRise: heelRise(.right),
            heelRise: activeSide.flatMap { heelRise($0) },
            kneeOverToe: activeSide.flatMap { kneeOverToe($0) },
            stanceWidthRatio: stanceWidthRatio,
            leftMedialKneeDisplacement: medialKnee(.left),
            rightMedialKneeDisplacement: medialKnee(.right),
            leftKneeToeDeviation: kneeToeDeviation(.left),
            rightKneeToeDeviation: kneeToeDeviation(.right),
            shinDepthRatio: shinDepthRatio,
            hipShiftRatio: hipShiftRatio,
            ankleSpread: ankleSpread,
            footTibiaRatio: calibration?.footTibiaRatio,
            pelvisTilt: pelvisTilt,
            shoulderTilt: shoulderTilt,
            trunkLateralLean: trunkLateralLean,
            leftFootRotation: footRotation(.left),
            rightFootRotation: footRotation(.right),
            minConfidence: confidence(of: pose, view: view, activeSide: activeSide)
        )
    }

    private static func confidence(of pose: Pose, view: CaptureView, activeSide: Side?) -> Float {
        let joints: [KeypointType]
        if view.isSide, let activeSide {
            joints = [Geometry.hip(activeSide), Geometry.knee(activeSide), Geometry.ankle(activeSide)]
        } else {
            joints = [.leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle]
        }
        return joints.map { pose[$0].confidence }.min() ?? 0
    }
}
