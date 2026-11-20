import GRDB
import PoseEngine
import XCTest
@testable import Storage

/// 저장 계층. **스키마가 Android(와 Supabase DDL)와 같은 모양인지**를 붙든다.
final class WorkoutRepositoryTests: XCTestCase {

    private var folder: URL!
    private var repository: WorkoutRepository!

    override func setUpWithError() throws {
        folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let queue = try AppDatabase.makeQueue(at: folder.appendingPathComponent("test.sqlite"))
        repository = WorkoutRepository(queue: queue)
    }

    override func tearDownWithError() throws {
        repository = nil
        try? FileManager.default.removeItem(at: folder)
    }

    // ── 재료 ────────────────────────────────────────────────

    private func session(id: String = UUID().uuidString, startedAt: Int64 = 1_700_000_000_000)
        -> WorkoutSession {
        WorkoutSession(id: id, startedAt: startedAt, endedAt: startedAt + 60_000)
    }

    private func rep(
        number: Int, warned: Int = 0, checked: Int = 4,
        angle: CameraAngle = .side, warnings: Set<FormWarning> = [],
        depth: DepthLevel? = .parallel, phases: [FormWarning: Set<RepPhase>] = [:]
    ) -> RepRecord {
        RepRecord(
            id: UUID().uuidString, setId: "", repNumber: number,
            recordedAt: 1_700_000_000_000, durationMs: 1_800,
            depthScore: 0.9, formScore: nil,
            checkedCount: checked, warnedCount: warned,
            errorFlags: RepRecordMapping.errorFlags(warnings, checks: RepScorer.checksFor(angle)),
            cameraAngle: angle.rawValue,
            depthLevel: depth?.rawValue, depthBasis: DepthBasis.hipHeight.rawValue,
            depthRatio: -0.01, minKneeAngle: 85, maxTorsoLean: 30,
            validFrameRatio: 1, kneeToeSide: nil,
            warningPhases: RepRecordMapping.phases(phases)
        )
    }

    // ── 저장 ────────────────────────────────────────────────

    func test_세션과_rep을_저장하고_다시_읽는다() throws {
        let made = session()
        try repository.save(session: made, reps: [rep(number: 1), rep(number: 2)], metrics: nil)

        XCTAssertEqual(try repository.session(id: made.id)?.id, made.id)
        let reps = try repository.reps(sessionId: made.id)
        XCTAssertEqual(reps.count, 2)
        XCTAssertEqual(reps.map(\.repNumber), [1, 2])
    }

    /// 🔴 **`form_score`는 항상 nil이다** — 점수 대신 사실(`checked`/`warned`)을 센다.
    func test_폼_점수는_저장하지_않는다() throws {
        let made = session()
        try repository.save(session: made, reps: [rep(number: 1)], metrics: nil)
        XCTAssertNil(try repository.reps(sessionId: made.id).first?.formScore)
    }

    /// 어느 기준으로 판정했는지가 rep마다 남아야 **나중에 재분석할 수 있다.**
    func test_판정_기준이_rep마다_남는다() throws {
        let made = session()
        var record = rep(number: 1)
        record.relaxedForm = false
        record.kneeTolerance = 0.10
        record.shallowTolerance = 0.03
        try repository.save(session: made, reps: [record], metrics: nil)

        let stored = try XCTUnwrap(try repository.reps(sessionId: made.id).first)
        XCTAssertEqual(stored.relaxedForm, false)
        XCTAssertEqual(try XCTUnwrap(stored.kneeTolerance), 0.10, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(stored.shallowTolerance), 0.03, accuracy: 1e-9)
    }

    func test_모든_행이_PENDING으로_쌓인다() throws {
        let made = session()
        try repository.save(session: made, reps: [rep(number: 1), rep(number: 2)], metrics: nil)
        // 세션 1 + rep 2
        XCTAssertEqual(try repository.pendingCount(), 3)
    }

    // ── 삭제 ────────────────────────────────────────────────

    /// 🔴 외래키를 켜지 않으면 `ON DELETE CASCADE`가 **조용히 동작하지 않는다.**
    func test_세션을_지우면_세트와_rep도_함께_지워진다() throws {
        let made = session()
        try repository.save(session: made, reps: [rep(number: 1), rep(number: 2)], metrics: nil)
        XCTAssertTrue(try repository.delete(sessionId: made.id))

        XCTAssertNil(try repository.session(id: made.id))
        XCTAssertTrue(try repository.reps(sessionId: made.id).isEmpty)
        XCTAssertEqual(try repository.pendingCount(), 0)
    }

    // ── 집계 ────────────────────────────────────────────────

    /// 🔴 **rep 행을 화면으로 끌어오지 않는다** — DB가 집계해서 한 줄로 준다.
    func test_목록은_횟수와_피드백_횟수를_집계한다() throws {
        let made = session(startedAt: 1_700_000_100_000)
        try repository.save(session: made, reps: [
            rep(number: 1, warned: 0),
            rep(number: 2, warned: 1),
            rep(number: 3, warned: 2),
        ], metrics: nil)

        let item = try XCTUnwrap(try repository.recentSessions().first)
        XCTAssertEqual(item.repCount, 3)
        XCTAssertEqual(item.warnedRepCount, 2, "경고가 난 rep 수지 경고 개수의 합이 아니다")
        XCTAssertEqual(item.pendingCount, 3)
    }

    func test_rep이_없는_세션도_목록에_나온다() throws {
        // 저장소는 거르지 않는다 — 0회를 막는 것은 호출부(운동 화면)의 몫이다.
        let made = session()
        try repository.save(session: made, reps: [], metrics: nil)
        let item = try XCTUnwrap(try repository.recentSessions().first)
        XCTAssertEqual(item.repCount, 0)
    }

    func test_최근_세션이_먼저_온다() throws {
        try repository.save(session: session(startedAt: 1_000), reps: [], metrics: nil)
        try repository.save(session: session(startedAt: 3_000), reps: [], metrics: nil)
        try repository.save(session: session(startedAt: 2_000), reps: [], metrics: nil)
        XCTAssertEqual(try repository.recentSessions().map(\.startedAt), [3_000, 2_000, 1_000])
    }

    // ── 매핑 ────────────────────────────────────────────────

    /// 저장과 화면이 **같은 매핑**을 써야 다른 답이 나오지 않는다.
    func test_경고_플래그가_왕복한다() {
        let warnings: Set<FormWarning> = [.kneeValgus, .hipShift]
        let text = RepRecordMapping.errorFlags(warnings, checks: RepScorer.checksFor(.front))
        XCTAssertEqual(RepRecordMapping.warnings(fromFlags: text), warnings)
    }

    /// 판정하지 않은 항목은 **플래그에 키조차 없어야** 한다.
    func test_판정하지_않은_항목은_플래그에_없다() throws {
        let text = RepRecordMapping.errorFlags([.kneeValgus], checks: RepScorer.checksFor(.front))
        let data = try XCTUnwrap(text.data(using: .utf8))
        let flags = try JSONDecoder().decode([String: Bool].self, from: data)
        XCTAssertNotNil(flags[FormWarning.kneeValgus.rawValue])
        XCTAssertNil(flags[FormWarning.shallowDepth.rawValue], "정면에서는 깊이를 재지 않는다")
    }

    func test_구간이_왕복한다() {
        let map: [FormWarning: Set<RepPhase>] = [
            .kneeValgus: [.ascending], .kneeFlared: [.descending, .bottom],
        ]
        let text = RepRecordMapping.phases(map)
        XCTAssertEqual(RepRecordMapping.phases(fromJSON: text), map)
    }

    /// **구간을 기록하지 않은 과거 기록은 아무것도 말하지 않는다** — 모를 때 지어내지 않는다.
    func test_구간이_없으면_빈_값이다() {
        XCTAssertNil(RepRecordMapping.phases([:]))
        XCTAssertTrue(RepRecordMapping.phases(fromJSON: nil).isEmpty)
    }

    // ── 리포트 연결 ─────────────────────────────────────────

    func test_저장한_기록으로_리포트를_만든다() throws {
        let made = session()
        try repository.save(session: made, reps: [
            rep(number: 1, warned: 1, angle: .front, warnings: [.kneeValgus],
                depth: nil, phases: [.kneeValgus: [.descending]]),
            rep(number: 2, warned: 1, angle: .front, warnings: [.kneeValgus],
                depth: nil, phases: [.kneeValgus: [.descending]]),
            rep(number: 3, warned: 0, angle: .front, depth: nil),
        ], metrics: nil)

        let records = try repository.reps(sessionId: made.id)
        let report = SessionReporter.build(reps: records.map(RepRecordMapping.reported))

        XCTAssertEqual(report.totalReps, 3)
        let finding = try XCTUnwrap(report.findings.first)
        XCTAssertEqual(finding.warning, .kneeValgus)
        XCTAssertEqual(finding.repCount, 2)
        XCTAssertEqual(finding.judgedReps, 3, "분모는 그 항목을 판정한 rep 수다")
        XCTAssertEqual(finding.phase, .descending, "구간이 살아서 넘어와야 한다")
        // 정면으로만 찍었으니 측면 항목은 "못 봤다"로 남아야 한다.
        XCTAssertTrue(report.notJudged.contains { $0.warning == .shallowDepth })
    }
}
