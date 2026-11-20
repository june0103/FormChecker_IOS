import XCTest
@testable import PoseEngine

/// Android `LetterboxTransformTest`의 이식.
final class LetterboxTransformTests: XCTestCase {

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
        let (x, y) = t.inverse(x: 0.25, y: 0.75)
        XCTAssertEqual(x, 0.25, accuracy: 1e-6)
        XCTAssertEqual(y, 0.75, accuracy: 1e-6)
    }

    func test_forward와_inverse는_서로를_되돌린다() {
        let t = LetterboxTransform(sourceWidth: 500, sourceHeight: 500,
                                   targetWidth: 192, targetHeight: 256)
        for (x, y) in [(Float(0), Float(0)), (0.5, 0.5), (1, 1), (0.13, 0.87)] {
            let f = t.forward(x: x, y: y)
            let back = t.inverse(x: f.x, y: f.y)
            XCTAssertEqual(back.x, x, accuracy: 1e-5)
            XCTAssertEqual(back.y, y, accuracy: 1e-5)
        }
    }

    func test_패딩을_걷어내지_않으면_좌표가_치우친다() {
        // 이 테스트는 "inverse를 빠뜨리면 생기는 오차"를 숫자로 붙들어 둔다.
        let t = LetterboxTransform(sourceWidth: 500, sourceHeight: 500,
                                   targetWidth: 192, targetHeight: 256)
        let letterboxY: Float = 0.5                   // 입력 한가운데
        let corrected = t.inverse(x: 0.5, y: letterboxY).y
        XCTAssertEqual(corrected, 0.5, accuracy: 1e-5)
        XCTAssertNotEqual(letterboxY, corrected - 0.0001)  // 변환이 실제로 뭔가 한다
    }
}
