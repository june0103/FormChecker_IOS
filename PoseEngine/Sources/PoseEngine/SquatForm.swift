import Foundation

public enum DepthLevel: String, Sendable, CaseIterable {
    case standing, shallow, parallel, deep
}

/// 깊이를 **무엇으로** 판정했는지. 두 기준은 서로 환산되지 않으므로 결과에 남긴다.
public enum DepthBasis: String, Sendable, CaseIterable {
    case hipHeight, shinLength
}

public enum PoseVisibility: String, Sendable, CaseIterable {
    case none, upperBodyOnly, full
}

public enum KneeAlignment: String, Sendable, CaseIterable {
    case good, valgus, flared
}

/// 한 프레임의 자세 판정 결과.
public struct SquatForm: Sendable {
    public let cameraAngle: CameraAngle
    public let visibility: PoseVisibility
    public let kneeAngles: KneeAngles
    public let hipAngles: BilateralAngles
    public let depth: DepthLevel?
    public let depthBasis: DepthBasis?
    public let depthRatio: Float?
    public let torsoLeanDegrees: Float?
    public let heelRise: Float?
    public let kneeOverToe: Float?
    public let kneeSpreadRatio: Float?
    public let hipShiftRatio: Float?
    public let kneeToeDeviation: Float?
    public let kneeAlignment: KneeAlignment?
    public let kneeToeSide: Side?
    public let asymmetryDegrees: Float?
    public let suggestedAngle: CameraAngle?
    public let warnings: [FormWarning]
}

/// 자세 경고 7종.
public enum FormWarning: String, Sendable, CaseIterable {
    case kneeValgus, kneeFlared, heelRise, kneePastToe, shallowDepth, excessiveLean, hipShift

    public var check: FormCheck {
        switch self {
        case .kneeValgus, .kneeFlared: .kneeAlignment
        case .heelRise: .heelLift
        case .kneePastToe: .kneeOverToe
        case .shallowDepth: .depth
        case .excessiveLean: .torsoLean
        case .hipShift: .symmetry
        }
    }

    /// rep이 끝난 뒤에 한 번 판정하는 항목인가.
    ///
    /// 🔴 **하강은 `standing → shallow → parallel`을 지나므로 얕은 구간이 반드시 있다.**
    /// 프레임 단위로 말하면 *아직 내려가는 중인 사람에게 "덜 앉았다"* 고 하는 것이 된다.
    /// 둘 다 rep 중간에 고칠 수 없어 **다 일어선 뒤**에 떠야 하고, 그 시점이 2초 hold가
    /// 겨냥한 자리다.
    public var isRepLevel: Bool {
        switch self {
        case .shallowDepth, .kneePastToe: true
        case .kneeValgus, .kneeFlared, .heelRise, .excessiveLean, .hipShift: false
        }
    }
}

/// rep 단위 경고 집합을 만든다.
///
/// **판정과 항목 간 배제 규칙은 여기 한 곳에만 있다** — 저장과 화면이 같은 답을 써야 한다.
public enum RepWarnings {
    public static func of(
        frameWarnings: Set<FormWarning>,
        depth: DepthLevel?,
        kneePastToe: Bool?
    ) -> Set<FormWarning> {
        let heelLifted = frameWarnings.contains(.heelRise)
        // 🔴 뒤꿈치가 뜨면 깊이 부족을 말하지 않는다 — 서로 반대인 지시가 된다.
        let shallow = depth == .shallow && !heelLifted

        var result = frameWarnings
        if shallow { result.insert(.shallowDepth) }
        if kneePastToe == true { result.insert(.kneePastToe) }
        return result
    }
}
