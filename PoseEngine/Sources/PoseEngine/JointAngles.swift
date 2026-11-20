import Foundation

/// 한 프레임에서 뽑은 좌우 관절 각도.
///
/// 좌/우를 따로 들고 있는 이유는 두 가지다.
/// 1. 측면 촬영에서는 먼 쪽 다리가 가려져 confidence가 낮게 나온다. 신뢰 가능한 쪽만 쓴다.
/// 2. 좌우 차이 자체가 자세 비대칭 판정의 재료가 된다.
public struct BilateralAngles: Sendable, Equatable {
    public let left: Float?
    public let right: Float?

    public init(left: Float?, right: Float?) {
        self.left = left
        self.right = right
    }

    /// 대표 각도.
    ///
    /// 둘 다 신뢰 가능하면 평균, 한쪽만이면 그 값, 둘 다 없으면 nil이다.
    /// 평균을 쓰는 이유: 정면 촬영에서 한쪽만 쓰면 좌우 흔들림이 그대로 노이즈가 된다.
    public var representative: Float? {
        if let left, let right { return (left + right) / 2 }
        return left ?? right
    }

    /// 좌우 각도 차이. 둘 다 신뢰 가능할 때만 값이 있다.
    public var asymmetry: Float? {
        guard let left, let right else { return nil }
        return abs(left - right)
    }
}

/// 무릎 각도. 호출부에서 어느 관절인지 읽히게 하는 별칭.
public typealias KneeAngles = BilateralAngles

/// 키포인트에서 관절 각도를 계산한다.
///
/// ## ⚠ 종횡비 보정이 필요한 이유
/// 좌표는 원본 프레임 기준 0~1 정규화 값이라 x축과 y축의 "1"이 서로 다른 픽셀 길이를
/// 뜻한다. 이 상태로 각도를 재면 프레임이 세로로 길수록 각도가 왜곡된다.
///
/// letterbox로 종횡비 왜곡을 막았더라도 이 보정은 **별개로** 필요하다. letterbox는 모델
/// 입력 단계의 왜곡을 막는 것이고, 이건 정규화 좌표계 자체가 비등방이라 생기는 문제다.
/// 둘 중 하나만 하면 각도가 틀린다.
public enum JointAngles {

    /// 어깨-힙-무릎 각도를 좌우 각각 계산한다. 고관절 굴곡의 척도.
    ///
    /// 측면 촬영에서만 의미가 있다 — 정면에서는 상체의 앞뒤 굴곡이 화면상 거의 변화를
    /// 만들지 않는다.
    public static func hips(
        _ pose: Pose,
        frameAspectRatio: Float,
        minConfidence: Float = Pose.minConfidence
    ) -> BilateralAngles {
        BilateralAngles(
            left: angleAt(pose, .leftShoulder, .leftHip, .leftKnee,
                          frameAspectRatio: frameAspectRatio, minConfidence: minConfidence),
            right: angleAt(pose, .rightShoulder, .rightHip, .rightKnee,
                           frameAspectRatio: frameAspectRatio, minConfidence: minConfidence)
        )
    }

    /// 힙-무릎-발목 각도를 좌우 각각 계산한다.
    public static func knees(
        _ pose: Pose,
        frameAspectRatio: Float,
        minConfidence: Float = Pose.minConfidence
    ) -> KneeAngles {
        KneeAngles(
            left: angleAt(pose, .leftHip, .leftKnee, .leftAnkle,
                          frameAspectRatio: frameAspectRatio, minConfidence: minConfidence),
            right: angleAt(pose, .rightHip, .rightKnee, .rightAnkle,
                           frameAspectRatio: frameAspectRatio, minConfidence: minConfidence)
        )
    }

    /// `vertex`를 꼭짓점으로 하는 `a`-`vertex`-`b` 사이각(도).
    ///
    /// 세 점 중 하나라도 confidence가 `minConfidence` 미만이면 nil을 돌려준다.
    /// 낮은 신뢰도의 좌표로 계산한 각도는 **틀린 값을 확신에 차서 내놓는 것보다 없는 편이 낫다.**
    public static func angleAt(
        _ pose: Pose,
        _ a: KeypointType,
        _ vertex: KeypointType,
        _ b: KeypointType,
        frameAspectRatio: Float,
        minConfidence: Float = Pose.minConfidence
    ) -> Float? {
        guard pose.isReliable(a, minConfidence: minConfidence),
              pose.isReliable(vertex, minConfidence: minConfidence),
              pose.isReliable(b, minConfidence: minConfidence) else { return nil }
        return angle(pose[a], pose[vertex], pose[b], frameAspectRatio: frameAspectRatio)
    }

    /// 세 점이 이루는 각도(도). 0~180 범위.
    private static func angle(
        _ a: Keypoint, _ vertex: Keypoint, _ b: Keypoint, frameAspectRatio: Float
    ) -> Float {
        let v1x = (a.x - vertex.x) * frameAspectRatio
        let v1y = a.y - vertex.y
        let v2x = (b.x - vertex.x) * frameAspectRatio
        let v2y = b.y - vertex.y

        let len1 = sqrt(v1x * v1x + v1y * v1y)
        let len2 = sqrt(v2x * v2x + v2y * v2y)
        if len1 == 0 || len2 == 0 { return 0 }

        // 부동소수 오차로 |cos|가 1을 아주 살짝 넘으면 acos가 NaN이 되므로 clamp한다.
        let cosine = min(1, max(-1, (v1x * v2x + v1y * v2y) / (len1 * len2)))
        return Float(Geometry.toDegrees(acos(Double(cosine))))
    }
}
