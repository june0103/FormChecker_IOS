import Foundation

/// rep 하나의 판정 집계.
///
/// 🔴 **점수를 만들지 않는다.** 경고 7종에 가중치를 매길 근거가 없고, 숫자 하나로 뭉치면
/// 무엇을 고쳐야 하는지도 함께 사라진다. `checkedCount` / `warnedCount`로 **사실만** 센다.
public struct RepScore: Sendable, Equatable {
    /// 패럴렐 도달률 0~1. **측면 전용**(정면은 nil).
    public let depthScore: Float?
    /// 이 rep에서 실제로 판정한 항목 수.
    public let checkedCount: Int
    /// 그중 경고가 난 항목 수.
    public let warnedCount: Int
    public let errorFlags: [FormWarning: Bool]

    /// 판정한 항목이 없으면 nil — "괜찮다"와 "못 봤다"는 다르다.
    public var clean: Bool? { checkedCount == 0 ? nil : warnedCount == 0 }
}

public enum RepScorer {

    public static func score(
        cameraAngle: CameraAngle,
        warnings: Set<FormWarning>,
        depthValue: Float?,
        depthBasis: DepthBasis?,
        thresholds: FormThresholds = FormThresholds()
    ) -> RepScore {
        let checks = checksFor(cameraAngle)
        var flags: [FormWarning: Bool] = [:]
        for check in checks { flags[check] = warnings.contains(check) }
        return RepScore(
            depthScore: depthScore(cameraAngle: cameraAngle, value: depthValue,
                                   basis: depthBasis, thresholds: thresholds),
            checkedCount: checks.count,
            warnedCount: flags.values.filter { $0 }.count,
            errorFlags: flags
        )
    }

    /// 이 촬영 각도에서 **판정 가능한** 경고 종류. 리포트의 분모가 된다.
    public static func checksFor(_ cameraAngle: CameraAngle) -> Set<FormWarning> {
        Set(FormWarning.allCases.filter { cameraAngle.supports($0.check) })
    }

    private static func depthScore(
        cameraAngle: CameraAngle, value: Float?, basis: DepthBasis?, thresholds: FormThresholds
    ) -> Float? {
        guard cameraAngle.supports(.depth), let value, let basis else { return nil }
        let standing: Float = switch basis {
        case .hipHeight: thresholds.standingDepthRatio
        case .shinLength: thresholds.standingShinDepth
        }
        guard standing < 0 else { return nil }
        return min(1, max(0, (value - standing) / -standing))
    }
}
