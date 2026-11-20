import XCTest
@testable import PoseEngine

final class SessionReportTests: XCTestCase {

    private func rep(
        _ angle: CameraAngle = .front,
        warnings: Set<FormWarning> = [],
        depth: DepthLevel? = nil,
        depthScore: Float? = nil,
        side: Side? = nil,
        checked: Int? = nil,
        phases: [FormWarning: Set<RepPhase>] = [:]
    ) -> ReportedRep {
        ReportedRep(
            cameraAngle: angle,
            checkedCount: checked ?? RepScorer.checksFor(angle).count,
            warnings: warnings, depthLevel: depth, depthScore: depthScore,
            kneeToeSide: side, warningPhases: phases
        )
    }

    /// 🔴 **분모는 그 항목을 판정한 rep 수다** — 전체로 나누면 심각도가 희석돼 보인다.
    func test_항목별_분모는_그_항목을_판정한_rep_수다() throws {
        let reps = (0..<6).map { _ in rep(.front, warnings: [.kneeValgus]) }
            + (0..<4).map { _ in rep(.side, warnings: [.shallowDepth]) }
        let report = SessionReporter.build(reps: reps)
        let knee = try XCTUnwrap(report.findings.first { $0.warning == .kneeValgus })
        let depth = try XCTUnwrap(report.findings.first { $0.warning == .shallowDepth })
        XCTAssertEqual(report.totalReps, 10, "전체는 10 rep")
        XCTAssertEqual(knee.judgedReps, 6, "무릎 분모는 정면 6")
        XCTAssertEqual(depth.judgedReps, 4, "깊이 분모는 측면 4")
    }

    func test_판정_불가_rep은_분모에서_뺀다() throws {
        let reps = (0..<3).map { _ in rep(.side, warnings: [.shallowDepth]) }
            + (0..<7).map { _ in rep(.side, checked: 0) }
        let report = SessionReporter.build(reps: reps)
        XCTAssertEqual(report.totalReps, 10)
        XCTAssertEqual(report.judgedReps, 3)
        XCTAssertEqual(try XCTUnwrap(report.findings.first).judgedReps, 3)
    }

    /// 순서를 빈도로 정하면 **새 임계값이 필요 없다.**
    func test_잦은_문제가_먼저_온다() throws {
        let reps = (0..<10).map { i in
            rep(.side, warnings: i < 8 ? [.excessiveLean] : [.shallowDepth, .excessiveLean])
        }
        let report = SessionReporter.build(reps: reps)
        let top = try XCTUnwrap(report.topFinding)
        XCTAssertEqual(top.warning, .excessiveLean)
        XCTAssertEqual(top.repCount, 10)
        XCTAssertEqual(report.findings[1].warning, .shallowDepth)
    }

    /// `everyRep`은 임계값이 아니라 `count == denominator`라는 사실이다.
    func test_전부에서_났을_때만_everyRep이다() throws {
        let all = SessionReporter.build(
            reps: (0..<5).map { _ in rep(.side, warnings: [.shallowDepth]) })
        let some = SessionReporter.build(
            reps: (0..<5).map { i in rep(.side, warnings: i < 4 ? [.shallowDepth] : []) })
        XCTAssertTrue(try XCTUnwrap(all.findings.first).everyRep)
        XCTAssertFalse(try XCTUnwrap(some.findings.first).everyRep)
    }

    /// 🔴 **못 본 것을 반드시 말한다.**
    func test_각도가_지원하지_않는_항목을_보고한다() {
        let report = SessionReporter.build(reps: (0..<5).map { _ in rep(.front) })
        let byAngle = Set(report.notJudged.filter { $0.reason == .cameraAngle }.map(\.warning))
        XCTAssertEqual(byAngle, [.shallowDepth, .excessiveLean, .heelRise, .kneePastToe])
        XCTAssertFalse(report.notJudged.contains { $0.warning == .kneeValgus },
                       "정면 항목은 못 본 목록에 없다")
    }

    func test_각도는_맞지만_판정된_rep이_없으면_이유가_다르다() {
        let report = SessionReporter.build(reps: (0..<5).map { _ in rep(.side, checked: 0) })
        XCTAssertEqual(report.judgedReps, 0)
        XCTAssertTrue(report.notJudged.filter { $0.warning == .shallowDepth }
            .allSatisfy { $0.reason == .noJudgedRep })
    }

    func test_두_각도를_다_찍으면_못_본_항목이_없다() {
        let reps = (0..<3).map { _ in rep(.front) } + (0..<3).map { _ in rep(.side) }
        let report = SessionReporter.build(reps: reps)
        XCTAssertTrue(report.notJudged.isEmpty)
        XCTAssertTrue(report.noFindings)
    }

    // ── 구간 ────────────────────────────────────────────────

    /// **구간이 다르면 고치는 방법도 다르다.**
    func test_두_방향이_다른_구간에_나면_각각_그_구간으로_말한다() throws {
        let reps = (0..<10).map { _ in
            rep(.front, warnings: [.kneeFlared, .kneeValgus],
                phases: [.kneeFlared: [.descending], .kneeValgus: [.ascending]])
        }
        let report = SessionReporter.build(reps: reps)
        XCTAssertEqual(try XCTUnwrap(report.findings.first { $0.warning == .kneeFlared }).phase,
                       .descending)
        XCTAssertEqual(try XCTUnwrap(report.findings.first { $0.warning == .kneeValgus }).phase,
                       .ascending)
    }

    func test_구간이_몰리지_않으면_동작_내내로_본다() throws {
        let reps = (0..<6).map { i -> ReportedRep in
            let phase: RepPhase = i % 3 == 0 ? .descending : (i % 3 == 1 ? .bottom : .ascending)
            return rep(.front, warnings: [.kneeValgus], phases: [.kneeValgus: [phase]])
        }
        XCTAssertEqual(try XCTUnwrap(SessionReporter.build(reps: reps).findings.first).phase,
                       .throughout)
    }

    /// **구간을 기록하지 않은 과거 기록은 아무것도 말하지 않는다** — 모를 때 지어내지 않는다.
    func test_구간을_모르면_말하지_않는다() throws {
        let reps = (0..<5).map { _ in rep(.front, warnings: [.kneeValgus]) }
        XCTAssertNil(try XCTUnwrap(SessionReporter.build(reps: reps).findings.first).phase)
    }

    func test_한_rep이_여러_구간에_걸치면_구간마다_센다() throws {
        let reps = (0..<5).map { _ in
            rep(.front, warnings: [.kneeValgus], phases: [.kneeValgus: [.descending, .bottom]])
        }
        XCTAssertEqual(try XCTUnwrap(SessionReporter.build(reps: reps).findings.first).phase,
                       .throughout)
    }

    // ── 좌우 ────────────────────────────────────────────────

    func test_한쪽에_몰리면_그_쪽을_지목한다() throws {
        let reps = (0..<10).map { i in
            rep(.front, warnings: [.kneeValgus], side: i < 9 ? .left : .right)
        }
        XCTAssertEqual(try XCTUnwrap(SessionReporter.build(reps: reps).findings.first).side, .left)
    }

    /// 틀려도 경고 자체는 바뀌지 않고 **쪽만 빠진다.**
    func test_좌우가_섞이면_쪽을_지목하지_않는다() throws {
        let reps = (0..<10).map { i in
            rep(.front, warnings: [.kneeValgus], side: i % 2 == 0 ? .left : .right)
        }
        XCTAssertNil(try XCTUnwrap(SessionReporter.build(reps: reps).findings.first).side)
    }

    func test_무릎이_아닌_항목에는_쪽을_붙이지_않는다() throws {
        let reps = (0..<5).map { _ in rep(.side, warnings: [.shallowDepth], side: .left) }
        XCTAssertNil(try XCTUnwrap(SessionReporter.build(reps: reps).findings.first).side)
    }

    // ── 깊이 요약 ───────────────────────────────────────────

    func test_깊이_요약은_깊이를_판정한_rep만_센다() throws {
        let reps = [
            rep(.side, depth: .shallow, depthScore: 0.6),
            rep(.side, depth: .parallel, depthScore: 1.0),
            rep(.side, depth: nil, depthScore: nil),
        ]
        let depth = try XCTUnwrap(SessionReporter.build(reps: reps).depth)
        XCTAssertEqual(depth.judgedReps, 2)
        XCTAssertEqual(try XCTUnwrap(depth.averageScore), 0.8, accuracy: 0.001)
        XCTAssertEqual(depth.levels[.shallow], 1)
        XCTAssertEqual(depth.levels[.parallel], 1)
    }

    func test_깊이를_못_본_세션에는_깊이_요약이_없다() {
        XCTAssertNil(SessionReporter.build(reps: (0..<5).map { _ in rep(.front) }).depth)
    }

    /// **rep이 없으면 아무것도 주장하지 않는다.**
    func test_rep이_없으면_아무것도_주장하지_않는다() {
        let report = SessionReporter.build(reps: [])
        XCTAssertEqual(report.totalReps, 0)
        XCTAssertEqual(report.judgedReps, 0)
        XCTAssertTrue(report.findings.isEmpty)
        XCTAssertFalse(report.noFindings, "판정한 rep이 0이면 noFindings도 false다")
        XCTAssertNil(report.topFinding)
    }
}
