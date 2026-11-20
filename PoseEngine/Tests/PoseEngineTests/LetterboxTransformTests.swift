import XCTest
@testable import PoseEngine

/// Android `LetterboxTransformTest`의 이식.
///
/// > ⚠ Android의 `유효하지 않은 크기는 거부한다`는 이식하지 않았다. Kotlin `require`는
/// > 잡을 수 있는 예외를 던지지만 Swift `precondition`은 트랩이라 같은 프로세스에서 검증할
/// > 수 없다. 계약 자체는 `LetterboxTransform`의 `precondition`이 그대로 지킨다.
final class LetterboxTransformTests: XCTestCase {

    func test_가로로_긴_프레임은_상하에_패딩이_생긴다() {
        let t = LetterboxTransform(sourceWidth: 1920, sourceHeight: 1080, targetSize: 192)
        XCTAssertEqual(t.scaledWidth, 192)
        XCTAssertEqual(t.scaledHeight, 108)
        XCTAssertEqual(t.padLeft, 0)
        XCTAssertEqual(t.padTop, 42)
    }

    func test_세로로_긴_프레임은_좌우에_패딩이_생긴다() {
        let t = LetterboxTransform(sourceWidth: 1080, sourceHeight: 1920, targetSize: 192)
        XCTAssertEqual(t.scaledWidth, 108)
        XCTAssertEqual(t.scaledHeight, 192)
        XCTAssertEqual(t.padLeft, 42)
        XCTAssertEqual(t.padTop, 0)
    }

    func test_정사각_프레임은_패딩이_없다() {
        let t = LetterboxTransform(sourceWidth: 720, sourceHeight: 720, targetSize: 192)
        XCTAssertEqual(t.padLeft, 0)
        XCTAssertEqual(t.padTop, 0)
        XCTAssertEqual(t.scaledWidth, 192)
    }

    func test_forward_후_inverse하면_원래_좌표로_돌아온다() {
        let t = LetterboxTransform(sourceWidth: 1920, sourceHeight: 1080, targetSize: 192)
        for x in [Float(0), 0.25, 0.5, 0.75, 1] {
            for y in [Float(0), 0.25, 0.5, 0.75, 1] {
                let forward = t.forward(x: x, y: y)
                let back = t.inverse(x: forward.x, y: forward.y)
                XCTAssertEqual(back.x, x, accuracy: 0.01, "x=\(x)")
                XCTAssertEqual(back.y, y, accuracy: 0.01, "y=\(y)")
            }
        }
    }

    func test_중심점은_변환_후에도_중심이다() {
        let t = LetterboxTransform(sourceWidth: 1920, sourceHeight: 1080, targetSize: 192)
        let center = t.forward(x: 0.5, y: 0.5)
        XCTAssertEqual(center.x, 0.5, accuracy: 0.01)
        XCTAssertEqual(center.y, 0.5, accuracy: 0.01)
    }

    /// 이 변환을 빠뜨리면 스켈레톤이 패딩 폭만큼 치우쳐 그려지고 각도도 함께 틀어진다.
    func test_letterbox는_단순_리사이즈와_다른_좌표를_만든다() {
        let t = LetterboxTransform(sourceWidth: 1920, sourceHeight: 1080, targetSize: 192)
        let top = t.forward(x: 0.5, y: 0)
        XCTAssertGreaterThan(top.y, 0.2, "상단이 패딩만큼 안쪽으로 밀려야 한다 (실제: \(top.y))")
    }

    // ── iOS 추가 ────────────────────────────────────────────

    /// **3:4는 모델이 정한 값이다** — RTMPose 입력이 192×256이라 패딩이 0이다.
    func test_프리뷰_3대4는_패딩이_0이다() {
        let t = LetterboxTransform(sourceWidth: 480, sourceHeight: 640,
                                   targetWidth: 192, targetHeight: 256)
        XCTAssertEqual(t.scaledWidth, 192)
        XCTAssertEqual(t.scaledHeight, 256)
        XCTAssertEqual(t.padLeft, 0)
        XCTAssertEqual(t.padTop, 0)
    }

    func test_정사각형_입력은_위아래에_패딩이_생긴다() {
        let t = LetterboxTransform(sourceWidth: 500, sourceHeight: 500,
                                   targetWidth: 192, targetHeight: 256)
        XCTAssertEqual(t.scaledWidth, 192)
        XCTAssertEqual(t.scaledHeight, 192)
        XCTAssertEqual(t.padLeft, 0)
        XCTAssertEqual(t.padTop, 32)
    }

    func test_같은_크기면_변환이_항등이다() {
        let t = LetterboxTransform(sourceWidth: 192, sourceHeight: 256,
                                   targetWidth: 192, targetHeight: 256)
        XCTAssertEqual(t.scale, 1)
        XCTAssertEqual(t.padLeft, 0)
        XCTAssertEqual(t.padTop, 0)
        let back = t.inverse(x: 0.25, y: 0.75)
        XCTAssertEqual(back.x, 0.25, accuracy: 1e-6)
        XCTAssertEqual(back.y, 0.75, accuracy: 1e-6)
    }
}
