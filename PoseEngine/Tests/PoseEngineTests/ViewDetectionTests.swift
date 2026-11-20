import XCTest
@testable import PoseEngine

/// 촬영 방향 판별. 수치는 **실측 15세션**에서 나왔다.
final class ViewDetectionTests: XCTestCase {

    private let aspect: Float = 0.75

    /// 실측 세션별 중앙값 — 정면 0.675~0.731 / 측면 0.058~0.105.
    private let frontHalf: Float = 0.093
    private let sideHalf: Float = 0.012
    private let obliqueHalf: Float = 0.055

    private func pose(shoulderHalf: Float, confidence: Float = 0.9) -> Pose {
        PoseFixtures.pose([
            .leftShoulder: (0.50 - shoulderHalf, 0.30, confidence),
            .rightShoulder: (0.50 + shoulderHalf, 0.30, confidence),
            .leftHip: (0.49, 0.50, confidence),
            .rightHip: (0.51, 0.50, confidence),
        ])
    }

    private func frames(_ halves: [Float]) -> [(pose: Pose, aspectRatio: Float)] {
        halves.map { (pose: pose(shoulderHalf: $0), aspectRatio: aspect) }
    }

    func test_실측_정면_중앙값은_정면으로_읽힌다() {
        XCTAssertEqual(CaptureQuality.estimateView(pose: pose(shoulderHalf: frontHalf),
                                                   aspectRatio: aspect), .front)
    }

    func test_실측_측면_중앙값은_측면으로_읽힌다() {
        XCTAssertEqual(CaptureQuality.estimateView(pose: pose(shoulderHalf: sideHalf),
                                                   aspectRatio: aspect), .side)
    }

    /// **0.15와 0.55 사이가 비어 있다** — 그 사이는 비스듬한 것이다.
    func test_두_무리_사이는_애매로_읽힌다() {
        XCTAssertEqual(CaptureQuality.estimateView(pose: pose(shoulderHalf: obliqueHalf),
                                                   aspectRatio: aspect), .ambiguous)
    }

    func test_어깨가_안_보이면_추정하지_않는다() {
        XCTAssertNil(CaptureQuality.estimateView(
            pose: pose(shoulderHalf: frontHalf, confidence: 0.1), aspectRatio: aspect))
    }

    /// 🔴 **프레임 단위 오분류를 다수결이 흡수한다** — 이것이 세션 단위로 정하는 이유다.
    func test_소수의_오분류_프레임은_다수결이_흡수한다() {
        let mixed = frames([frontHalf, frontHalf, frontHalf, frontHalf,
                            sideHalf,   // 어깨가 무너진 프레임
                            frontHalf, frontHalf, frontHalf])
        XCTAssertEqual(CaptureQuality.estimateView(frames: mixed), .front)
    }

    func test_애매한_프레임이_섞여도_다수가_이긴다() {
        let mixed = frames([sideHalf, sideHalf, obliqueHalf, sideHalf, obliqueHalf])
        XCTAssertEqual(CaptureQuality.estimateView(frames: mixed), .side)
    }

    func test_대부분이_애매하면_애매가_나온다() {
        let mixed = frames([obliqueHalf, obliqueHalf, obliqueHalf, frontHalf])
        XCTAssertEqual(CaptureQuality.estimateView(frames: mixed), .ambiguous)
    }

    func test_프레임이_없으면_nil이다() {
        XCTAssertNil(CaptureQuality.estimateView(frames: []))
    }

    func test_추정_불가_프레임만_있으면_nil이다() {
        let invisible = (0..<5).map {
            _ in (pose: pose(shoulderHalf: frontHalf, confidence: 0.1), aspectRatio: aspect)
        }
        XCTAssertNil(CaptureQuality.estimateView(frames: invisible))
    }

    func test_측면_경계는_0_30이다() {
        XCTAssertEqual(AngleDetectionThresholds().sideRatio, 0.30, accuracy: 1e-6)
        XCTAssertEqual(CaptureQuality.estimateView(pose: pose(shoulderHalf: 0.29 / 7.5),
                                                   aspectRatio: aspect), .side)
        XCTAssertEqual(CaptureQuality.estimateView(pose: pose(shoulderHalf: 0.31 / 7.5),
                                                   aspectRatio: aspect), .ambiguous)
    }

    func test_경계는_설정으로_바뀐다() {
        var loose = AngleDetectionThresholds()
        loose.sideRatio = 0.5
        XCTAssertEqual(CaptureQuality.estimateView(pose: pose(shoulderHalf: obliqueHalf),
                                                   aspectRatio: aspect, thresholds: loose), .side)
    }

    /// 종횡비 보정이 실제로 결과를 바꾼다 — 빠뜨리면 기기마다 다른 답이 나온다.
    func test_종횡비가_결과를_바꾼다() {
        let borderline = pose(shoulderHalf: 0.29 / 7.5)
        XCTAssertEqual(CaptureQuality.estimateView(pose: borderline, aspectRatio: aspect), .side)
        XCTAssertEqual(CaptureQuality.estimateView(pose: borderline, aspectRatio: 1), .ambiguous)
    }
}
