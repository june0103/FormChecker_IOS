import XCTest
@testable import PoseEngine

final class RepStateMachineTests: XCTestCase {

    private let frameMs: Int64 = 33   // 30fps

    /// 각도 시퀀스를 **프로덕션과 같은 스무딩 경로**로 흘려보낸다.
    private func run(
        angles: [Float?],
        thresholds: CountingThresholds = .default,
        stepMs: Int64? = nil
    ) -> (machine: RepStateMachine, events: [RepEvent]) {
        let step = stepMs ?? frameMs
        let machine = RepStateMachine(thresholds: thresholds)
        let ema = AngleEma(timeConstantMs: 120)
        let median = MedianWindow(size: 5)
        var events: [RepEvent] = []

        for (i, angle) in angles.enumerated() {
            let t = Int64(i) * step
            let frame = RepFrame(
                timestampMs: t,
                rawKneeAngle: angle,
                smoothedKneeAngle: ema.update(angle, timestampMs: t),
                medianKneeAngle: median.push(angle),
                leftKneeAngle: angle,
                rightKneeAngle: angle,
                hipAngle: angle.map { $0 * 0.9 },
                torsoLeanDegrees: 30,
                kneeAsymmetryDegrees: 2,
                kneeSpreadRatio: angle.map { 0.86 + (170 - $0) / 170 * 1.1 },
                leftFoot: nil, rightFoot: nil,
                minLegConfidence: angle == nil ? 0 : 0.9
            )
            if let event = machine.update(frame) { events.append(event) }
        }
        return (machine, events)
    }

    /// 선 자세 → 사인 곡선으로 앉았다 일어남 → 선 자세.
    private func squat(bottomAngle: Float, moveFrames: Int = 60, standFrames: Int = 20) -> [Float?] {
        var out: [Float?] = Array(repeating: 170, count: standFrames)
        for i in 0..<moveFrames {
            let phase = Double.pi * Double(i) / Double(moveFrames - 1)
            out.append(Float(170.0 - (170.0 - Double(bottomAngle)) * sin(phase)))
        }
        out += Array(repeating: 170, count: standFrames)
        return out
    }

    private func completed(_ events: [RepEvent]) -> [RepSummary] {
        events.compactMap { if case .completed(let s) = $0 { return s } else { return nil } }
    }

    private func aborts(_ events: [RepEvent]) -> [RepEvent.AbortReason] {
        events.compactMap { if case .aborted(_, let r, _) = $0 { return r } else { return nil } }
    }

    private func startedCount(_ events: [RepEvent]) -> Int {
        events.count { if case .started = $0 { return true } else { return false } }
    }

    // ── 카운팅 ──────────────────────────────────────────────

    func test_깊은_스쿼트_한_번은_rep_1개로_센다() {
        let (machine, events) = run(angles: squat(bottomAngle: 80))
        XCTAssertEqual(machine.completedReps, 1)
        XCTAssertEqual(startedCount(events), 1)
        XCTAssertEqual(completed(events).count, 1)
        XCTAssertEqual(machine.state, .standing)
    }

    func test_연속_세_번은_rep_3개로_센다() {
        var angles: [Float?] = Array(repeating: 170, count: 20)
        for _ in 0..<3 {
            angles += squat(bottomAngle: 80, standFrames: 15).dropFirst(15)
        }
        XCTAssertEqual(run(angles: angles).machine.completedReps, 3)
    }

    /// 🔴 **얕은 스쿼트도 센다** — 세지 않으면 카운터가 멈춘 것처럼 보인다. 세고, 경고한다.
    func test_얕은_스쿼트도_카운팅_임계값을_통과하면_센다() throws {
        let (machine, events) = run(angles: squat(bottomAngle: 125))
        XCTAssertEqual(machine.completedReps, 1, "얕아도 rep으로 센다")
        let summary = try XCTUnwrap(completed(events).first)
        XCTAssertNotNil(summary.aggregate.minKneeAngle, "rep 요약은 최저 각도를 남긴다")
        XCTAssertEqual(FormThresholds().depthLevel(byShinDepth: -0.242), .shallow,
                       "P001 실측 최저점(정강이 기준 −0.242)은 깊이 부족이다")
    }

    func test_최저_임계값에_못_미치면_rep으로_세지_않는다() {
        let (machine, events) = run(angles: squat(bottomAngle: 140))
        XCTAssertEqual(machine.completedReps, 0)
        XCTAssertTrue(aborts(events).contains(.notDeepEnough))
    }

    func test_노이즈가_있어도_한_번_앉으면_rep_1개다() {
        let noisy = squat(bottomAngle: 80).enumerated().map { i, a in
            a.map { $0 + (i % 2 == 0 ? 8 : -8) }
        }
        XCTAssertEqual(run(angles: noisy).machine.completedReps, 1)
    }

    /// `minHoldMs`가 없으면 최저점 근처 진동이 rep을 쪼갠다.
    func test_최저점_부근_진동으로_rep이_쪼개지지_않는다() {
        var angles: [Float?] = Array(repeating: 170, count: 20)
        for i in 0..<20 { angles.append(170 - Float(i) * 4.5) }           // 하강
        for i in 0..<20 { angles.append(i % 2 == 0 ? 82 : 126) }          // 최저점 근처 진동
        for i in 0..<20 { angles.append(80 + Float(i) * 4.5) }            // 상승
        angles += Array(repeating: 170, count: 20)
        XCTAssertEqual(run(angles: angles).machine.completedReps, 1)
    }

    // ── 중단 ────────────────────────────────────────────────

    func test_너무_빠른_동작은_반동으로_보고_세지_않는다() throws {
        let strict = try CountingThresholds(minHoldMs: 0, minRepDurationMs: 5_000)
        let (machine, events) = run(angles: squat(bottomAngle: 80, moveFrames: 30),
                                    thresholds: strict)
        XCTAssertEqual(machine.completedReps, 0)
        XCTAssertTrue(aborts(events).contains(.tooFast),
                      "TOO_FAST로 중단돼야 한다 (발생: \(aborts(events)))")
    }

    func test_최소_지속시간을_낮추면_같은_동작이_카운트된다() throws {
        let lenient = try CountingThresholds(minHoldMs: 0, minRepDurationMs: 100)
        XCTAssertEqual(run(angles: squat(bottomAngle: 80, moveFrames: 30),
                           thresholds: lenient).machine.completedReps, 1)
    }

    func test_너무_오래_걸리면_타임아웃으로_중단한다() throws {
        let quick = try CountingThresholds(maxRepDurationMs: 500)
        let (machine, events) = run(angles: squat(bottomAngle: 80, moveFrames: 60),
                                    thresholds: quick)
        XCTAssertEqual(machine.completedReps, 0)
        XCTAssertTrue(aborts(events).contains(.timeout))
    }

    func test_짧은_가림은_rep을_끊지_않는다() {
        var angles = squat(bottomAngle: 80)
        angles[45] = nil; angles[46] = nil; angles[47] = nil
        XCTAssertEqual(run(angles: angles).machine.completedReps, 1)
    }

    func test_긴_가림은_rep을_포기한다() {
        var angles = squat(bottomAngle: 80)
        for i in 40..<85 { angles[i] = nil }
        let (machine, events) = run(angles: angles)
        XCTAssertEqual(machine.completedReps, 0)
        XCTAssertTrue(aborts(events).contains(.poseLost),
                      "POSE_LOST로 중단돼야 한다 (발생: \(aborts(events)))")
    }

    // ── 요약 ────────────────────────────────────────────────

    func test_요약에_최저점과_최상점이_모두_담긴다() throws {
        let summary = try XCTUnwrap(completed(run(angles: squat(bottomAngle: 80)).events).first)
        let top = try XCTUnwrap(summary.top, "top 기준값이 있어야 delta_top 특징을 계산할 수 있다")
        let bottom = try XCTUnwrap(summary.bottom)
        XCTAssertLessThan(try XCTUnwrap(bottom.kneeAngle), try XCTUnwrap(top.kneeAngle),
                          "최저점 각도가 최상점보다 작아야 한다")
    }

    func test_무릎폭_비율이_최상점과_최저점에_모두_담긴다() throws {
        let summary = try XCTUnwrap(completed(run(angles: squat(bottomAngle: 80)).events).first)
        let standing = try XCTUnwrap(summary.top?.kneeSpreadRatio, "선 자세 기준선이 없으면 판정할 수 없다")
        let bottom = try XCTUnwrap(summary.bottom?.kneeSpreadRatio, "최저점 값이 없으면 판정할 수 없다")
        XCTAssertGreaterThan(bottom, standing, "앉으면 무릎폭 비율이 커진다")
        XCTAssertEqual(FormThresholds().kneeAlignment(standingRatio: standing, bottomRatio: bottom),
                       .good)
    }

    func test_가동범위와_구간_길이가_계산된다() throws {
        let agg = try XCTUnwrap(completed(run(angles: squat(bottomAngle: 80)).events).first).aggregate
        XCTAssertGreaterThan(try XCTUnwrap(agg.kneeRangeOfMotion), 60, "가동범위가 60도 이상이어야 한다")
        XCTAssertNotNil(agg.descentDurationMs)
        XCTAssertNotNil(agg.ascentDurationMs)
        XCTAssertNotNil(agg.maxAngularVelocityDegPerSec)
    }

    /// 각속도는 **시간으로 나누므로** fps가 절반이면 값도 대략 절반이다.
    func test_각속도는_분석_fps에_영향받지_않는다() throws {
        func velocity(stepMs: Int64) throws -> Float {
            let events = run(angles: squat(bottomAngle: 80), stepMs: stepMs).events
            return try XCTUnwrap(completed(events).first?.aggregate.maxAngularVelocityDegPerSec)
        }
        let at30fps = try velocity(stepMs: 33)
        let at15fps = try velocity(stepMs: 66)
        XCTAssertLessThan(at15fps, at30fps * 0.7,
                          "fps가 절반이면 각속도도 대략 절반이어야 한다 (30fps=\(at30fps), 15fps=\(at15fps))")
    }

    func test_가림이_섞이면_유효_프레임_비율이_1보다_작다() throws {
        var angles = squat(bottomAngle: 80)
        angles[45] = nil; angles[46] = nil
        let agg = try XCTUnwrap(completed(run(angles: angles).events).first).aggregate
        XCTAssertLessThan(agg.validFrameRatio, 1, "실제: \(agg.validFrameRatio)")
        XCTAssertGreaterThan(agg.validFrameRatio, 0.8)
    }

    // ── 상태 ────────────────────────────────────────────────

    func test_각도가_없으면_IDLE에서_시작한다() {
        let (machine, events) = run(angles: Array(repeating: nil, count: 10))
        XCTAssertEqual(machine.state, .idle)
        XCTAssertTrue(events.isEmpty)
    }

    func test_reset하면_진행_중인_rep이_버려진다() {
        let machine = RepStateMachine()
        let ema = AngleEma(timeConstantMs: 120)
        let median = MedianWindow(size: 5)
        for (i, a) in squat(bottomAngle: 80).prefix(40).enumerated() {
            let t = Int64(i) * frameMs
            _ = machine.update(RepFrame(
                timestampMs: t, rawKneeAngle: a,
                smoothedKneeAngle: ema.update(a, timestampMs: t),
                medianKneeAngle: median.push(a),
                leftKneeAngle: a, rightKneeAngle: a, hipAngle: a,
                torsoLeanDegrees: 30, kneeAsymmetryDegrees: 2,
                kneeSpreadRatio: nil, leftFoot: nil, rightFoot: nil, minLegConfidence: 0.9
            ))
        }
        machine.reset()
        XCTAssertEqual(machine.state, .idle)
        XCTAssertEqual(machine.completedReps, 0)
    }

    // ── 임계값 불변식 ───────────────────────────────────────

    func test_히스테리시스가_성립하지_않는_설정은_거부한다() {
        XCTAssertThrowsError(
            try CountingThresholds(standingEnterAngle: 150, standingExitAngle: 150))
    }

    func test_최저_임계값이_하강_임계값보다_크면_거부한다() {
        XCTAssertThrowsError(
            try CountingThresholds(standingExitAngle: 145, repBottomAngle: 150))
    }

    func test_카운팅_임계값을_낮추면_더_얕은_동작도_센다() throws {
        let lenient = try CountingThresholds(
            standingEnterAngle: 160, standingExitAngle: 152, repBottomAngle: 145)
        XCTAssertEqual(run(angles: squat(bottomAngle: 140)).machine.completedReps, 0,
                       "기본 임계값(130도)에서는 140도까지만 내려가면 세지 않는다")
        XCTAssertEqual(run(angles: squat(bottomAngle: 140), thresholds: lenient)
            .machine.completedReps, 1, "임계값을 145도로 올리면 센다")
    }
}

private extension Array {
    func count(where predicate: (Element) -> Bool) -> Int {
        reduce(0) { predicate($1) ? $0 + 1 : $0 }
    }
}
