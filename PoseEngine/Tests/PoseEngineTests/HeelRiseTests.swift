import XCTest
@testable import PoseEngine

/// 뒤꿈치 들림. ⚠ **이 판정이 아무것도 못 잡을 수 있다** — 진짜 들림의 추정치(0.139)가
/// 현재 임계값(0.18)보다 아래다. 임계값 문제가 아니라 **측정이 둘을 못 가르는** 문제일 수 있다.
final class HeelRiseTests: XCTestCase {

    private let aspect: Float = 0.75
    private let analyzer = SquatFormAnalyzer()

    private func sidePose(
        heelLift: Float = 0, toeX: Float = 0.58, hipY: Float = 0.50,
        confidence: Float = 0.9, footConfidence: Float = 0.9
    ) -> Pose {
        var points: [KeypointType: PoseFixtures.Point] = [
            .leftShoulder: (0.48, hipY - 0.20, confidence),
            .rightShoulder: (0.52, hipY - 0.20, confidence),
            .leftHip: (0.49, hipY, confidence), .rightHip: (0.51, hipY, confidence),
            .leftKnee: (0.50, 0.70, confidence), .rightKnee: (0.50, 0.70, confidence),
            .leftAnkle: (0.50, 0.90, confidence), .rightAnkle: (0.51, 0.90, confidence),
            .neck: (0.50, hipY - 0.18, confidence),
        ]
        points[.rightAnkle] = (0.50, 0.90, confidence)
        for side in Side.allCases {
            points[Geometry.heel(side)] = (0.46, 0.94 - heelLift, footConfidence)
            points[Geometry.bigToe(side)] = (toeX, 0.94, footConfidence)
            points[Geometry.smallToe(side)] = (toeX, 0.94, footConfidence)
        }
        return PoseFixtures.pose(points)
    }

    private func calibration(of pose: Pose) throws -> StandingCalibration {
        try XCTUnwrap(StandingCalibration.from(
            frames: (0..<30).map { _ in (pose: pose, aspectRatio: aspect) }))
    }

    private func features(_ pose: Pose, _ calibration: StandingCalibration?) -> FrameFeatures {
        FrameFeatures.from(pose: pose, aspectRatio: aspect, calibration: calibration,
                           view: .sideLeft, activeSide: .left)
    }

    private func analyze(_ pose: Pose, _ calibration: StandingCalibration?) -> SquatForm {
        analyzer.analyze(pose: pose, frameAspectRatio: aspect, cameraAngle: .side,
                         features: features(pose, calibration))
    }

    // ── 측정 ────────────────────────────────────────────────

    func test_기립_자세에서는_0이다() throws {
        let standing = sidePose()
        let f = features(standing, try calibration(of: standing))
        XCTAssertEqual(try XCTUnwrap(f.leftHeelRise), 0, accuracy: 1e-4)
    }

    func test_뒤꿈치를_들면_정강이_길이로_정규화된_값이_나온다() throws {
        let calib = try calibration(of: sidePose())
        let f = features(sidePose(heelLift: 0.02), calib)
        XCTAssertEqual(try XCTUnwrap(f.leftHeelRise), 0.10, accuracy: 1e-3)
    }

    /// **기립 기준 대비 변화량**이라 화면상 위치에 영향받지 않는다.
    func test_몸이_화면에서_위아래로_움직여도_값이_바뀌지_않는다() throws {
        let calib = try calibration(of: sidePose())
        let flat = try XCTUnwrap(features(sidePose(), calib).leftHeelRise)
        let moved = sidePose().mapKeypoints { $0.confidence > 0 ? $0.with(y: $0.y - 0.03) : $0 }
        XCTAssertEqual(try XCTUnwrap(features(moved, calib).leftHeelRise), flat, accuracy: 1e-4)
    }

    /// 정강이로 정규화하므로 **발이 짧게 보여도** 같은 들림은 같은 값이다.
    func test_발이_짧게_보여도_같은_들림은_같은_값을_낸다() throws {
        let longFoot = try calibration(of: sidePose(toeX: 0.58))
        let shortFoot = try calibration(of: sidePose(toeX: 0.53))
        let a = try XCTUnwrap(features(sidePose(heelLift: 0.02, toeX: 0.58), longFoot).leftHeelRise)
        let b = try XCTUnwrap(features(sidePose(heelLift: 0.02, toeX: 0.53), shortFoot).leftHeelRise)
        XCTAssertEqual(a, b, accuracy: 1e-4)
    }

    func test_기준선이_없으면_계산하지_않는다() {
        XCTAssertNil(features(sidePose(heelLift: 0.02), nil).leftHeelRise)
    }

    /// 🔴 **발이 안 보이면 기준선에 0을 채우지 않는다** — 0을 채우면 "안 들렸다"가 된다.
    func test_발이_안_보이면_기준선에_0을_채우지_않는다() throws {
        let calib = try calibration(of: sidePose(footConfidence: 0.1))
        XCTAssertNil(calib.standingLeftHeelLift)
        XCTAssertNil(features(sidePose(heelLift: 0.02), calib).leftHeelRise)
    }

    func test_정면에서는_계산하지_않는다() throws {
        let calib = try calibration(of: sidePose())
        let f = FrameFeatures.from(pose: sidePose(heelLift: 0.02), aspectRatio: aspect,
                                   calibration: calib, view: .front, activeSide: nil)
        XCTAssertNil(f.leftHeelRise)
        XCTAssertNil(f.rightHeelRise)
    }

    // ── 판정 ────────────────────────────────────────────────

    func test_허용폭을_넘으면_경고한다() throws {
        let calib = try calibration(of: sidePose())
        XCTAssertTrue(analyze(sidePose(heelLift: 0.04), calib).warnings.contains(.heelRise))
    }

    /// **기기에서 발바닥이 붙어 있는데 0.15까지 올라갔다** — 그래서 0.11 → 0.18로 올렸다.
    func test_발이_붙어_있을_때_관찰된_상한은_경고하지_않는다() throws {
        let calib = try calibration(of: sidePose())
        XCTAssertFalse(analyze(sidePose(heelLift: 0.03), calib).warnings.contains(.heelRise),
                       "발이 붙어 있는데 0.15에서 경고하면 안 된다")
    }

    func test_허용폭_안이면_경고하지_않는다() throws {
        let calib = try calibration(of: sidePose())
        XCTAssertFalse(analyze(sidePose(heelLift: 0.0178), calib).warnings.contains(.heelRise))
    }

    func test_발이_짧게_보이면_판정하지_않는다() throws {
        let shortFoot = sidePose(toeX: 0.50)
        let calib = try calibration(of: shortFoot)
        XCTAssertLessThan(calib.footTibiaRatio, FormThresholds().minHeelFootRatio,
                          "게이트가 닫힐 만큼 짧아야 한다")
        let form = analyze(sidePose(heelLift: 0.05, toeX: 0.50), calib)
        XCTAssertNil(form.heelRise)
        XCTAssertFalse(form.warnings.contains(.heelRise))
    }

    func test_발이_충분히_보이면_게이트가_열린다() throws {
        let calib = try calibration(of: sidePose())
        XCTAssertGreaterThanOrEqual(calib.footTibiaRatio, FormThresholds().minHeelFootRatio)
        XCTAssertNotNil(analyze(sidePose(heelLift: 0.03), calib).heelRise)
    }

    func test_정면에서는_항목_자체가_꺼진다() {
        XCTAssertFalse(CameraAngle.front.supports(.heelLift))
        XCTAssertTrue(CameraAngle.side.supports(.heelLift))
        XCTAssertFalse(RepScorer.checksFor(.front).contains(.heelRise))
        XCTAssertTrue(RepScorer.checksFor(.side).contains(.heelRise))
    }

    // ── 깊이와의 관계 ───────────────────────────────────────

    func test_깊이는_프레임_경고로_나가지_않는다() throws {
        let calib = try calibration(of: sidePose())
        let form = analyze(sidePose(hipY: 0.60), calib)
        XCTAssertEqual(form.depth, .shallow)
        XCTAssertFalse(form.warnings.contains(.shallowDepth), "깊이는 rep 최저점으로만 판정한다")
    }

    /// 🔴 **둘이 함께 뜨면 서로 반대인 지시가 된다.**
    func test_뒤꿈치가_뜨면_깊이_부족을_말하지_않는다() {
        let rep = RepWarnings.of(frameWarnings: [.heelRise], depth: .shallow, kneePastToe: nil)
        XCTAssertTrue(rep.contains(.heelRise))
        XCTAssertFalse(rep.contains(.shallowDepth), "뒤꿈치가 떴는데 더 깊게 앉으라고 하면 안 된다")
    }

    func test_뒤꿈치가_붙어_있으면_깊이_부족은_그대로_말한다() {
        let rep = RepWarnings.of(frameWarnings: [], depth: .shallow, kneePastToe: nil)
        XCTAssertTrue(rep.contains(.shallowDepth))
        XCTAssertFalse(rep.contains(.heelRise))
    }

    /// 배제 규칙은 **"뒤꿈치가 떴다"는 사실에만** 걸린다 — 못 본 것은 배제 사유가 아니다.
    func test_뒤꿈치를_판정하지_못하면_깊이_경고는_살아_있다() throws {
        let calib = try calibration(of: sidePose(toeX: 0.50))
        let form = analyze(sidePose(heelLift: 0.05, toeX: 0.50, hipY: 0.60), calib)
        XCTAssertNil(form.heelRise, "게이트가 닫혀 뒤꿈치를 못 잰다")
        XCTAssertFalse(form.warnings.contains(.heelRise))
        let rep = RepWarnings.of(frameWarnings: Set(form.warnings), depth: form.depth,
                                 kneePastToe: nil)
        XCTAssertTrue(rep.contains(.shallowDepth))
    }

    func test_활성측이_없으면_판정하지_않는다() throws {
        let calib = try calibration(of: sidePose())
        let f = FrameFeatures.from(pose: sidePose(heelLift: 0.05), aspectRatio: aspect,
                                   calibration: calib, view: .sideLeft, activeSide: nil)
        XCTAssertNil(f.heelRise)
        XCTAssertNotNil(f.leftHeelRise)
        let form = analyzer.analyze(pose: sidePose(heelLift: 0.05), frameAspectRatio: aspect,
                                    cameraAngle: .side, features: f)
        XCTAssertNil(form.heelRise)
        XCTAssertFalse(form.warnings.contains(.heelRise))
    }

    func test_뒤꿈치_경고가_깊이_부족보다_먼저_온다() {
        XCTAssertLessThan(FormWarning.heelRise.order, FormWarning.shallowDepth.order)
    }
}
