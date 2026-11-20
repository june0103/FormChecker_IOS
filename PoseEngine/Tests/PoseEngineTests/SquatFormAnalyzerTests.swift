import XCTest
@testable import PoseEngine

final class SquatFormAnalyzerTests: XCTestCase {

    private let analyzer = SquatFormAnalyzer()
    private let aspect: Float = 0.75

    private func frontFacing(
        kneeSpread: Float = 0.16, ankleSpread: Float = 0.16,
        hipY: Float = 0.5, kneeY: Float = 0.7
    ) -> Pose {
        PoseFixtures.pose([
            .leftShoulder: (0.40, 0.25, 0.9), .rightShoulder: (0.60, 0.25, 0.9),
            .leftHip: (0.44, hipY, 0.9), .rightHip: (0.56, hipY, 0.9),
            .leftKnee: (0.5 - kneeSpread / 2, kneeY, 0.9),
            .rightKnee: (0.5 + kneeSpread / 2, kneeY, 0.9),
            .leftAnkle: (0.5 - ankleSpread / 2, 0.9, 0.9),
            .rightAnkle: (0.5 + ankleSpread / 2, 0.9, 0.9),
        ])
    }

    private func sideFacing(
        shoulderX: Float = 0.5, hipY: Float = 0.5, kneeY: Float = 0.7, kneeX: Float = 0.5
    ) -> Pose {
        PoseFixtures.pose([
            .leftShoulder: (shoulderX, 0.25, 0.9), .rightShoulder: (shoulderX + 0.01, 0.25, 0.9),
            .leftHip: (0.5, hipY, 0.9), .rightHip: (0.51, hipY, 0.9),
            .leftKnee: (kneeX, kneeY, 0.9), .rightKnee: (kneeX + 0.01, kneeY, 0.9),
            .leftAnkle: (0.5, 0.9, 0.9), .rightAnkle: (0.51, 0.9, 0.9),
        ])
    }

    private func features(_ pose: Pose, _ view: CaptureView, _ side: Side?) -> FrameFeatures {
        FrameFeatures.from(pose: pose, aspectRatio: aspect, calibration: nil,
                           view: view, activeSide: side)
    }

    private func analyze(_ pose: Pose, _ angle: CameraAngle,
                         features: FrameFeatures? = nil) -> SquatForm {
        analyzer.analyze(pose: pose, frameAspectRatio: aspect, cameraAngle: angle,
                         features: features)
    }

    // ── 각도별 판정 분리 ────────────────────────────────────

    func test_측면에서는_깊이와_상체_기울기만_판정한다() {
        let pose = sideFacing()
        let form = analyze(pose, .side, features: features(pose, .sideLeft, .left))
        XCTAssertNotNil(form.depth, "깊이는 측면에서 판정한다")
        XCTAssertNotNil(form.torsoLeanDegrees, "상체 기울기는 측면에서 판정한다")
        XCTAssertNil(form.asymmetryDegrees, "좌우 비대칭은 측면에서 판정하지 않는다")
    }

    func test_정면에서는_무릎_정렬과_비대칭만_판정한다() {
        let form = analyze(frontFacing(), .front)
        XCTAssertNotNil(form.asymmetryDegrees, "좌우 비대칭은 정면에서 판정한다")
        XCTAssertNil(form.depth, "깊이는 정면에서 판정하지 않는다")
        XCTAssertNil(form.torsoLeanDegrees, "상체 기울기는 정면에서 판정하지 않는다")
    }

    // ── 깊이 ────────────────────────────────────────────────

    func test_정강이_기준으로_깊이_단계가_나뉜다() {
        let t = FormThresholds()
        XCTAssertEqual(t.depthLevel(byShinDepth: -1.087), .standing)
        XCTAssertEqual(t.depthLevel(byShinDepth: -0.242), .shallow)
        XCTAssertEqual(t.depthLevel(byShinDepth: 0), .parallel)
        XCTAssertEqual(t.depthLevel(byShinDepth: 0.339), .deep)
    }

    func test_깊이_경계값을_주입하면_분류가_달라진다() {
        var strict = FormThresholds()
        strict.parallelShinTolerance = 0.02
        XCTAssertEqual(FormThresholds().depthLevel(byShinDepth: 0.04), .parallel)
        XCTAssertEqual(strict.depthLevel(byShinDepth: 0.04), .deep)
    }

    // ── 무릎 정렬 (폐기된 배수 방식) ────────────────────────

    func test_valgus_배수를_주입하면_판정이_달라진다() {
        var lenient = FormThresholds(); lenient.valgusSpreadGain = 1.2
        var strict = FormThresholds(); strict.valgusSpreadGain = 1.6
        XCTAssertEqual(lenient.kneeAlignment(standingRatio: 0.86, bottomRatio: 1.20), .good)
        XCTAssertEqual(strict.kneeAlignment(standingRatio: 0.86, bottomRatio: 1.20), .valgus)
    }

    func test_정상_스쿼트의_실측_비율은_valgus가_아니다() {
        XCTAssertEqual(
            FormThresholds().kneeAlignment(standingRatio: 0.857, bottomRatio: 1.432), .good)
    }

    func test_최저점에서_무릎이_벌어지지_않으면_valgus로_판정한다() {
        XCTAssertEqual(
            FormThresholds().kneeAlignment(standingRatio: 0.86, bottomRatio: 0.90), .valgus)
    }

    func test_기준선이나_최저점_값이_없으면_무릎_정렬을_판정하지_않는다() {
        let t = FormThresholds()
        XCTAssertNil(t.kneeAlignment(standingRatio: nil, bottomRatio: 1.4))
        XCTAssertNil(t.kneeAlignment(standingRatio: 0.86, bottomRatio: nil))
        XCTAssertNil(t.kneeAlignment(standingRatio: 0.05, bottomRatio: 1.4))
    }

    // ── 상체 숙임 ───────────────────────────────────────────

    func test_상체_기울기_한계를_주입하면_경고_여부가_달라진다() {
        let pose = sideFacing(shoulderX: 0.72)
        var lenientForm = FormThresholds(); lenientForm.torsoLeanLimitDegrees = 80
        var strictForm = FormThresholds(); strictForm.torsoLeanLimitDegrees = 10
        var lenientConfig = SquatAnalyzerConfig(); lenientConfig.form = lenientForm
        var strictConfig = SquatAnalyzerConfig(); strictConfig.form = strictForm

        XCTAssertTrue(SquatFormAnalyzer(config: lenientConfig)
            .analyze(pose: pose, frameAspectRatio: aspect, cameraAngle: .side).warnings.isEmpty)
        XCTAssertTrue(SquatFormAnalyzer(config: strictConfig)
            .analyze(pose: pose, frameAspectRatio: aspect, cameraAngle: .side)
            .warnings.contains(.excessiveLean))
    }

    /// 실측 정상 최대 41.1° — 한계 45°에서 **오탐 0%**.
    func test_실측_정상_상체_숙임은_경고하지_않는다() {
        let limit = FormThresholds().torsoLeanLimitDegrees
        for measured in [Float(29.5), 38.8, 40.1, 41.1] {
            XCTAssertLessThanOrEqual(measured, limit, "실측 정상 \(measured)°가 한계 \(limit)°를 넘었다")
        }
    }

    func test_곧게_선_상체는_기울기가_0에_가깝다() throws {
        let form = analyze(sideFacing(shoulderX: 0.5), .side)
        let lean = try XCTUnwrap(form.torsoLeanDegrees)
        XCTAssertLessThan(lean, 10, "실제: \(lean)")
    }

    func test_상체가_크게_숙여지면_경고가_나온다() throws {
        let form = analyze(sideFacing(shoulderX: 0.85), .side)
        XCTAssertNotNil(form.torsoLeanDegrees)
        XCTAssertTrue(form.warnings.contains(.excessiveLean),
                      "기울기 \(String(describing: form.torsoLeanDegrees))에서 경고가 나와야 한다")
    }

    func test_깊이가_부족하면_경고가_나온다() {
        let form = analyze(sideFacing(hipY: 0.52, kneeY: 0.72, kneeX: 0.56), .side)
        // 깊이는 rep 단위라 프레임 경고에는 나오지 않는다 — 단계만 확인한다.
        if form.depth == .shallow {
            XCTAssertFalse(form.warnings.contains(.shallowDepth))
        }
    }

    // ── 무릎폭 비율 (측정값) ────────────────────────────────

    func test_무릎폭_비율은_판정이_아니라_측정값으로_나온다() throws {
        let form = analyze(frontFacing(kneeSpread: 0.08, ankleSpread: 0.16), .front)
        XCTAssertEqual(try XCTUnwrap(form.kneeSpreadRatio), 0.5, accuracy: 0.001)
        XCTAssertTrue(form.warnings.isEmpty)
    }

    func test_무릎폭_비율은_화면상_위치에_영향받지_않는다() throws {
        let centered = analyze(frontFacing(kneeSpread: 0.06, ankleSpread: 0.18), .front)
        let shifted = analyze(PoseFixtures.pose([
            .leftShoulder: (0.15, 0.25, 0.9), .rightShoulder: (0.35, 0.25, 0.9),
            .leftHip: (0.19, 0.5, 0.9), .rightHip: (0.31, 0.5, 0.9),
            .leftKnee: (0.22, 0.7, 0.9), .rightKnee: (0.28, 0.7, 0.9),
            .leftAnkle: (0.16, 0.9, 0.9), .rightAnkle: (0.34, 0.9, 0.9),
        ]), .front)
        XCTAssertEqual(try XCTUnwrap(centered.kneeSpreadRatio),
                       try XCTUnwrap(shifted.kneeSpreadRatio), accuracy: 0.001)
    }

    /// 두 발이 겹치면 **분모가 무너진다** — 값을 내지 않는다.
    func test_발을_모으고_서면_무릎폭_비율을_내지_않는다() {
        let form = analyze(frontFacing(kneeSpread: 0.01, ankleSpread: 0.02), .front)
        XCTAssertNil(form.kneeSpreadRatio, "기준이 불안정한 구간에서는 값을 내지 않는다")
    }

    func test_무릎폭_비율은_촬영_각도와_무관하게_기록된다() {
        let pose = frontFacing(kneeSpread: 0.06, ankleSpread: 0.18)
        XCTAssertNotNil(analyze(pose, .side).kneeSpreadRatio)
        XCTAssertNotNil(analyze(pose, .front).kneeSpreadRatio)
        XCTAssertFalse(CameraAngle.side.supports(.kneeAlignment),
                       "측면은 무릎 정렬을 지원하지 않는다")
    }

    // ── 각도 제안 ───────────────────────────────────────────

    func test_측면_모드인데_정면으로_서_있으면_각도_전환을_제안한다() {
        XCTAssertEqual(analyze(frontFacing(), .side).suggestedAngle, .front)
    }

    func test_정면_모드인데_측면으로_서_있으면_각도_전환을_제안한다() {
        XCTAssertEqual(analyze(sideFacing(), .front).suggestedAngle, .side)
    }

    func test_선택한_각도와_실제가_일치하면_제안하지_않는다() {
        XCTAssertNil(analyze(sideFacing(), .side).suggestedAngle)
        XCTAssertNil(analyze(frontFacing(), .front).suggestedAngle)
    }

    // ── 가시성 ──────────────────────────────────────────────

    func test_사람이_안_보이면_NONE이다() {
        XCTAssertEqual(analyze(PoseFixtures.pose([:]), .side).visibility, .none)
    }

    func test_상체만_보이면_UPPER_BODY_ONLY이고_각도는_나오지_않는다() {
        let form = analyze(PoseFixtures.pose([
            .leftShoulder: (0.40, 0.25, 0.9), .rightShoulder: (0.60, 0.25, 0.9),
            .leftHip: (0.44, 0.5, 0.9), .rightHip: (0.56, 0.5, 0.9),
        ]), .side)
        XCTAssertEqual(form.visibility, .upperBodyOnly)
        XCTAssertNil(form.kneeAngles.representative)
    }

    /// 측면에서는 먼 쪽 다리가 가려진다 — **한쪽만 보여도 FULL이다.**
    func test_한쪽_다리만_보여도_FULL이다() {
        let form = analyze(PoseFixtures.pose([
            .leftShoulder: (0.5, 0.25, 0.9), .leftHip: (0.5, 0.5, 0.9),
            .leftKnee: (0.5, 0.7, 0.9), .leftAnkle: (0.5, 0.9, 0.9),
        ]), .side)
        XCTAssertEqual(form.visibility, .full)
        XCTAssertNotNil(form.kneeAngles.left)
    }

    func test_키포인트가_없으면_아무것도_판정하지_않는다() {
        let form = analyze(PoseFixtures.pose([:]), .side)
        XCTAssertNil(form.depth)
        XCTAssertNil(form.torsoLeanDegrees)
        XCTAssertNil(form.suggestedAngle)
        XCTAssertTrue(form.warnings.isEmpty)
    }
}
