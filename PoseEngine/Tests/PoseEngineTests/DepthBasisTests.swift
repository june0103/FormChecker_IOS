import XCTest
@testable import PoseEngine

/// 깊이 판정과 정면 판정(골반 쏠림·무릎 정렬). 가장 많은 실측 근거가 걸린 테스트다.
final class DepthBasisTests: XCTestCase {

    private let thresholds = FormThresholds()
    private let analyzer = SquatFormAnalyzer()
    private let aspect: Float = 0.75

    private static let squatHipY: Float = 0.72
    private static let standingHipY: Float = 0.50

    /// 기준 완화 — **얕은 쪽 경계만** 넓힌다.
    private var relaxed: FormThresholds {
        var t = FormThresholds()
        t.shallowToleranceRatio = FormThresholds.relaxedShallowTolerance
        t.shallowShinTolerance = FormThresholds.relaxedShallowShinTolerance
        return t
    }

    // ── 깊이 단계 ───────────────────────────────────────────

    func test_선_자세_깊이비를_서_있음으로_본다() {
        XCTAssertEqual(thresholds.depthLevel(byRatio: -0.52), .standing)
        XCTAssertEqual(thresholds.depthLevel(byRatio: -0.45), .standing)
    }

    /// **"패럴렐"의 정의가 대퇴 수평, 즉 엉덩이가 무릎 높이다.**
    func test_엉덩이가_무릎_높이면_패럴렐이다() {
        XCTAssertEqual(thresholds.depthLevel(byRatio: 0), .parallel)
    }

    func test_측정_오차만큼_부족한_것은_패럴렐로_본다() {
        XCTAssertEqual(thresholds.depthLevel(byRatio: -0.026), .parallel)
        XCTAssertEqual(thresholds.depthLevel(byRatio: -0.10), .shallow, "허용폭을 넘으면 부족으로 본다")
    }

    func test_패럴렐보다_확실히_내려가면_충분으로_본다() {
        XCTAssertEqual(thresholds.depthLevel(byRatio: 0.060), .deep)
    }

    // ── 기준 완화 ───────────────────────────────────────────

    func test_완화하면_얕은_쪽_경계가_넓어진다() {
        XCTAssertEqual(thresholds.depthLevel(byRatio: -0.10), .shallow)
        XCTAssertEqual(relaxed.depthLevel(byRatio: -0.10), .parallel)
    }

    func test_완화해도_경계를_넘으면_부족이다() {
        XCTAssertEqual(relaxed.depthLevel(byRatio: -0.11), .shallow)
        XCTAssertEqual(relaxed.depthLevel(byRatio: -0.25), .shallow)
    }

    /// 🔴 **"깊음"이 "적당"으로 내려앉으면 안 된다.**
    func test_완화해도_깊음_경계는_그대로다() {
        XCTAssertEqual(thresholds.depthLevel(byRatio: 0.060), .deep)
        XCTAssertEqual(relaxed.depthLevel(byRatio: 0.060), .deep)
        XCTAssertEqual(relaxed.depthLevel(byRatio: 0.031), .deep,
                       "측정 오차 폭(0.03) 바로 위는 양쪽 다 깊음이어야 한다")
    }

    func test_완화해도_선_자세_경계는_그대로다() {
        XCTAssertEqual(relaxed.depthLevel(byRatio: -0.45), .standing)
    }

    func test_정강이_경로도_함께_넓어진다() {
        XCTAssertEqual(thresholds.depthLevel(byShinDepth: -0.20), .shallow)
        XCTAssertEqual(relaxed.depthLevel(byShinDepth: -0.20), .parallel)
        XCTAssertEqual(relaxed.depthLevel(byShinDepth: -0.21), .shallow)
    }

    func test_기본값은_예전과_같다() {
        XCTAssertEqual(thresholds.parallelToleranceRatio, thresholds.shallowToleranceRatio,
                       accuracy: 1e-6)
        XCTAssertEqual(thresholds.parallelShinTolerance, thresholds.shallowShinTolerance,
                       accuracy: 1e-6)
    }

    /// 실측 측면 3명의 최저점 중앙값이 −0.043 / +0.046 / +0.149다.
    func test_완화하면_실측_세_사람이_전부_통과한다() {
        for median in [Float(-0.043), 0.046, 0.149] {
            XCTAssertNotEqual(relaxed.depthLevel(byRatio: median), .shallow,
                              "완화에서는 \(median) 이 부족이면 안 된다")
        }
        XCTAssertEqual(thresholds.depthLevel(byRatio: -0.043), .shallow)
    }

    func test_경계가_단조롭게_놓여_있다() {
        let ordered: [Float] = [-0.60, -0.40, -0.03, 0, 0.05, 0.20]
        XCTAssertEqual(ordered.map { thresholds.depthLevel(byRatio: $0) },
                       [.standing, .standing, .parallel, .parallel, .deep, .deep])
    }

    /// 두 기준은 서로 환산되지 않지만 **같은 깊이는 같은 단계로 읽혀야** 한다.
    func test_두_정규화가_같은_깊이를_같은_단계로_읽는다() {
        let pairs: [(Float, Float)] = [
            (-0.52, -1.079),  // 선 자세
            (-0.10, -0.208),  // 패럴렐에 못 미침
            (0, 0),           // 대퇴 수평
            (0.08, 0.166),    // 확실히 아래
        ]
        for (ratio, shin) in pairs {
            XCTAssertEqual(thresholds.depthLevel(byRatio: ratio),
                           thresholds.depthLevel(byShinDepth: shin),
                           "깊이비 \(ratio) / 정강이비 \(shin) 이 다른 단계로 읽혔다")
        }
    }

    /// 각도 경로에서는 이 둘이 전부 DEEP으로 읽혔다.
    func test_각도로는_놓쳤던_얕은_rep을_잡는다() {
        XCTAssertEqual(thresholds.depthLevel(byShinDepth: -0.119), .shallow)
        XCTAssertEqual(thresholds.depthLevel(byRatio: -0.043), .shallow)
    }

    // ── 측면 자세 생성 ──────────────────────────────────────

    private func sidePose(flexionDegrees: Float) -> Pose {
        let radians = Double(flexionDegrees) * .pi / 180
        let kneeY: Float = 0.70
        let femur: Float = 0.20
        let hipX = Float(0.50 + Double(femur) * sin(radians))
        let hipY = Float(Double(kneeY) - Double(femur) * cos(radians))

        var points: [KeypointType: PoseFixtures.Point] = [:]
        func sides(_ left: KeypointType, _ right: KeypointType, _ x: Float, _ y: Float) {
            points[left] = (x - 0.03, y, 0.9)
            points[right] = (x + 0.03, y, 0.9)
        }
        sides(.leftHip, .rightHip, hipX, hipY)
        sides(.leftKnee, .rightKnee, 0.50, kneeY)
        sides(.leftAnkle, .rightAnkle, 0.50, 0.90)
        sides(.leftShoulder, .rightShoulder, hipX, hipY - 0.20)
        points[.neck] = (hipX, hipY - 0.22, 0.9)
        sides(.leftHeel, .rightHeel, 0.50, 0.94)
        sides(.leftBigToe, .rightBigToe, 0.58, 0.94)
        sides(.leftSmallToe, .rightSmallToe, 0.58, 0.94)
        return PoseFixtures.pose(points)
    }

    private func calibration() throws -> StandingCalibration {
        try XCTUnwrap(StandingCalibration.from(
            frames: (0..<30).map { _ in (pose: sidePose(flexionDegrees: 0), aspectRatio: aspect) }))
    }

    private func features(at flexion: Float) throws -> FrameFeatures {
        FrameFeatures.from(pose: sidePose(flexionDegrees: flexion), aspectRatio: aspect,
                           calibration: try calibration(), view: .sideLeft, activeSide: .left)
    }

    private func uncalibratedFeatures(at flexion: Float) -> FrameFeatures {
        FrameFeatures.from(pose: sidePose(flexionDegrees: flexion), aspectRatio: aspect,
                           calibration: nil, view: .sideLeft, activeSide: .left)
    }

    // ── 깊이 기준 선택 ──────────────────────────────────────

    func test_기준선이_없으면_정강이_기준을_쓴다() {
        let form = analyzer.analyze(pose: sidePose(flexionDegrees: 90), frameAspectRatio: aspect,
                                    cameraAngle: .side, features: uncalibratedFeatures(at: 90))
        XCTAssertEqual(form.depthBasis, .shinLength)
        XCTAssertNil(form.depthRatio, "기준선이 없으면 깊이비도 없다")
        XCTAssertNotNil(form.depth, "그래도 깊이는 판정한다")
    }

    /// **둘 다 없으면 nil이다** — 각도로 대체하지 않는다.
    func test_특징이_없으면_깊이를_판정하지_않는다() {
        let form = analyzer.analyze(pose: sidePose(flexionDegrees: 90),
                                    frameAspectRatio: aspect, cameraAngle: .side)
        XCTAssertNil(form.depth)
        XCTAssertNil(form.depthBasis)
    }

    func test_기준선이_있으면_높이_기준을_쓴다() throws {
        let form = analyzer.analyze(pose: sidePose(flexionDegrees: 90), frameAspectRatio: aspect,
                                    cameraAngle: .side, features: try features(at: 90))
        XCTAssertEqual(form.depthBasis, .hipHeight)
        XCTAssertNotNil(form.depthRatio, "깊이비를 함께 남긴다")
    }

    func test_대퇴_수평은_두_기준_모두_패럴렐이다() throws {
        let calibrated = analyzer.analyze(pose: sidePose(flexionDegrees: 90),
                                          frameAspectRatio: aspect, cameraAngle: .side,
                                          features: try features(at: 90))
        let uncalibrated = analyzer.analyze(pose: sidePose(flexionDegrees: 90),
                                            frameAspectRatio: aspect, cameraAngle: .side,
                                            features: uncalibratedFeatures(at: 90))
        XCTAssertEqual(calibrated.depthBasis, .hipHeight)
        XCTAssertEqual(uncalibrated.depthBasis, .shinLength)
        XCTAssertEqual(calibrated.depth, .parallel)
        XCTAssertEqual(uncalibrated.depth, .parallel)
    }

    func test_선_자세는_두_기준_모두_서_있음으로_본다() throws {
        let calibrated = analyzer.analyze(pose: sidePose(flexionDegrees: 0),
                                          frameAspectRatio: aspect, cameraAngle: .side,
                                          features: try features(at: 0))
        let uncalibrated = analyzer.analyze(pose: sidePose(flexionDegrees: 0),
                                            frameAspectRatio: aspect, cameraAngle: .side,
                                            features: uncalibratedFeatures(at: 0))
        XCTAssertEqual(calibrated.depth, .standing)
        XCTAssertEqual(uncalibrated.depth, .standing)
    }

    func test_정면에서는_기준선이_있어도_깊이를_판정하지_않는다() throws {
        let form = analyzer.analyze(pose: sidePose(flexionDegrees: 90), frameAspectRatio: aspect,
                                    cameraAngle: .front, features: try features(at: 90))
        XCTAssertNil(form.depth)
        XCTAssertNil(form.depthBasis)
        XCTAssertNil(form.depthRatio)
    }

    func test_기준선이_있으면_상체_숙임도_그쪽_값을_쓴다() throws {
        let f = try features(at: 60)
        let form = analyzer.analyze(pose: sidePose(flexionDegrees: 60), frameAspectRatio: aspect,
                                    cameraAngle: .side, features: f)
        XCTAssertEqual(form.torsoLeanDegrees, f.trunkLean)
    }

    // ── 정면: 골반 쏠림 ────────────────────────────────────

    private func frontPose(hipOffset: Float) -> Pose {
        let ankleSpread: Float = 0.10
        var points: [KeypointType: PoseFixtures.Point] = [:]
        func sides(_ l: KeypointType, _ r: KeypointType, _ x: Float, _ y: Float, _ s: Float) {
            points[l] = (x - s / 2, y, 0.9)
            points[r] = (x + s / 2, y, 0.9)
        }
        sides(.leftAnkle, .rightAnkle, 0.50, 0.90, ankleSpread)
        sides(.leftKnee, .rightKnee, 0.50, 0.70, ankleSpread)
        sides(.leftHip, .rightHip, 0.50 + hipOffset, 0.50, ankleSpread)
        sides(.leftShoulder, .rightShoulder, 0.50 + hipOffset, 0.30, 0.20)
        points[.neck] = (0.50 + hipOffset, 0.28, 0.9)
        sides(.leftHeel, .rightHeel, 0.50, 0.94, ankleSpread)
        sides(.leftBigToe, .rightBigToe, 0.50, 0.98, ankleSpread)
        sides(.leftSmallToe, .rightSmallToe, 0.50, 0.98, ankleSpread)
        return PoseFixtures.pose(points)
    }

    private func frontFeatures(hipOffset: Float) throws -> FrameFeatures {
        let calibration = try XCTUnwrap(StandingCalibration.from(
            frames: (0..<30).map { _ in (pose: frontPose(hipOffset: 0), aspectRatio: aspect) }))
        return FrameFeatures.from(pose: frontPose(hipOffset: hipOffset), aspectRatio: aspect,
                                  calibration: calibration, view: .front, activeSide: nil)
    }

    private func frontForm(hipOffset: Float) throws -> SquatForm {
        analyzer.analyze(pose: frontPose(hipOffset: hipOffset), frameAspectRatio: aspect,
                         cameraAngle: .front, features: try frontFeatures(hipOffset: hipOffset))
    }

    func test_정상_범위_안의_골반_쏠림은_경고하지_않는다() throws {
        let form = try frontForm(hipOffset: 0)
        XCTAssertEqual(try XCTUnwrap(form.hipShiftRatio), 0, accuracy: 0.01)
        XCTAssertFalse(form.warnings.contains(.hipShift))
    }

    func test_한계를_넘는_골반_쏠림은_경고한다() throws {
        let form = try frontForm(hipOffset: 0.02)
        XCTAssertTrue(form.warnings.contains(.hipShift),
                      "쏠림이 한계를 넘어야 한다 (실제: \(String(describing: form.hipShiftRatio)))")
    }

    func test_반대쪽으로_쏠려도_같게_판정한다() throws {
        XCTAssertEqual(try frontForm(hipOffset: 0.02).warnings.contains(.hipShift),
                       try frontForm(hipOffset: -0.02).warnings.contains(.hipShift))
    }

    func test_측면에서는_골반_쏠림을_판정하지_않는다() throws {
        let side = analyzer.analyze(pose: sidePose(flexionDegrees: 90), frameAspectRatio: aspect,
                                    cameraAngle: .side, features: try features(at: 90))
        XCTAssertNil(side.hipShiftRatio)
    }

    // ── 정면: 무릎 정렬 ────────────────────────────────────

    private func kneeShiftedPose(
        kneeOffset: Float, hipY: Float = DepthBasisTests.squatHipY, spread: Float = 0.10,
        leftOffset: Float? = nil, rightOffset: Float? = nil
    ) -> Pose {
        let left = leftOffset ?? kneeOffset
        let right = rightOffset ?? kneeOffset
        var points: [KeypointType: PoseFixtures.Point] = [:]
        func sides(_ l: KeypointType, _ r: KeypointType, _ x: Float, _ y: Float, _ s: Float) {
            points[l] = (x + s / 2, y, 0.9)
            points[r] = (x - s / 2, y, 0.9)
        }
        sides(.leftAnkle, .rightAnkle, 0.50, 0.90, spread)
        points[.leftKnee] = (0.50 + spread / 2 - left, 0.70, 0.9)
        points[.rightKnee] = (0.50 - spread / 2 + right, 0.70, 0.9)
        sides(.leftHip, .rightHip, 0.50, hipY, 0.04)
        sides(.leftShoulder, .rightShoulder, 0.50, hipY - 0.20, 0.20)
        points[.neck] = (0.50, hipY - 0.22, 0.9)
        sides(.leftHeel, .rightHeel, 0.50, 0.94, spread)
        sides(.leftBigToe, .rightBigToe, 0.50, 0.98, spread)
        sides(.leftSmallToe, .rightSmallToe, 0.50, 0.98, spread)
        return PoseFixtures.pose(points)
    }

    private func kneeForm(
        kneeOffset: Float, hipY: Float = DepthBasisTests.squatHipY, spread: Float = 0.10,
        leftOffset: Float? = nil, rightOffset: Float? = nil
    ) throws -> SquatForm {
        func pose(_ h: Float) -> Pose {
            kneeShiftedPose(kneeOffset: kneeOffset, hipY: h, spread: spread,
                            leftOffset: leftOffset, rightOffset: rightOffset)
        }
        let calibration = try XCTUnwrap(StandingCalibration.from(frames: (0..<30).map { _ in
            (pose: kneeShiftedPose(kneeOffset: 0, hipY: Self.standingHipY, spread: spread),
             aspectRatio: aspect)
        }))
        let f = FrameFeatures.from(pose: pose(hipY), aspectRatio: aspect,
                                   calibration: calibration, view: .front, activeSide: nil)
        return analyzer.analyze(pose: pose(hipY), frameAspectRatio: aspect,
                                cameraAngle: .front, features: f)
    }

    func test_무릎이_발끝_위에_있으면_정상이다() throws {
        let form = try kneeForm(kneeOffset: 0)
        XCTAssertEqual(try XCTUnwrap(form.kneeToeDeviation), 0, accuracy: 0.01)
        XCTAssertEqual(form.kneeAlignment, .good)
        XCTAssertFalse(form.warnings.contains(.kneeValgus))
        XCTAssertFalse(form.warnings.contains(.kneeFlared))
    }

    func test_무릎이_안으로_말리면_valgus로_본다() throws {
        let form = try kneeForm(kneeOffset: 0.02)
        XCTAssertEqual(form.kneeAlignment, .valgus)
        XCTAssertTrue(form.warnings.contains(.kneeValgus))
    }

    /// **양방향이다** — 과도하게 벌리는 것도 잡는다.
    func test_무릎이_과도하게_벌어지면_오류로_본다() throws {
        let form = try kneeForm(kneeOffset: -0.02)
        XCTAssertEqual(form.kneeAlignment, .flared)
        XCTAssertTrue(form.warnings.contains(.kneeFlared))
    }

    func test_허용폭_안의_벗어남은_정상이다() throws {
        XCTAssertEqual(try kneeForm(kneeOffset: 0.007).kneeAlignment, .good)
        XCTAssertEqual(try kneeForm(kneeOffset: -0.007).kneeAlignment, .good)
    }

    func test_발_간격이_무너지면_무릎_정렬을_판정하지_않는다() throws {
        let narrow = try kneeForm(kneeOffset: 0.02, spread: 0.03)
        XCTAssertNil(narrow.kneeToeDeviation, "분모가 무너졌으면 값을 내지 않는다")
        XCTAssertNil(narrow.kneeAlignment)
        XCTAssertNotNil(try kneeForm(kneeOffset: 0.02).kneeToeDeviation)
    }

    func test_좌우_중_나쁜_쪽을_남긴다() throws {
        let leftBad = try kneeForm(kneeOffset: 0, leftOffset: 0.02, rightOffset: 0)
        XCTAssertEqual(leftBad.kneeToeSide, .left)
        XCTAssertEqual(leftBad.kneeAlignment, .valgus)

        let rightBad = try kneeForm(kneeOffset: 0, leftOffset: 0, rightOffset: 0.02)
        XCTAssertEqual(rightBad.kneeToeSide, .right)
        XCTAssertEqual(rightBad.kneeAlignment, .valgus)
    }

    func test_정렬이_정상이면_쪽을_남기지_않는다() throws {
        let good = try kneeForm(kneeOffset: 0)
        XCTAssertEqual(good.kneeAlignment, .good)
        XCTAssertNil(good.kneeToeSide)
    }

    func test_좌우_차이가_커지려면_한쪽이_이미_허용폭을_넘는다() throws {
        let form = try kneeForm(kneeOffset: 0, leftOffset: 0.02, rightOffset: 0)
        let worst = try XCTUnwrap(form.kneeToeDeviation)
        XCTAssertGreaterThan(abs(worst), thresholds.kneeToeToleranceRatio,
                             "나쁜 쪽이 허용폭을 넘지 않았는데 좌우차만 큰 경우는 실측에 없었다")
        XCTAssertNotEqual(form.kneeAlignment, .good)
    }

    func test_측면에서는_무릎_정렬을_판정하지_않는다() throws {
        let side = analyzer.analyze(pose: sidePose(flexionDegrees: 90), frameAspectRatio: aspect,
                                    cameraAngle: .side, features: try features(at: 90))
        XCTAssertNil(side.kneeToeDeviation)
        XCTAssertNil(side.kneeAlignment)
    }

    /// 폐기된 배수 방식이 **아무것도 잡지 못한다**는 사실을 붙들어 둔다.
    func test_무릎폭_배수_방식은_정상_표본을_전부_통과시킨다() {
        for gain in [Float(1.53), 1.58, 1.79, 2.04] {
            XCTAssertEqual(
                thresholds.kneeAlignment(standingRatio: 0.8, bottomRatio: 0.8 * gain), .good,
                "배수 \(gain) 은 임계값 \(thresholds.valgusSpreadGain) 위라 통과한다")
        }
    }

    // ── 기준선 없이도 되는 것 / 안 되는 것 ──────────────────

    func test_기준선이_없어도_골반_쏠림과_무릎_정렬을_낸다() {
        let f = FrameFeatures.from(pose: kneeShiftedPose(kneeOffset: 0.02), aspectRatio: aspect,
                                   calibration: nil, view: .front, activeSide: nil)
        XCTAssertNotNil(f.hipShiftRatio, "골반 쏠림")
        XCTAssertNotNil(f.leftKneeToeDeviation, "무릎–발끝(왼)")
        XCTAssertNotNil(f.rightKneeToeDeviation, "무릎–발끝(오)")
        let form = analyzer.analyze(pose: kneeShiftedPose(kneeOffset: 0.02),
                                    frameAspectRatio: aspect, cameraAngle: .front, features: f)
        XCTAssertEqual(form.kneeAlignment, .valgus)
    }

    func test_기준선이_없으면_거리_특징은_비운다() {
        let f = FrameFeatures.from(pose: sidePose(flexionDegrees: 90), aspectRatio: aspect,
                                   calibration: nil, view: .sideLeft, activeSide: .left)
        XCTAssertNil(f.depthRatio, "깊이 비율")
        XCTAssertNil(f.hipDropRatio, "엉덩이 하강")
        XCTAssertNil(f.leftHeelRise, "뒤꿈치 들림")
        XCTAssertNil(f.leftMedialKneeDisplacement, "무릎 내측 이동")
        XCTAssertNotNil(f.representativeKneeFlexion, "무릎 굴곡")
    }

    // ── 깊이 게이트 ─────────────────────────────────────────

    /// 🔴 **선 자세에서 판정하면 안 된다** — 임계값이 최저점 분포에서 나왔기 때문이다.
    func test_선_자세에서는_무릎_정렬을_판정하지_않는다() {
        let standing = kneeShiftedPose(kneeOffset: 0, hipY: Self.standingHipY)
        let f = FrameFeatures.from(pose: standing, aspectRatio: aspect, calibration: nil,
                                   view: .front, activeSide: nil)
        XCTAssertNotNil(f.leftKneeToeDeviation, "특징은 계산된다")
        let form = analyzer.analyze(pose: standing, frameAspectRatio: aspect,
                                    cameraAngle: .front, features: f)
        XCTAssertNil(form.kneeAlignment, "선 자세에서는 판정하지 않는다")
        XCTAssertFalse(form.warnings.contains { $0 == .kneeValgus || $0 == .kneeFlared },
                       "선 자세에서 무릎 경고가 뜨면 안 된다")
    }

    func test_굴곡이_충분하면_판정을_재개한다() throws {
        XCTAssertNil(try kneeForm(kneeOffset: 0.02, hipY: Self.standingHipY).kneeAlignment)
        XCTAssertEqual(try kneeForm(kneeOffset: 0.02).kneeAlignment, .valgus)
    }

    func test_자세_생성기가_깊이_게이트를_넘긴다() throws {
        func depth(hipY: Float) throws -> Float {
            try XCTUnwrap(FrameFeatures.from(
                pose: kneeShiftedPose(kneeOffset: 0, hipY: hipY), aspectRatio: aspect,
                calibration: nil, view: .front, activeSide: nil).shinDepthRatio)
        }
        let squat = try depth(hipY: Self.squatHipY)
        let standing = try depth(hipY: Self.standingHipY)
        XCTAssertGreaterThanOrEqual(squat, thresholds.kneeToeMinDepth,
                                    "앉은 자세 깊이 \(squat) 는 게이트 이상")
        XCTAssertLessThan(standing, thresholds.kneeToeMinDepth,
                          "선 자세 깊이 \(standing) 는 게이트 미만")
    }

    func test_무릎을_모아도_깊이_게이트는_열린다() throws {
        func features(_ offset: Float) -> FrameFeatures {
            FrameFeatures.from(pose: kneeShiftedPose(kneeOffset: offset), aspectRatio: aspect,
                               calibration: nil, view: .front, activeSide: nil)
        }
        let aligned = features(0)
        let kneesIn = features(0.02)
        let kneesInDepth = try XCTUnwrap(kneesIn.shinDepthRatio)
        XCTAssertGreaterThanOrEqual(kneesInDepth, thresholds.kneeToeMinDepth,
                                    "무릎을 모아도 깊이 게이트를 넘는다 (실제: \(kneesInDepth))")
        XCTAssertEqual(try XCTUnwrap(aligned.shinDepthRatio), kneesInDepth, accuracy: 0.05,
                       "깊이는 무릎의 좌우 이동에 거의 영향받지 않는다")
        XCTAssertEqual(analyzer.analyze(pose: kneeShiftedPose(kneeOffset: 0.02),
                                        frameAspectRatio: aspect, cameraAngle: .front,
                                        features: kneesIn).kneeAlignment, .valgus)
    }
}
