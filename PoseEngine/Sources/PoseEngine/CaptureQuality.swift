import Foundation

/// 촬영 방향 추정.
///
/// 어깨 폭을 몸통 길이로 나눈 비율을 쓴다 — 정면에서는 두 어깨가 넓게 벌어지고 측면에서는
/// 앞뒤로 겹쳐 거의 한 점이 된다. 몸통 길이로 정규화하면 체격·카메라 거리와 무관해진다.
///
/// > Android `CaptureQuality` 중 **방향 추정만** 이식했다. 나머지(개발용 수집 화면의 프레임
/// > 품질 검사)는 iOS 1.0 범위 밖이다.
public enum CaptureQuality {

    public enum EstimatedView: String, Sendable, CaseIterable { case front, side, ambiguous }

    /// 여러 프레임의 **다수결**로 방향을 정한다.
    ///
    /// 🔴 **프레임 단위로 쓰면 안 된다.** 실측에서 정면 0.5% / 측면 0.5%가 반대로 읽히고
    /// 그게 두 세션에 몰려 있다 — rep 한가운데서 판정이 뒤집힌다. 세션 단위 다수결은
    /// 15/15 전부 맞았다.
    ///
    /// - Returns: 한 프레임도 추정하지 못했으면 nil.
    public static func estimateView(
        frames: [(pose: Pose, aspectRatio: Float)],
        thresholds: AngleDetectionThresholds = AngleDetectionThresholds(),
        minConfidence: Float = StandingCalibration.minConfidence
    ) -> EstimatedView? {
        var counts: [EstimatedView: Int] = [:]
        for entry in frames {
            guard let view = estimateView(pose: entry.pose, aspectRatio: entry.aspectRatio,
                                          thresholds: thresholds, minConfidence: minConfidence)
            else { continue }
            counts[view, default: 0] += 1
        }
        // 동점이면 Kotlin `maxByOrNull`과 같이 먼저 만난 쪽을 택하도록 순서를 고정한다.
        return EstimatedView.allCases
            .filter { counts[$0] != nil }
            .max { (counts[$0] ?? 0) < (counts[$1] ?? 0) }
    }

    /// 한 프레임의 방향 추정.
    public static func estimateView(
        pose: Pose,
        aspectRatio: Float,
        thresholds: AngleDetectionThresholds = AngleDetectionThresholds(),
        minConfidence: Float = StandingCalibration.minConfidence
    ) -> EstimatedView? {
        let joints: [KeypointType] = [.leftShoulder, .rightShoulder, .leftHip, .rightHip]
        guard joints.allSatisfy({ pose.isReliable($0, minConfidence: minConfidence) }) else {
            return nil
        }
        func p(_ type: KeypointType) -> Point2 {
            Geometry.point(pose, type, aspectRatio: aspectRatio)
        }
        let shoulderSpread = Geometry.distance(p(.leftShoulder), p(.rightShoulder))
        let shoulderCenter = Geometry.midpoint(p(.leftShoulder), p(.rightShoulder))
        let hipCenter = Geometry.midpoint(p(.leftHip), p(.rightHip))
        let trunk = Geometry.distance(shoulderCenter, hipCenter)
        guard trunk >= thresholds.minTorsoLength else { return nil }

        let ratio = shoulderSpread / trunk
        if ratio >= thresholds.frontRatio { return .front }
        if ratio <= thresholds.sideRatio { return .side }
        return .ambiguous
    }
}
