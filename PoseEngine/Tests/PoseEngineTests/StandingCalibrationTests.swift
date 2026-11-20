import XCTest
@testable import PoseEngine

final class StandingCalibrationTests: XCTestCase {

    private let aspect: Float = 0.75

    private func standingPose(confidence: Float = 0.9) -> Pose {
        PoseFixtures.pose([
            .leftShoulder: (0.40, 0.30, confidence), .rightShoulder: (0.60, 0.30, confidence),
            .leftHip: (0.44, 0.50, confidence), .rightHip: (0.56, 0.50, confidence),
            .leftKnee: (0.44, 0.70, confidence), .rightKnee: (0.56, 0.70, confidence),
            .leftAnkle: (0.44, 0.90, confidence), .rightAnkle: (0.56, 0.90, confidence),
            .neck: (0.50, 0.32, confidence),
            .leftHeel: (0.44, 0.94, confidence), .rightHeel: (0.56, 0.94, confidence),
            .leftBigToe: (0.52, 0.94, confidence), .rightBigToe: (0.64, 0.94, confidence),
            .leftSmallToe: (0.52, 0.94, confidence), .rightSmallToe: (0.64, 0.94, confidence),
        ])
    }

    private func frames(_ count: Int, confidence: Float = 0.9)
        -> [(pose: Pose, aspectRatio: Float)] {
        (0..<count).map { _ in (pose: standingPose(confidence: confidence), aspectRatio: aspect) }
    }

    func test_체절_길이를_손계산값과_같게_잰다() throws {
        let calibration = try XCTUnwrap(StandingCalibration.from(frames: frames(30)))
        XCTAssertEqual(calibration.femurLength, 0.20, accuracy: 0.001, "대퇴")
        XCTAssertEqual(calibration.tibiaLength, 0.20, accuracy: 0.001, "정강이")
        XCTAssertEqual(calibration.legLength, 0.40, accuracy: 0.001, "다리 전체")
        XCTAssertEqual(calibration.trunkLength, 0.20, accuracy: 0.001, "몸통")
    }

    func test_가로_길이에_종횡비가_적용된다() throws {
        let calibration = try XCTUnwrap(StandingCalibration.from(frames: frames(30)))
        XCTAssertEqual(calibration.hipWidth, 0.09, accuracy: 0.001, "골반 너비")
        XCTAssertEqual(calibration.shoulderWidth, 0.15, accuracy: 0.001, "어깨 너비")
    }

    func test_종횡비를_바꾸면_가로_길이만_변한다() throws {
        let a = try XCTUnwrap(StandingCalibration.from(
            frames: (0..<30).map { _ in (pose: standingPose(), aspectRatio: Float(0.75)) }))
        let b = try XCTUnwrap(StandingCalibration.from(
            frames: (0..<30).map { _ in (pose: standingPose(), aspectRatio: Float(1.50)) }))
        XCTAssertEqual(b.hipWidth, a.hipWidth * 2, accuracy: 0.001)
        XCTAssertEqual(b.femurLength, a.femurLength, accuracy: 0.001, "세로 길이는 영향받지 않는다")
    }

    func test_대퇴_정강이_비율을_따로_낸다() throws {
        let calibration = try XCTUnwrap(StandingCalibration.from(frames: frames(30)))
        XCTAssertEqual(calibration.femurTibiaRatio, 1.0, accuracy: 0.001)
    }

    /// 굴곡각 규약 — **곧게 서면 0**이다.
    func test_곧게_선_자세의_무릎_굴곡은_0에_가깝다() throws {
        let calibration = try XCTUnwrap(StandingCalibration.from(frames: frames(30)))
        XCTAssertLessThan(calibration.standingKneeFlexion, 1,
                          "곧게 서면 0 (실제 \(calibration.standingKneeFlexion))")
    }

    func test_프레임이_부족하면_캘리브레이션하지_않는다() {
        XCTAssertNil(StandingCalibration.from(frames: frames(5)))
    }

    func test_confidence가_낮은_프레임은_제외한다() throws {
        let mixed = frames(25, confidence: 0.9) + frames(15, confidence: 0.3)
        let calibration = try XCTUnwrap(StandingCalibration.from(frames: mixed))
        XCTAssertEqual(calibration.framesUsed, 25, "신뢰 가능한 프레임만 평균한다")
    }

    func test_필수_키포인트가_없으면_캘리브레이션하지_않는다() {
        let noLegs = (0..<30).map { _ -> (pose: Pose, aspectRatio: Float) in
            let stripped = standingPose().mapKeypoints { keypoint in
                (keypoint.type == .leftKnee || keypoint.type == .rightKnee)
                    ? keypoint.with(confidence: 0) : keypoint
            }
            return (pose: stripped, aspectRatio: aspect)
        }
        XCTAssertNil(StandingCalibration.from(frames: noLegs))
    }

    func test_정상_기립_자세는_통과한다() throws {
        let result = try XCTUnwrap(StandingCalibration.from(frames: frames(30))).validate()
        XCTAssertTrue(result.passed, "문제: \(result.problems)")
    }

    func test_사람이_너무_작게_찍히면_차단한다() throws {
        let small = (0..<30).map { _ -> (pose: Pose, aspectRatio: Float) in
            (pose: standingPose().mapKeypoints { $0.with(y: $0.y * 0.2) }, aspectRatio: aspect)
        }
        let result = try XCTUnwrap(StandingCalibration.from(frames: small)).validate()
        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.problems.contains(.subjectTooSmall))
    }

    /// **발 부재는 차단 사유가 아니다** — 발 관련 항목만 빠진다.
    func test_발이_안_보여도_캘리브레이션은_통과한다() throws {
        let noFeet = (0..<30).map { _ -> (pose: Pose, aspectRatio: Float) in
            let stripped = standingPose().mapKeypoints { keypoint in
                keypoint.type.rawValue >= KeypointType.leftBigToe.rawValue
                    ? keypoint.with(confidence: 0) : keypoint
            }
            return (pose: stripped, aspectRatio: aspect)
        }
        let calibration = try XCTUnwrap(StandingCalibration.from(frames: noFeet))
        let result = calibration.validate()
        XCTAssertTrue(result.passed, "발 부재는 차단 사유가 아니다")
        XCTAssertTrue(result.problems.contains(.footNotVisible))
        XCTAssertEqual(calibration.footLength, 0, accuracy: 0.0001)
    }

    func test_움직임이_감지되면_차단한다() throws {
        // 평행 이동은 **길이를 바꾸지 않으므로** 통과해야 한다.
        let moving = (0..<30).map { index -> (pose: Pose, aspectRatio: Float) in
            (pose: standingPose().mapKeypoints { $0.with(y: $0.y + Float(index) * 0.004) },
             aspectRatio: aspect)
        }
        XCTAssertTrue(try XCTUnwrap(StandingCalibration.from(frames: moving)).validate().passed,
                      "평행 이동은 길이를 바꾸지 않아 통과해야 한다")

        let jittery = (0..<30).map { index -> (pose: Pose, aspectRatio: Float) in
            let shifted = standingPose().mapKeypoints { keypoint in
                (keypoint.type == .leftKnee || keypoint.type == .rightKnee)
                    ? keypoint.with(y: keypoint.y + Float(index % 2) * 0.05) : keypoint
            }
            return (pose: shifted, aspectRatio: aspect)
        }
        let result = try XCTUnwrap(StandingCalibration.from(frames: jittery)).validate()
        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.problems.contains(.unstable))
    }

    // ── 활성측 ──────────────────────────────────────────────

    private func sidedPose(leftConfidence: Float, rightConfidence: Float) -> Pose {
        standingPose().mapKeypoints { keypoint in
            switch keypoint.type {
            case .leftHip, .leftKnee, .leftAnkle: keypoint.with(confidence: leftConfidence)
            case .rightHip, .rightKnee, .rightAnkle: keypoint.with(confidence: rightConfidence)
            default: keypoint
            }
        }
    }

    private func sidedFrames(left: Float, right: Float, count: Int = 30)
        -> [(pose: Pose, aspectRatio: Float)] {
        (0..<count).map { _ in
            (pose: sidedPose(leftConfidence: left, rightConfidence: right), aspectRatio: aspect)
        }
    }

    func test_신뢰도가_높은_쪽을_가까운_다리로_본다() {
        XCTAssertEqual(StandingCalibration.nearerSide(frames: sidedFrames(left: 0.9, right: 0.5)), .left)
        XCTAssertEqual(StandingCalibration.nearerSide(frames: sidedFrames(left: 0.5, right: 0.9)), .right)
    }

    /// 🔴 **프레임마다 활성측을 바꾸면 관절 좌표가 전환되면서 각도가 크게 튄다.**
    func test_한_프레임의_튐으로_활성측이_뒤집히지_않는다() {
        let frames = sidedFrames(left: 0.8, right: 0.6, count: 29)
            + [(pose: sidedPose(leftConfidence: 0.1, rightConfidence: 0.99), aspectRatio: aspect)]
        XCTAssertEqual(StandingCalibration.nearerSide(frames: frames), .left)
    }

    func test_프레임이_없으면_활성측을_정하지_않는다() {
        XCTAssertNil(StandingCalibration.nearerSide(frames: []))
    }

    func test_좌우_신뢰도가_같으면_왼쪽으로_고정한다() {
        XCTAssertEqual(StandingCalibration.nearerSide(frames: sidedFrames(left: 0.7, right: 0.7)), .left)
    }
}
