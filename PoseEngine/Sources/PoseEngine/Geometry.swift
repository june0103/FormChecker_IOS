import Foundation

/// 2D 점. Kotlin 쪽 `Pair<Float, Float>`에 대응한다.
public struct Point2: Sendable, Equatable {
    public var x: Float
    public var y: Float
    public init(_ x: Float, _ y: Float) { self.x = x; self.y = y }
}

public enum Side: String, Sendable, CaseIterable { case left, right }

/// 좌표 계산 공통 함수.
///
/// ## 등방 보정을 여기서 한 번만 한다
/// 키포인트 좌표는 프레임 기준 0~1 정규화지만 화면이 정사각형이 아니어서 **x와 y의
/// 스케일이 다르다**(비등방). x에 종횡비를 곱해야 거리·각도 계산이 맞는다. 이 보정을 각
/// 특징 계산에 흩어 놓으면 어딘가에서 반드시 빠뜨리게 되고, 빠뜨려도 값이 그럴듯해서
/// 조용히 틀린다. 그래서 좌표를 꺼내는 ``point(_:_:aspectRatio:)`` 하나에서만 보정하고,
/// 이후 모든 계산은 등방 좌표로 한다.
///
/// ## 굴곡각 부호 규약
/// **곧게 선 상태를 0도로, 굽힐수록 증가**하도록 통일한다.
/// ```
/// kneeFlexion = 180° - angle(hip, knee, ankle)
/// hipFlexion  = 180° - angle(shoulder, hip, knee)
/// ```
/// 관절의 내각(180°가 곧은 상태)을 그대로 쓰면 "각도가 작아질수록 깊다"가 되어 임계값을
/// 읽을 때마다 방향을 헷갈리게 된다.
public enum Geometry {

    public static let epsilon: Float = 1e-6

    /// 등방 보정된 좌표.
    public static func point(_ pose: Pose, _ type: KeypointType, aspectRatio: Float) -> Point2 {
        let keypoint = pose[type]
        return Point2(keypoint.x * aspectRatio, keypoint.y)
    }

    public static func midpoint(_ a: Point2, _ b: Point2) -> Point2 {
        Point2((a.x + b.x) / 2, (a.y + b.y) / 2)
    }

    public static func distance(_ a: Point2, _ b: Point2) -> Float {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// `b`를 꼭짓점으로 하는 각(도). 0~180.
    public static func angle(_ a: Point2, _ b: Point2, _ c: Point2) -> Float {
        let ax = a.x - b.x
        let ay = a.y - b.y
        let cx = c.x - b.x
        let cy = c.y - b.y
        let magnitude = hypot(ax, ay) * hypot(cx, cy)
        if magnitude < epsilon { return 0 }
        let cosine = min(1, max(-1, (ax * cx + ay * cy) / magnitude))
        return Float(toDegrees(acos(Double(cosine))))
    }

    /// 벡터가 수직축과 이루는 각(도). 0이면 완전히 수직.
    ///
    /// 화면 y는 아래로 증가하므로, 위를 향하는 벡터가 되도록 부호를 뒤집는다.
    public static func angleFromVertical(from: Point2, to: Point2) -> Float {
        let dx = to.x - from.x
        let dy = from.y - to.y
        if abs(dx) < epsilon && abs(dy) < epsilon { return 0 }
        return abs(Float(toDegrees(atan2(Double(dx), Double(dy)))))
    }

    /// 벡터가 수평축과 이루는 각(도). 0이면 완전히 수평.
    public static func angleFromHorizontal(from: Point2, to: Point2) -> Float {
        let dx = to.x - from.x
        let dy = to.y - from.y
        if abs(dx) < epsilon && abs(dy) < epsilon { return 0 }
        let value = abs(Float(toDegrees(atan2(Double(dy), Double(dx)))))
        return value > 90 ? 180 - value : value
    }

    // ── 부위별 키포인트 ──────────────────────────────────────

    public static func hip(_ side: Side) -> KeypointType { side == .left ? .leftHip : .rightHip }
    public static func knee(_ side: Side) -> KeypointType { side == .left ? .leftKnee : .rightKnee }
    public static func ankle(_ side: Side) -> KeypointType { side == .left ? .leftAnkle : .rightAnkle }
    public static func shoulder(_ side: Side) -> KeypointType { side == .left ? .leftShoulder : .rightShoulder }
    public static func heel(_ side: Side) -> KeypointType { side == .left ? .leftHeel : .rightHeel }
    public static func bigToe(_ side: Side) -> KeypointType { side == .left ? .leftBigToe : .rightBigToe }
    public static func smallToe(_ side: Side) -> KeypointType { side == .left ? .leftSmallToe : .rightSmallToe }

    /// 발끝 중점(엄지·소지 평균).
    public static func toeCenter(
        _ pose: Pose, _ side: Side, aspectRatio: Float, minConfidence: Float
    ) -> Point2? {
        guard pose.isReliable(bigToe(side), minConfidence: minConfidence),
              pose.isReliable(smallToe(side), minConfidence: minConfidence) else { return nil }
        return midpoint(
            point(pose, bigToe(side), aspectRatio: aspectRatio),
            point(pose, smallToe(side), aspectRatio: aspectRatio)
        )
    }

    public static func footLength(
        _ pose: Pose, _ side: Side, aspectRatio: Float, minConfidence: Float
    ) -> Float? {
        guard pose.isReliable(heel(side), minConfidence: minConfidence),
              let toe = toeCenter(pose, side, aspectRatio: aspectRatio, minConfidence: minConfidence)
        else { return nil }
        let length = distance(point(pose, heel(side), aspectRatio: aspectRatio), toe)
        return length > epsilon ? length : nil
    }

    // ── 굴곡각 (부호 규약) ───────────────────────────────────

    /// 무릎 굴곡각. 곧게 서면 0에 가깝고 굽힐수록 증가한다.
    public static func kneeFlexion(
        _ pose: Pose, _ side: Side, aspectRatio: Float, minConfidence: Float
    ) -> Float? {
        let joints = [hip(side), knee(side), ankle(side)]
        guard joints.allSatisfy({ pose.isReliable($0, minConfidence: minConfidence) }) else { return nil }
        return 180 - angle(
            point(pose, hip(side), aspectRatio: aspectRatio),
            point(pose, knee(side), aspectRatio: aspectRatio),
            point(pose, ankle(side), aspectRatio: aspectRatio)
        )
    }

    /// 고관절 굴곡각. 곧게 서면 0에 가깝고 접을수록 증가한다.
    public static func hipFlexion(
        _ pose: Pose, _ side: Side, aspectRatio: Float, minConfidence: Float
    ) -> Float? {
        let joints = [shoulder(side), hip(side), knee(side)]
        guard joints.allSatisfy({ pose.isReliable($0, minConfidence: minConfidence) }) else { return nil }
        return 180 - angle(
            point(pose, shoulder(side), aspectRatio: aspectRatio),
            point(pose, hip(side), aspectRatio: aspectRatio),
            point(pose, knee(side), aspectRatio: aspectRatio)
        )
    }

    /// 발목 각도 `angle(무릎, 발목, 발끝중점)`.
    ///
    /// 배측굴곡은 이 값의 **기립 대비 변화량**으로 잰다. 절대값은 발 길이 추정과 신발에
    /// 크게 좌우된다.
    public static func ankleAngle(
        _ pose: Pose, _ side: Side, aspectRatio: Float, minConfidence: Float
    ) -> Float? {
        guard pose.isReliable(knee(side), minConfidence: minConfidence),
              pose.isReliable(ankle(side), minConfidence: minConfidence),
              let toe = toeCenter(pose, side, aspectRatio: aspectRatio, minConfidence: minConfidence)
        else { return nil }
        return angle(
            point(pose, knee(side), aspectRatio: aspectRatio),
            point(pose, ankle(side), aspectRatio: aspectRatio),
            toe
        )
    }

    /// 점이 선분에서 얼마나 벗어났는지, **선분 기준 부호 있는 수평 편차**.
    ///
    /// 무릎 내측 이동에 쓴다 — 힙과 발목을 잇는 기준선을 긋고, 무릎 높이에서 기준선의
    /// 기대 x와 실제 무릎 x의 차를 본다.
    ///
    /// - Returns: 무릎이 기준선보다 x가 작으면 음수, 크면 양수.
    ///   방향(내측/외측) 해석은 호출부가 사람의 좌우와 화면 좌우를 맞춰서 한다.
    public static func horizontalDeviationFromLine(
        lineStart: Point2, lineEnd: Point2, point: Point2
    ) -> Float? {
        let dy = lineEnd.y - lineStart.y
        // 힙과 발목의 높이가 같으면 기준선이 수평이라 "무릎 높이에서의 x"가 정의되지 않는다.
        if abs(dy) < epsilon { return nil }
        let t = (point.y - lineStart.y) / dy
        let expectedX = lineStart.x + (lineEnd.x - lineStart.x) * t
        return point.x - expectedX
    }

    @inline(__always)
    static func toDegrees(_ radians: Double) -> Double { radians * 180.0 / .pi }
}
