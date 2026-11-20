import XCTest
@testable import PoseEngine

/// 준비 자세 점검. 🔴 **막는 항목이 오탐하면 사용자가 앱을 아예 쓸 수 없다.**
final class ReadyPostureTests: XCTestCase {

    private let aspect: Float = 0.75

    private func frontPose(
        ankleHalfWidth: Float = 0.10, kneeOffset: Float = 0, hipCenterX: Float = 0.50,
        toeOutward: Float = 0.06, toeConfidence: Float = 0.9, confidence: Float = 0.9
    ) -> Pose {
        let straightKnee = (0.06 + ankleHalfWidth) / 2
        let leftHeelX = 0.50 + ankleHalfWidth
        let rightHeelX = 0.50 - ankleHalfWidth
        var points: [KeypointType: PoseFixtures.Point] = [
            .leftShoulder: (0.32, 0.30, confidence), .rightShoulder: (0.68, 0.30, confidence),
            .leftHip: (hipCenterX - 0.06, 0.50, confidence),
            .rightHip: (hipCenterX + 0.06, 0.50, confidence),
            .leftKnee: (0.50 - straightKnee - kneeOffset, 0.70, confidence),
            .rightKnee: (0.50 + straightKnee + kneeOffset, 0.70, confidence),
            .leftAnkle: (0.50 - ankleHalfWidth, 0.90, confidence),
            .rightAnkle: (0.50 + ankleHalfWidth, 0.90, confidence),
            .neck: (0.50, 0.32, confidence),
            .leftHeel: (leftHeelX, 0.94, toeConfidence),
            .rightHeel: (rightHeelX, 0.94, toeConfidence),
        ]
        for type in [KeypointType.leftBigToe, .leftSmallToe] {
            points[type] = (leftHeelX + toeOutward, 0.94, toeConfidence)
        }
        for type in [KeypointType.rightBigToe, .rightSmallToe] {
            points[type] = (rightHeelX - toeOutward, 0.94, toeConfidence)
        }
        return PoseFixtures.pose(points)
    }

    private func sidePose() -> Pose {
        var points: [KeypointType: PoseFixtures.Point] = [
            .leftShoulder: (0.48, 0.30, 0.9), .rightShoulder: (0.52, 0.30, 0.9),
            .leftHip: (0.49, 0.50, 0.9), .rightHip: (0.51, 0.50, 0.9),
            .leftKnee: (0.50, 0.70, 0.9), .rightKnee: (0.50, 0.70, 0.9),
            .leftAnkle: (0.50, 0.90, 0.9), .rightAnkle: (0.50, 0.90, 0.9),
            .neck: (0.50, 0.32, 0.9),
            .leftHeel: (0.48, 0.94, 0.9), .rightHeel: (0.48, 0.94, 0.9),
        ]
        for type in [KeypointType.leftBigToe, .leftSmallToe, .rightBigToe, .rightSmallToe] {
            points[type] = (0.56, 0.94, 0.9)
        }
        return PoseFixtures.pose(points)
    }

    private func frames(_ pose: Pose, count: Int = 5) -> [(pose: Pose, aspectRatio: Float)] {
        (0..<count).map { _ in (pose: pose, aspectRatio: aspect) }
    }

    private func evaluate(_ pose: Pose, _ angle: CameraAngle = .front) -> ReadyPosture {
        ReadyPosture.from(frames: frames(pose), cameraAngle: angle)
    }

    // ── 기본 ────────────────────────────────────────────────

    func test_프레임이_없으면_아무것도_판정하지_않는다() {
        let result = ReadyPosture.from(frames: [], cameraAngle: .front)
        XCTAssertEqual(result.framesUsed, 0)
        XCTAssertFalse(result.clean)
        XCTAssertTrue(result.issues.isEmpty)
    }

    // ── 발 간격 ─────────────────────────────────────────────

    func test_발_간격을_어깨_너비로_나눈다() throws {
        XCTAssertEqual(try XCTUnwrap(evaluate(frontPose()).stanceWidthByShoulder),
                       0.556, accuracy: 0.005)
    }

    func test_발이_어깨보다_좁으면_벌리라고_한다() {
        let result = evaluate(frontPose(ankleHalfWidth: 0.10))
        XCTAssertTrue(result.issues.contains(.stanceTooNarrow))
        XCTAssertFalse(result.issues.contains(.stanceTooWide))
    }

    func test_발이_어깨보다_넓으면_모으라고_한다() throws {
        let result = evaluate(frontPose(ankleHalfWidth: 0.30))
        XCTAssertEqual(try XCTUnwrap(result.stanceWidthByShoulder), 1.667, accuracy: 0.005)
        XCTAssertTrue(result.issues.contains(.stanceTooWide))
    }

    func test_어깨너비면_발_간격을_지적하지_않는다() throws {
        let result = evaluate(frontPose(ankleHalfWidth: 0.18))
        XCTAssertEqual(try XCTUnwrap(result.stanceWidthByShoulder), 1.0, accuracy: 0.005)
        XCTAssertFalse(result.issues.contains { $0.check == .stanceWidth })
    }

    /// ⚠ 이 허용폭은 **막는 판정 중 유일하게 `provisional`**이다.
    func test_발_간격_허용폭은_설정으로_바뀐다() {
        var strict = ReadyThresholds()
        strict.stanceNarrowLimit = 0.5
        strict.stanceWideLimit = 0.6
        let result = ReadyPosture.from(frames: frames(frontPose()), cameraAngle: .front,
                                       ready: strict)
        XCTAssertFalse(result.issues.contains { $0.check == .stanceWidth })
    }

    // ── 발끝 방향 ───────────────────────────────────────────

    func test_발끝이_안쪽을_향하면_지적한다() throws {
        let result = evaluate(frontPose(toeOutward: -0.06))
        XCTAssertLessThan(try XCTUnwrap(result.leftToeDirection), 0)
        XCTAssertTrue(result.issues.contains(.toesInward))
    }

    func test_발끝이_바깥을_향하면_지적하지_않는다() throws {
        let result = evaluate(frontPose())
        XCTAssertGreaterThan(try XCTUnwrap(result.leftToeDirection), 0)
        XCTAssertFalse(result.issues.contains { $0.check == .toeDirection })
    }

    /// 발이 원근으로 압축되면 방향을 믿을 수 없다.
    func test_발이_너무_짧게_보이면_발끝_방향을_판정하지_않는다() {
        XCTAssertNotNil(evaluate(frontPose()).leftToeDirection)
        var strict = ReadyThresholds()
        strict.minFootLengthRatio = 0.2
        let result = ReadyPosture.from(frames: frames(frontPose()), cameraAngle: .front,
                                       ready: strict)
        XCTAssertNil(result.leftToeDirection)
        XCTAssertEqual(result.notJudged[.toeDirection], .keypoints)
    }

    // ── 좌우 균형 ───────────────────────────────────────────

    func test_골반이_한쪽으로_쏠리면_지적한다() throws {
        let result = evaluate(frontPose(hipCenterX: 0.56))
        XCTAssertEqual(try XCTUnwrap(result.hipShiftRatio), 0.30, accuracy: 0.01)
        XCTAssertTrue(result.issues.contains(.weightOnOneSide))
    }

    func test_좌우_균형은_동작_판정과_같은_허용폭을_쓴다() {
        var loose = FormThresholds()
        loose.hipShiftLimit = 0.5
        let result = ReadyPosture.from(frames: frames(frontPose(hipCenterX: 0.56)),
                                       cameraAngle: .front, form: loose)
        XCTAssertFalse(result.issues.contains { $0.check == .weightBalance })
    }

    // ── 촬영 방향 ───────────────────────────────────────────

    func test_측면에서는_정면_전용_항목을_촬영_각도_때문에_못_본다고_말한다() {
        let result = evaluate(sidePose(), .side)
        for check in [ReadyCheck.stanceWidth, .toeDirection, .weightBalance] {
            XCTAssertEqual(result.notJudged[check], .cameraAngle,
                           "\(check) 는 측면에서 각도 사유로 빠져야 한다")
        }
        XCTAssertNil(result.stanceWidthByShoulder)
        XCTAssertTrue(result.judged.contains(.kneeStraight))
        XCTAssertTrue(result.judged.contains(.facing))
    }

    func test_정면을_골랐는데_옆으로_서_있으면_돌아서라고_한다() {
        let result = evaluate(sidePose(), .front)
        XCTAssertEqual(result.topIssue, .turnToFront)
        XCTAssertEqual(result.notJudged[.stanceWidth], .cameraAngle)
    }

    func test_측면을_골랐는데_정면으로_서_있으면_몸을_돌리라고_한다() {
        XCTAssertEqual(evaluate(frontPose(), .side).topIssue, .turnToSide)
    }

    func test_방향이_어긋나면_발_간격을_지적하지_않는다() {
        XCTAssertFalse(evaluate(frontPose(), .side).issues.contains { $0.check == .stanceWidth })
    }

    // ── 무릎 ────────────────────────────────────────────────

    func test_무릎을_덜_펴면_지적한다() throws {
        let result = evaluate(frontPose(ankleHalfWidth: 0.18, kneeOffset: 0.12))
        XCTAssertGreaterThan(try XCTUnwrap(result.standingKneeFlexion),
                             ReadyThresholds().maxStandingKneeFlexion)
        XCTAssertTrue(result.issues.contains(.kneesBent))
    }

    func test_무릎_상한은_캘리브레이션과_같은_값이다() {
        XCTAssertEqual(ReadyThresholds().maxStandingKneeFlexion,
                       StandingCalibration.maxStandingFlexion)
    }

    // ── 종합 ────────────────────────────────────────────────

    func test_문제가_없으면_통과지만_못_본_항목은_남는다() {
        let result = evaluate(frontPose(ankleHalfWidth: 0.18))
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertTrue(result.clean)
        XCTAssertTrue(result.notJudged.isEmpty)
    }

    func test_하나도_판정하지_못하면_통과가_아니다() {
        let result = evaluate(frontPose(toeConfidence: 0.1, confidence: 0.1))
        XCTAssertFalse(result.clean)
        XCTAssertEqual(result.notJudged.count, ReadyCheck.allCases.count)
    }

    /// 실시간 갱신이라 **한두 프레임이 무너져도 중앙값이 버틴다.**
    func test_일부_프레임이_무너져도_중앙값이_버틴다() throws {
        let good = frontPose(ankleHalfWidth: 0.18)
        let collapsed = frontPose(ankleHalfWidth: 0.001)
        let mixed: [(pose: Pose, aspectRatio: Float)] = [
            (good, aspect), (collapsed, aspect), (good, aspect),
            (good, aspect), (collapsed, aspect),
        ]
        let result = ReadyPosture.from(frames: mixed, cameraAngle: .front)
        XCTAssertEqual(try XCTUnwrap(result.stanceWidthByShoulder), 1.0, accuracy: 0.005)
        XCTAssertFalse(result.issues.contains { $0.check == .stanceWidth })
    }

    // ── 측정 시작 게이트 ────────────────────────────────────

    func test_비스듬히_서_있으면_측정을_시작하지_않는다() {
        let result = ReadyPosture.from(frames: frames(sidePose()), cameraAngle: .front)
        XCTAssertFalse(result.readyToMeasure)
        XCTAssertTrue(result.blockingIssues.contains(.turnToFront))
    }

    func test_무릎을_덜_펴면_측정을_시작하지_않는다() {
        XCTAssertFalse(evaluate(frontPose(ankleHalfWidth: 0.18, kneeOffset: 0.12)).readyToMeasure)
    }

    func test_발_간격이_어긋나면_측정을_시작하지_않는다() {
        let narrow = evaluate(frontPose(ankleHalfWidth: 0.10))
        XCTAssertTrue(narrow.blockingIssues.contains(.stanceTooNarrow))
        XCTAssertFalse(narrow.readyToMeasure)

        let wide = evaluate(frontPose(ankleHalfWidth: 0.30))
        XCTAssertTrue(wide.blockingIssues.contains(.stanceTooWide))
        XCTAssertFalse(wide.readyToMeasure)
    }

    /// 🔴 **못 본 항목은 통과로 본다** — 안 그러면 측면 촬영으로는 영원히 시작할 수 없다.
    func test_측면에서는_발_간격이_시작을_막지_않는다() {
        let result = evaluate(sidePose(), .side)
        XCTAssertEqual(result.notJudged[.stanceWidth], .cameraAngle)
        XCTAssertTrue(result.readyToMeasure)
    }

    func test_발끝이_안쪽을_향하면_측정을_시작하지_않는다() {
        let result = evaluate(frontPose(ankleHalfWidth: 0.18, toeOutward: -0.06))
        XCTAssertFalse(result.readyToMeasure)
        XCTAssertTrue(result.blockingIssues.contains(.toesInward))
    }

    func test_좌우로_쏠리면_측정을_시작하지_않는다() {
        let result = evaluate(frontPose(ankleHalfWidth: 0.18, hipCenterX: 0.56))
        XCTAssertFalse(result.readyToMeasure)
        XCTAssertTrue(result.blockingIssues.contains(.weightOnOneSide))
    }

    func test_자세가_맞으면_측정을_시작한다() {
        XCTAssertTrue(evaluate(frontPose(ankleHalfWidth: 0.18)).readyToMeasure)
    }

    func test_측면에서_못_보는_항목은_통과로_본다() {
        let result = evaluate(sidePose(), .side)
        XCTAssertFalse(result.notJudged.isEmpty)
        XCTAssertTrue(result.readyToMeasure)
    }

    func test_아무것도_못_봤으면_시작하지_않는다() {
        XCTAssertFalse(evaluate(frontPose(toeConfidence: 0.1, confidence: 0.1)).readyToMeasure)
    }

    func test_프레임이_없으면_시작하지_않는다() {
        XCTAssertFalse(ReadyPosture.empty.readyToMeasure)
    }

    func test_방향이_어긋나면_그것이_첫_안내다() throws {
        let result = ReadyPosture.from(frames: frames(sidePose()), cameraAngle: .front)
        let first = try XCTUnwrap(result.issues.first)
        XCTAssertEqual(first, .turnToFront)
        XCTAssertEqual(first.check, .facing)
    }
}
