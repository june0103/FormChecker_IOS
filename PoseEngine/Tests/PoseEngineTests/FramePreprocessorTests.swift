import XCTest
@testable import PoseEngine

/// 전처리에서 **조용히 틀리는** 자리들을 숫자로 붙들어 둔다.
///
/// 03 문서 §4가 예고한 네 가지 — 색 채널 순서, 리샘플링 보간, 패딩 색, 이중 정규화 —
/// 중 코드로 고정할 수 있는 것들이다.
final class FramePreprocessorTests: XCTestCase {

    /// 가로 w, 세로 h의 RGBA 버퍼를 만든다. 픽셀 값은 (r, g, b) 고정.
    private func makeBuffer(w: Int, h: Int, r: UInt8, g: UInt8, b: UInt8) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = r; bytes[i + 1] = g; bytes[i + 2] = b; bytes[i + 3] = 255
        }
        return bytes
    }

    private func run(
        bytes: [UInt8], w: Int, h: Int, order: ChannelOrder,
        targetW: Int, targetH: Int, mode: ResampleMode
    ) -> [Float] {
        let transform = LetterboxTransform(sourceWidth: w, sourceHeight: h,
                                           targetWidth: targetW, targetHeight: targetH)
        var out = [Float](repeating: -1, count: targetW * targetH * 3)
        out.withUnsafeMutableBufferPointer { dst in
            bytes.withUnsafeBytes { src in
                FramePreprocessor.fill(
                    destination: dst, transform: transform,
                    source: src.baseAddress!, sourceBytesPerRow: w * order.bytesPerPixel,
                    channelOrder: order, mode: mode
                )
            }
        }
        return out
    }

    func test_값을_0에서_255_그대로_넣는다() {
        // 🔴 모델이 정규화를 그래프에 품고 있다. 여기서 ÷255 하면 이중 적용이 된다.
        let bytes = makeBuffer(w: 8, h: 8, r: 200, g: 100, b: 50)
        let out = run(bytes: bytes, w: 8, h: 8, order: .rgba, targetW: 8, targetH: 8, mode: .nearest)
        XCTAssertEqual(out[0], 200)
        XCTAssertEqual(out[1], 100)
        XCTAssertEqual(out[2], 50)
    }

    func test_BGRA는_R과_B가_바뀐다() {
        // CameraX는 RGBA, AVCaptureVideoDataOutput은 BGRA를 준다.
        // 바꾸지 않으면 크래시 없이 키포인트만 조용히 틀어진다.
        let bytes = makeBuffer(w: 4, h: 4, r: 10, g: 20, b: 30)
        let asRGBA = run(bytes: bytes, w: 4, h: 4, order: .rgba, targetW: 4, targetH: 4, mode: .nearest)
        let asBGRA = run(bytes: bytes, w: 4, h: 4, order: .bgra, targetW: 4, targetH: 4, mode: .nearest)
        XCTAssertEqual(asRGBA[0], 10); XCTAssertEqual(asRGBA[2], 30)
        XCTAssertEqual(asBGRA[0], 30); XCTAssertEqual(asBGRA[2], 10)
        XCTAssertEqual(asRGBA[1], asBGRA[1], "G는 두 배치에서 같은 자리다")
    }

    func test_패딩은_검정이다() {
        // 정사각형 입력 → 위아래 32px 패딩.
        let bytes = makeBuffer(w: 100, h: 100, r: 255, g: 255, b: 255)
        let out = run(bytes: bytes, w: 100, h: 100, order: .rgba,
                      targetW: 192, targetH: 256, mode: .nearest)
        // 맨 윗줄은 패딩이어야 한다.
        for x in 0..<192 {
            let o = x * 3
            XCTAssertEqual(out[o], 0, "패딩이 검정이 아닙니다 (x=\(x))")
        }
        // 가운데는 원본(흰색).
        let center = ((256 / 2) * 192 + 96) * 3
        XCTAssertEqual(out[center], 255)
    }

    func test_크기가_같으면_보간_방식과_무관하다() {
        // 프리뷰 3:4 → 192×256은 리사이즈가 없다. 여기서 두 방식이 갈리면 전처리에 버그가 있다.
        var bytes = [UInt8](repeating: 0, count: 192 * 256 * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = UInt8((i / 4) % 256)
            bytes[i + 1] = UInt8((i / 4 / 7) % 256)
            bytes[i + 2] = UInt8((i / 4 / 13) % 256)
            bytes[i + 3] = 255
        }
        let nearest = run(bytes: bytes, w: 192, h: 256, order: .rgba,
                          targetW: 192, targetH: 256, mode: .nearest)
        let bilinear = run(bytes: bytes, w: 192, h: 256, order: .rgba,
                           targetW: 192, targetH: 256, mode: .bilinear)
        XCTAssertEqual(nearest, bilinear)
        // 그리고 원본 그대로여야 한다.
        XCTAssertEqual(nearest[0], Float(bytes[0]))
        XCTAssertEqual(nearest[3], Float(bytes[4]))
    }

    func test_단색_이미지는_보간해도_같은_값이다() {
        let bytes = makeBuffer(w: 480, h: 640, r: 77, g: 88, b: 99)
        for mode in ResampleMode.allCases {
            let out = run(bytes: bytes, w: 480, h: 640, order: .rgba,
                          targetW: 192, targetH: 256, mode: mode)
            XCTAssertEqual(out[0], 77, accuracy: 0.001, "\(mode)")
            XCTAssertEqual(out[1], 88, accuracy: 0.001, "\(mode)")
            XCTAssertEqual(out[2], 99, accuracy: 0.001, "\(mode)")
        }
    }
}
