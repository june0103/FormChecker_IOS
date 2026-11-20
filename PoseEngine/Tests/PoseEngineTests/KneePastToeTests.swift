import XCTest
@testable import PoseEngine

/// 무릎이 발끝을 넘었는가. **rep 단위 판정**이고 허용폭이 0이다.
final class KneePastToeTests: XCTestCase {

    private let aspect: Float = 0.75
    private let thresholds = FormThresholds()

    private func sidePose(
        kneeAhead: Float = 0, toeX: Float = 0.58, hipY: Float = 0.60,
        mirrored: Bool = false, footConfidence: Float = 0.9
    ) -> Pose {
        func flip(_ x: Float) -> Float { mirrored ? 1 - x : x }
        var points: [KeypointType: PoseFixtures.Point] = [
            .leftShoulder: (flip(0.48), hipY - 0.20, 0.9),
            .rightShoulder: (flip(0.52), hipY - 0.20, 0.9),
            .leftHip: (flip(0.49), hipY, 0.9),
            .rightHip: (flip(0.51), hipY, 0.9),
            .leftKnee: (flip(0.50 + kneeAhead), 0.70, 0.9),
            .rightKnee: (flip(0.50 + kneeAhead), 0.70, 0.9),
            .leftAnkle: (flip(0.50), 0.90, 0.9),
            .rightAnkle: (flip(0.50), 0.90, 0.9),
            .neck: (flip(0.50), hipY - 0.18, 0.9),
        ]
        for side in Side.allCases {
            points[Geometry.heel(side)] = (flip(0.46), 0.94, footConfidence)
            points[Geometry.bigToe(side)] = (flip(toeX), 0.94, footConfidence)
            points[Geometry.smallToe(side)] = (flip(toeX), 0.94, footConfidence)
        }
        return PoseFixtures.pose(points)
    }

    private func calibration(toeX: Float = 0.58) -> StandingCalibration? {
        StandingCalibration.from(frames: (0..<30).map { _ in
            (pose: sidePose(toeX: toeX, hipY: 0.50), aspectRatio: aspect)
        })
    }

    private func features(
        _ pose: Pose, view: CaptureView = .sideLeft, calibrationToeX: Float = 0.58
    ) -> FrameFeatures {
        FrameFeatures.from(pose: pose, aspectRatio: aspect,
                           calibration: calibration(toeX: calibrationToeX),
                           view: view, activeSide: .left)
    }

    private func analyze(_ pose: Pose, calibrationToeX: Float = 0.58) -> SquatForm {
        var config = SquatAnalyzerConfig()
        config.form = thresholds
        return SquatFormAnalyzer(config: config).analyze(
            pose: pose, frameAspectRatio: aspect, cameraAngle: .side,
            features: features(pose, calibrationToeX: calibrationToeX)
        )
    }

    // ── 측정 ────────────────────────────────────────────────

    func test_무릎이_발목_위면_음수다() throws {
        let v = try XCTUnwrap(features(sidePose()).kneeOverToe)
        XCTAssertLessThan(v, 0, "발끝보다 뒤여야 한다: \(v)")
    }

    func test_무릎이_발끝_바로_위면_0이다() throws {
        XCTAssertEqual(try XCTUnwrap(features(sidePose(kneeAhead: 0.08)).kneeOverToe),
                       0, accuracy: 1e-3)
    }

    func test_발_길이만큼_넘으면_1이다() throws {
        XCTAssertEqual(try XCTUnwrap(features(sidePose(kneeAhead: 0.08 + 0.12)).kneeOverToe),
                       1, accuracy: 1e-2)
    }

    /// 앞쪽은 `sign(발끝.x − 뒤꿈치.x)`로 **발이 스스로 가리킨다** — 촬영 좌/우를 몰라도 된다.
    func test_좌우를_뒤집어도_같은_값이다() throws {
        let normal = try XCTUnwrap(features(sidePose(kneeAhead: 0.14)).kneeOverToe)
        let flipped = try XCTUnwrap(
            features(sidePose(kneeAhead: 0.14, mirrored: true), view: .sideRight).kneeOverToe)
        XCTAssertEqual(normal, flipped, accuracy: 1e-3)
    }

    func test_정면에서는_재지_않는다() {
        let f = FrameFeatures.from(pose: sidePose(kneeAhead: 0.20), aspectRatio: aspect,
                                   calibration: nil, view: .front, activeSide: nil)
        XCTAssertNil(f.kneeOverToe, "정면에서는 앞뒤가 깊이축이라 잴 수 없다")
    }

    // ── 게이트 ──────────────────────────────────────────────

    func test_게이트를_통과하면_값이_실린다() {
        XCTAssertNotNil(analyze(sidePose(kneeAhead: 0.14)).kneeOverToe, "게이트를 통과해야 한다")
    }

    /// 🔴 **rep 단위 항목이라 프레임 경고로 나가면 안 된다.**
    func test_프레임_경고로는_나가지_않는다() {
        XCTAssertFalse(analyze(sidePose(kneeAhead: 0.30)).warnings.contains(.kneePastToe))
    }

    /// 실측에서 발끝을 넘은 rep이 **전부** 이 게이트에 걸리는 세션에서 나왔다.
    func test_발이_짧게_보이는_세션은_판정하지_않는다() {
        let pose = sidePose(kneeAhead: 0.14, toeX: 0.52)
        XCTAssertNotNil(analyze(pose).kneeOverToe, "발이 잘 보이는 세션이면 값이 나온다")
        XCTAssertNil(analyze(pose, calibrationToeX: 0.52).kneeOverToe,
                     "발이 짧게 보이는 세션은 값 자체를 내지 않는다")
    }

    func test_서_있을_때는_판정하지_않는다() {
        XCTAssertNil(analyze(sidePose(kneeAhead: 0.20, hipY: 0.30)).kneeOverToe)
    }

    // ── rep 중앙값 ──────────────────────────────────────────

    func test_중앙값이_0을_넘으면_경고다() {
        XCTAssertEqual(thresholds.kneePastToe(of: [0.02, 0.05, 0.10]), true)
    }

    func test_정상_rep_모양은_통과한다() {
        XCTAssertEqual(thresholds.kneePastToe(of: [-0.14, -0.11, -0.05]), false)
    }

    /// 프레임 단위로 0을 대면 정상 rep의 **46%**가 걸린다. 중앙값이면 **0%**다.
    func test_몇_프레임이_튀어도_중앙값은_넘어가지_않는다() {
        let values = Array(repeating: Float(-0.10), count: 13) + [0.05, 0.07]
        XCTAssertEqual(thresholds.kneePastToe(of: values), false)
    }

    func test_절반_이상이_넘으면_경고한다() {
        let values = Array(repeating: Float(0.03), count: 8)
            + Array(repeating: Float(-0.10), count: 7)
        XCTAssertEqual(thresholds.kneePastToe(of: values), true)
    }

    /// **"안 넘었다"와 "못 봤다"는 다르다.**
    func test_값이_없으면_nil이다() {
        XCTAssertNil(thresholds.kneePastToe(of: []))
    }

    func test_분석기는_rep_단위_항목을_내보내지_않는다() {
        XCTAssertEqual(Set(FormWarning.allCases.filter(\.isRepLevel)),
                       [.shallowDepth, .kneePastToe],
                       "rep 단위 항목이 바뀌면 이 테스트도 함께 봐야 한다")
        let warnings = analyze(sidePose(kneeAhead: 0.30, hipY: 0.60)).warnings
        XCTAssertFalse(warnings.contains(where: \.isRepLevel),
                       "프레임 경고에 rep 단위 항목이 섞였다: \(warnings)")
    }

    func test_rep_조립이_두_항목을_넣는다() {
        let rep = RepWarnings.of(frameWarnings: [], depth: .shallow, kneePastToe: true)
        XCTAssertEqual(rep, [.shallowDepth, .kneePastToe])
    }

    func test_측면_판정_목록에_뒤꿈치와_함께_있다() {
        let checks = RepScorer.checksFor(.side)
        XCTAssertTrue(checks.contains(.kneePastToe))
        XCTAssertTrue(checks.contains(.heelRise))
    }
}
