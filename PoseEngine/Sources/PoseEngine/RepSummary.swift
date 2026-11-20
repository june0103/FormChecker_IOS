import Foundation

/// 완주한 rep 하나의 요약.
public struct RepSummary: Sendable, Equatable {
    public let repIndex: Int
    public let startTimeMs: Int64
    public let endTimeMs: Int64
    public let aggregate: RepAggregate
    public let top: RepPosture?
    /// 최저점. **중앙값 각도가 가장 작은 프레임**으로 잡는다.
    public let bottom: RepPosture?
    public let cameraAngle: CameraAngle

    public var durationMs: Int64 { endTimeMs - startTimeMs }
}

public struct RepAggregate: Sendable, Equatable {
    public let minKneeAngle: Float?
    public let maxKneeAngle: Float?
    public let minHipAngle: Float?
    public let maxHipAngle: Float?
    public let maxTorsoLeanDegrees: Float?
    public let descentDurationMs: Int64?
    public let ascentDurationMs: Int64?
    public let maxAngularVelocityDegPerSec: Float?
    public let validFrameRatio: Float
    public let analyzedFrameCount: Int

    public var kneeRangeOfMotion: Float? {
        guard let minKneeAngle, let maxKneeAngle else { return nil }
        return maxKneeAngle - minKneeAngle
    }
}

/// rep 안의 한 시점(선 자세 / 최저점)에서의 자세.
public struct RepPosture: Sendable, Equatable {
    public let frameIndex: Int
    public let timestampMs: Int64
    public let kneeAngle: Float?
    public let leftKneeAngle: Float?
    public let rightKneeAngle: Float?
    public let hipAngle: Float?
    public let torsoLeanDegrees: Float?
    public let kneeAsymmetryDegrees: Float?
    public let kneeSpreadRatio: Float?
    public let leftFoot: FootSample?
    public let rightFoot: FootSample?
    public let minLegConfidence: Float
    public let framesUsed: Int
}

/// 발 키포인트 4개의 원값. **뒤꿈치 들림·무릎–발끝 판정의 재료다.**
public struct FootSample: Sendable, Equatable {
    public let bigToeX, bigToeY, bigToeConfidence: Float
    public let smallToeX, smallToeY, smallToeConfidence: Float
    public let heelX, heelY, heelConfidence: Float
    public let ankleX, ankleY, ankleConfidence: Float

    public var minConfidence: Float {
        min(bigToeConfidence, smallToeConfidence, heelConfidence, ankleConfidence)
    }

    public static func from(pose: Pose, side: Side) -> FootSample {
        let bigToe = pose[Geometry.bigToe(side)]
        let smallToe = pose[Geometry.smallToe(side)]
        let heel = pose[Geometry.heel(side)]
        let ankle = pose[Geometry.ankle(side)]
        return FootSample(
            bigToeX: bigToe.x, bigToeY: bigToe.y, bigToeConfidence: bigToe.confidence,
            smallToeX: smallToe.x, smallToeY: smallToe.y, smallToeConfidence: smallToe.confidence,
            heelX: heel.x, heelY: heel.y, heelConfidence: heel.confidence,
            ankleX: ankle.x, ankleY: ankle.y, ankleConfidence: ankle.confidence
        )
    }
}
