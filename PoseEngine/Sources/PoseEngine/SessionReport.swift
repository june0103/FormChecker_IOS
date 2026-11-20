import Foundation

/// 세션이 끝난 뒤 rep 사실을 모아 만든 리포트.
///
/// 🔴 **점수를 내지 않는다.** 항목별로 "몇 번 나왔는가"를 세고 **잦은 것부터** 보여준다.
/// 순서를 빈도로 정하면 새 임계값이 필요 없다.
public struct SessionReport: Sendable, Equatable {
    public let totalReps: Int
    /// 판정 항목이 하나라도 있었던 rep 수.
    public let judgedReps: Int
    public let findings: [Finding]
    /// 🔴 **못 본 것을 반드시 말한다** — 말하지 않으면 "피드백 없음"이 "전부 괜찮다"로 읽힌다.
    public let notJudged: [NotJudged]
    public let depth: DepthSummary?

    public var noFindings: Bool { judgedReps > 0 && findings.isEmpty }
    public var topFinding: Finding? { findings.first }
}

public struct Finding: Sendable, Equatable {
    public let warning: FormWarning
    public let repCount: Int
    /// 🔴 **분모는 그 항목을 판정한 rep 수다.** 전체 rep이 아니다 — 정면 6 + 측면 4로 찍으면
    /// 무릎 문제의 분모는 6이다. 10으로 쓰면 심각도가 희석돼 보인다.
    public let judgedReps: Int
    public let side: Side?
    public let phase: RepPhase?

    /// 전부에서 났는가. 임계값이 아니라 `count == denominator`라는 **사실**이다.
    public var everyRep: Bool { judgedReps > 0 && repCount == judgedReps }
}

/// 경고가 난 구간.
///
/// "무릎이 모여요"와 "무릎이 벌어져요"는 한 세션에 함께 나올 수 있다 — 내려갈 때와 올라올
/// 때가 다른 사람이 있다. **언제인지를 말하지 않으면 사용자는 둘 중 무엇을 언제 고쳐야
/// 하는지 알 수 없다.**
public enum RepPhase: String, Sendable, CaseIterable {
    case descending, bottom, ascending, throughout

    /// 과반인 구간. **과반은 임계값이 아니라 "나머지 전부보다 많다"는 사실**이라
    /// 새로 정할 숫자가 없다. 과반이 없으면 `throughout`이다.
    ///
    /// 구간은 **rep 수로 센다**(프레임 수가 아니다 — 구간마다 길이가 달라 긴 구간이 항상 이긴다).
    public static func dominant(_ counts: [RepPhase: Int]) -> RepPhase? {
        let real = counts.filter { $0.key != .throughout && $0.value > 0 }
        if real.isEmpty { return nil }
        let total = real.values.reduce(0, +)
        guard let top = real.max(by: { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key.order > rhs.key.order
        }) else { return nil }
        return top.value * 2 > total ? top.key : .throughout
    }

    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

public struct NotJudged: Sendable, Equatable {
    public let warning: FormWarning
    public let reason: Reason

    public enum Reason: String, Sendable, CaseIterable {
        /// 이 촬영 방향에서는 볼 수 없는 항목.
        case cameraAngle
        /// 각도는 맞지만 판정된 rep이 없었다.
        case noJudgedRep
    }
}

public struct DepthSummary: Sendable, Equatable {
    public let judgedReps: Int
    public let averageScore: Float?
    public let levels: [DepthLevel: Int]
}

/// 리포트의 입력. rep 하나가 남긴 사실.
public struct ReportedRep: Sendable, Equatable {
    public let cameraAngle: CameraAngle
    public let checkedCount: Int
    public let warnings: Set<FormWarning>
    public let depthLevel: DepthLevel?
    public let depthScore: Float?
    public let kneeToeSide: Side?
    public let warningPhases: [FormWarning: Set<RepPhase>]

    public init(
        cameraAngle: CameraAngle, checkedCount: Int, warnings: Set<FormWarning>,
        depthLevel: DepthLevel? = nil, depthScore: Float? = nil, kneeToeSide: Side? = nil,
        warningPhases: [FormWarning: Set<RepPhase>] = [:]
    ) {
        self.cameraAngle = cameraAngle
        self.checkedCount = checkedCount
        self.warnings = warnings
        self.depthLevel = depthLevel
        self.depthScore = depthScore
        self.kneeToeSide = kneeToeSide
        self.warningPhases = warningPhases
    }
}

public enum SessionReporter {

    /// 좌우를 지목하는 기준. **잠정값이며, 틀려도 경고 자체는 바뀌지 않고 쪽만 빠진다.**
    /// 실측에서 어느 쪽이 나쁜지는 사람 안에서 90~100% 일관됐다(9세션 중 8개).
    static let sideDominance: Float = 0.75

    public static func build(reps: [ReportedRep]) -> SessionReport {
        let judged = reps.filter { $0.checkedCount > 0 }
        var denominators: [FormWarning: Int] = [:]
        for warning in FormWarning.allCases {
            denominators[warning] = judged.count {
                RepScorer.checksFor($0.cameraAngle).contains(warning)
            }
        }

        var findings: [Finding] = []
        for warning in FormWarning.allCases {
            let denominator = denominators[warning] ?? 0
            if denominator == 0 { continue }
            let hits = judged.filter { $0.warnings.contains(warning) }
            if hits.isEmpty { continue }
            findings.append(Finding(
                warning: warning,
                repCount: hits.count,
                judgedReps: denominator,
                side: dominantSide(warning: warning, hits: hits),
                phase: dominantPhase(warning: warning, hits: hits)
            ))
        }
        // 잦은 것부터. 같으면 비율이 높은 쪽.
        findings.sort { lhs, rhs in
            if lhs.repCount != rhs.repCount { return lhs.repCount > rhs.repCount }
            return Float(lhs.repCount) / Float(lhs.judgedReps)
                > Float(rhs.repCount) / Float(rhs.judgedReps)
        }

        let notJudged: [NotJudged] = FormWarning.allCases.compactMap { warning in
            if !reps.contains(where: { RepScorer.checksFor($0.cameraAngle).contains(warning) }) {
                return NotJudged(warning: warning, reason: .cameraAngle)
            }
            if (denominators[warning] ?? 0) == 0 {
                return NotJudged(warning: warning, reason: .noJudgedRep)
            }
            return nil
        }

        return SessionReport(
            totalReps: reps.count,
            judgedReps: judged.count,
            findings: findings,
            notJudged: notJudged,
            depth: depthSummary(of: judged)
        )
    }

    private static func dominantSide(warning: FormWarning, hits: [ReportedRep]) -> Side? {
        guard warning == .kneeValgus || warning == .kneeFlared else { return nil }
        let sides = hits.compactMap(\.kneeToeSide)
        if sides.isEmpty { return nil }
        let left = sides.count { $0 == .left }
        let dominant: Side = left * 2 >= sides.count ? .left : .right
        let share = Float(sides.count { $0 == dominant }) / Float(sides.count)
        return share >= sideDominance ? dominant : nil
    }

    private static func dominantPhase(warning: FormWarning, hits: [ReportedRep]) -> RepPhase? {
        var counts: [RepPhase: Int] = [:]
        for rep in hits {
            for phase in rep.warningPhases[warning] ?? [] {
                counts[phase, default: 0] += 1
            }
        }
        return RepPhase.dominant(counts)
    }

    private static func depthSummary(of judged: [ReportedRep]) -> DepthSummary? {
        let withDepth = judged.filter { $0.depthLevel != nil }
        if withDepth.isEmpty { return nil }
        let scores = withDepth.compactMap(\.depthScore)
        var levels: [DepthLevel: Int] = [:]
        for rep in withDepth { levels[rep.depthLevel!, default: 0] += 1 }
        return DepthSummary(
            judgedReps: withDepth.count,
            averageScore: scores.isEmpty ? nil : StandingCalibration.average(scores),
            levels: levels
        )
    }
}

private extension Array {
    func count(where predicate: (Element) -> Bool) -> Int {
        reduce(0) { predicate($1) ? $0 + 1 : $0 }
    }
}
