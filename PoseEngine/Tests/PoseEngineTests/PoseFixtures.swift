import Foundation
@testable import PoseEngine

/// 테스트용 포즈 만들기.
///
/// 지정한 키포인트만 좌표를 넣고 나머지는 **신뢰도 0**으로 채운다 — 판정 코드가 전부
/// `isReliable` 게이트를 거치므로 "가려진 관절"과 똑같이 취급된다.
enum PoseFixtures {

    typealias Point = (x: Float, y: Float, confidence: Float)

    static func pose(_ points: [KeypointType: Point]) -> Pose {
        Pose(
            keypoints: (0..<KeypointType.count).map { index in
                let type = KeypointType(rawValue: index)!
                let p = points[type]
                return Keypoint(type: type, x: p?.x ?? 0, y: p?.y ?? 0, confidence: p?.confidence ?? 0)
            },
            inferenceTimeNanos: 0
        )
    }

    /// 한쪽 다리만 있는 포즈.
    static func leg(
        hip: (Float, Float), knee: (Float, Float), ankle: (Float, Float),
        side: Side = .left, confidence: Float = 0.9
    ) -> Pose {
        pose([
            Geometry.hip(side): (hip.0, hip.1, confidence),
            Geometry.knee(side): (knee.0, knee.1, confidence),
            Geometry.ankle(side): (ankle.0, ankle.1, confidence),
        ])
    }

    /// 양쪽 다리 + 어깨까지 갖춘 포즈. 기준 자세 측정에 필요한 8개를 채운다.
    static func fullBody(
        hipY: Float = 0.5, kneeY: Float = 0.7, ankleY: Float = 0.9,
        hipHalfWidth: Float = 0.05, shoulderHalfWidth: Float = 0.1,
        shoulderY: Float = 0.25, centerX: Float = 0.5,
        confidence: Float = 0.9,
        extra: [KeypointType: Point] = [:]
    ) -> Pose {
        var points: [KeypointType: Point] = [
            .leftShoulder: (centerX - shoulderHalfWidth, shoulderY, confidence),
            .rightShoulder: (centerX + shoulderHalfWidth, shoulderY, confidence),
            .leftHip: (centerX - hipHalfWidth, hipY, confidence),
            .rightHip: (centerX + hipHalfWidth, hipY, confidence),
            .leftKnee: (centerX - hipHalfWidth, kneeY, confidence),
            .rightKnee: (centerX + hipHalfWidth, kneeY, confidence),
            .leftAnkle: (centerX - hipHalfWidth, ankleY, confidence),
            .rightAnkle: (centerX + hipHalfWidth, ankleY, confidence),
        ]
        for (key, value) in extra { points[key] = value }
        return pose(points)
    }
}

extension Keypoint {
    /// Kotlin `data class`의 `copy(...)`에 대응한다.
    func with(x: Float? = nil, y: Float? = nil, confidence: Float? = nil) -> Keypoint {
        Keypoint(type: type, x: x ?? self.x, y: y ?? self.y,
                 confidence: confidence ?? self.confidence)
    }
}

extension Pose {
    func mapKeypoints(_ transform: (Keypoint) -> Keypoint) -> Pose {
        Pose(keypoints: keypoints.map(transform), inferenceTimeNanos: inferenceTimeNanos)
    }

    func mapKeypoints(_ transform: (Int, Keypoint) -> Keypoint) -> Pose {
        Pose(keypoints: keypoints.enumerated().map(transform),
             inferenceTimeNanos: inferenceTimeNanos)
    }
}
