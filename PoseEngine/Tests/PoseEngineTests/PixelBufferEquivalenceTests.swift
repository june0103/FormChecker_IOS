import CoreVideo
import XCTest
@testable import PoseEngine

/// **카메라 경로 게이트** — 실제 앱이 먹는 입력으로도 같은 답이 나오는가.
///
/// Phase 0의 첫 게이트는 PNG(RGBA)로 "같은 비트맵 → 같은 키포인트"를 증명했다.
/// 그런데 앱이 실제로 받는 것은 `AVCaptureVideoDataOutput`의 **BGRA 픽셀 버퍼**이고,
/// 거기에는 PNG에 없던 두 가지가 붙는다.
///
/// 1. **채널 순서가 반대다** — Android는 RGBA였다
/// 2. **행 패딩(stride)** — `bytesPerRow`가 `width × 4`보다 클 수 있다
///
/// 이 테스트들이 묶는 것은 전이 관계다:
/// ```
/// BGRA 픽셀버퍼  ==  RGBA 원본 바이트  ==  Android 기준값
///      (여기)              (Phase 0에서 증명)
/// ```
final class PixelBufferEquivalenceTests: XCTestCase {

    private static let images = [
        "squat_bottom_192x256", "squat_bottom_480x640",
        "squat_bottom_500x500", "standing_480x640",
    ]

    private func makeEngine() throws -> RTMPoseEngine {
        let url = try XCTUnwrap(RTMPoseEngine.bundledModelURL)
        return try RTMPoseEngine(modelPath: url.path)
    }

    private func pose(_ engine: RTMPoseEngine, rgba loaded: TestImageLoader.Loaded) throws -> Pose {
        var result: Pose?
        loaded.bytes.withUnsafeBytes { raw in
            result = engine.analyze(frame: RawFrame(
                baseAddress: raw.baseAddress!,
                width: loaded.width, height: loaded.height,
                bytesPerRow: loaded.bytesPerRow, channelOrder: loaded.channelOrder
            ))
        }
        return try XCTUnwrap(result)
    }

    private func assertSame(_ a: Pose, _ b: Pose, _ label: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        for (lhs, rhs) in zip(a.keypoints, b.keypoints) {
            XCTAssertEqual(lhs.x, rhs.x, "\(label) \(lhs.type).x", file: file, line: line)
            XCTAssertEqual(lhs.y, rhs.y, "\(label) \(lhs.type).y", file: file, line: line)
            XCTAssertEqual(lhs.confidence, rhs.confidence,
                           "\(label) \(lhs.type).confidence", file: file, line: line)
        }
    }

    // ── 1. 채널 순서 ────────────────────────────────────────

    func test_BGRA_입력은_RGBA_입력과_완전히_같은_키포인트를_낸다() throws {
        let engine = try makeEngine()
        for name in Self.images {
            let loaded = try TestImageLoader.load(name)
            let expected = try pose(engine, rgba: loaded)

            let (bgra, bytesPerRow) = TestPixelBuffer.bgraBytes(from: loaded)
            var actual: Pose?
            bgra.withUnsafeBytes { raw in
                actual = engine.analyze(frame: RawFrame(
                    baseAddress: raw.baseAddress!,
                    width: loaded.width, height: loaded.height,
                    bytesPerRow: bytesPerRow, channelOrder: .bgra
                ))
            }
            assertSame(expected, try XCTUnwrap(actual), name)
        }
    }

    func test_채널_순서를_틀리면_키포인트가_달라진다() throws {
        // 이 테스트가 깨지면 위 테스트가 아무것도 증명하지 않는다는 뜻이다
        // (예: 흑백 이미지라 R·B가 같아서 순서가 무의미한 경우).
        let engine = try makeEngine()
        let loaded = try TestImageLoader.load("squat_bottom_480x640")
        let correct = try pose(engine, rgba: loaded)

        let (bgra, bytesPerRow) = TestPixelBuffer.bgraBytes(from: loaded)
        var wrong: Pose?
        bgra.withUnsafeBytes { raw in
            // BGRA 버퍼를 RGBA라고 **잘못** 알려준다 — 실수했을 때 벌어지는 일.
            wrong = engine.analyze(frame: RawFrame(
                baseAddress: raw.baseAddress!,
                width: loaded.width, height: loaded.height,
                bytesPerRow: bytesPerRow, channelOrder: .rgba
            ))
        }
        let drifted = try XCTUnwrap(wrong)
        let worst = zip(correct.keypoints, drifted.keypoints)
            .map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 0
        print("META,channel_swap_drift,\(worst)")
        XCTAssertGreaterThan(worst, 0, "R·B를 뒤바꿔도 결과가 같다면 이 테스트 세트로는 검증이 안 된다")
    }

    // ── 2. 행 패딩 (stride) ────────────────────────────────

    func test_행_패딩이_있어도_같은_키포인트를_낸다() throws {
        let engine = try makeEngine()
        for name in Self.images {
            let loaded = try TestImageLoader.load(name)
            let expected = try pose(engine, rgba: loaded)

            // CoreVideo는 행을 16·64바이트로 정렬한다. 패딩 바이트에는 쓰레기값이 들어 있다.
            for padding in [16, 64, 252] {
                let (bgra, bytesPerRow) = TestPixelBuffer.bgraBytes(
                    from: loaded, extraRowPadding: padding
                )
                XCTAssertEqual(bytesPerRow, loaded.width * 4 + padding)
                var actual: Pose?
                bgra.withUnsafeBytes { raw in
                    actual = engine.analyze(frame: RawFrame(
                        baseAddress: raw.baseAddress!,
                        width: loaded.width, height: loaded.height,
                        bytesPerRow: bytesPerRow, channelOrder: .bgra
                    ))
                }
                assertSame(expected, try XCTUnwrap(actual), "\(name) pad=\(padding)")
            }
        }
    }

    // ── 3. 실제 CVPixelBuffer ──────────────────────────────

    func test_픽셀버퍼_경로가_원본_바이트_경로와_같다() throws {
        let engine = try makeEngine()
        for name in Self.images {
            let loaded = try TestImageLoader.load(name)
            let expected = try pose(engine, rgba: loaded)

            let pixelBuffer = try TestPixelBuffer.makeBGRA(from: loaded)
            let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
            print("META,pixelbuffer,\(name),bytesPerRow=\(stride),packed=\(loaded.width * 4)")

            let actual = try XCTUnwrap(engine.analyze(pixelBuffer: pixelBuffer), name)
            assertSame(expected, actual, "\(name) pixelBuffer")
        }
    }

    /// 전이 관계의 마지막 고리 — 픽셀 버퍼 경로가 **Android 기준값**과 일치하는가.
    func test_픽셀버퍼_경로가_Android_기준값과_일치한다() throws {
        let engine = try makeEngine()
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "keypoints_android", withExtension: "csv",
                              subdirectory: "reference")
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        var reference: [String: [Int: (Float, Float)]] = [:]
        for line in text.split(separator: "\n").dropFirst() {
            let f = line.split(separator: ",", omittingEmptySubsequences: false)
            guard f.count >= 6, let i = Int(f[1]),
                  let x = Float(f[3]), let y = Float(f[4]) else { continue }
            reference[String(f[0]), default: [:]][i] = (x, y)
        }

        var worst: Float = 0
        for (name, expected) in reference.sorted(by: { $0.key < $1.key }) {
            let loaded = try TestImageLoader.load(name)
            let pixelBuffer = try TestPixelBuffer.makeBGRA(from: loaded)
            let result = try XCTUnwrap(engine.analyze(pixelBuffer: pixelBuffer), name)
            for (index, ref) in expected {
                let kp = result.keypoints[index]
                let d = hypot(kp.x - ref.0, kp.y - ref.1)
                worst = max(worst, d)
                XCTAssertLessThanOrEqual(d, 0.01, "\(name) #\(index) \(kp.type)")
            }
        }
        print("META,pixelbuffer_vs_android,worst=\(worst)")
        XCTAssertLessThanOrEqual(worst, 0.001)
    }

    // ── 4. 지원하지 않는 포맷 ───────────────────────────────

    func test_픽셀_포맷_매핑() {
        XCTAssertEqual(PixelBufferInput.channelOrder(for: kCVPixelFormatType_32BGRA), .bgra)
        XCTAssertEqual(PixelBufferInput.channelOrder(for: kCVPixelFormatType_32RGBA), .rgba)
        XCTAssertEqual(PixelBufferInput.channelOrder(for: kCVPixelFormatType_32ARGB), .argb)
        XCTAssertNil(PixelBufferInput.channelOrder(
            for: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange))
    }

    func test_YUV_버퍼는_거절한다() throws {
        // 카메라를 YUV로 설정하면 색 변환 계수가 Android 경로에 없던 새 변수가 된다.
        // 조용히 이상한 답을 내느니 nil을 낸다.
        let engine = try makeEngine()
        let yuv = try TestPixelBuffer.makeYUV(width: 480, height: 640)
        XCTAssertNil(engine.analyze(pixelBuffer: yuv))
    }
}

// ── 5. 미러링 ───────────────────────────────────────────

extension PixelBufferEquivalenceTests {

    /// 좌우를 뒤집은 RGBA 바이트.
    private func flipped(_ loaded: TestImageLoader.Loaded) -> (bytes: [UInt8], bytesPerRow: Int) {
        let bpp = loaded.channelOrder.bytesPerPixel
        let bytesPerRow = loaded.width * bpp
        var out = [UInt8](repeating: 0, count: bytesPerRow * loaded.height)
        loaded.bytes.withUnsafeBytes { raw in
            let src = raw.bindMemory(to: UInt8.self)
            for y in 0..<loaded.height {
                for x in 0..<loaded.width {
                    let s = y * loaded.bytesPerRow + x * bpp
                    let d = y * bytesPerRow + (loaded.width - 1 - x) * bpp
                    for c in 0..<bpp { out[d + c] = src[s + c] }
                }
            }
        }
        return (out, bytesPerRow)
    }

    /// 🔴 **엔진은 입력을 좌우 반전하지 않는다.**
    ///
    /// 모델은 키포인트를 해부학적 기준(그 사람의 실제 왼쪽/오른쪽)으로 라벨링한다.
    /// 반전된 이미지를 넣으면 좌우 라벨이 뒤바뀌어 나오고, **무릎 판정이 조용히 반대로**
    /// 된다. 전면 카메라의 거울 효과는 **그릴 때만** 적용해야 한다.
    ///
    /// 이 테스트는 "엔진이 방향을 정규화하지 않는다"는 사실을 붙든다 — 누군가 전처리에
    /// 미러링을 넣으면 여기서 깨진다.
    func test_엔진은_입력을_미러링하지_않는다() throws {
        let engine = try makeEngine()
        let loaded = try TestImageLoader.load("squat_bottom_480x640")
        let original = try pose(engine, rgba: loaded)

        let (bytes, bytesPerRow) = flipped(loaded)
        var mirroredPose: Pose?
        bytes.withUnsafeBytes { raw in
            mirroredPose = engine.analyze(frame: RawFrame(
                baseAddress: raw.baseAddress!,
                width: loaded.width, height: loaded.height,
                bytesPerRow: bytesPerRow, channelOrder: loaded.channelOrder
            ))
        }
        let mirrored = try XCTUnwrap(mirroredPose)

        // 엔진이 방향을 정규화한다면 두 결과가 같아질 것이다. 같아지면 안 된다.
        let same = zip(original.keypoints, mirrored.keypoints)
            .allSatisfy { $0.x == $1.x && $0.y == $1.y }
        XCTAssertFalse(same, "엔진이 입력 방향을 정규화하고 있다 — 미러링이 끼어든 것 아닌지 보세요")

        // 좌우 라벨이 실제로 뒤바뀌는지 기록해 둔다 (주장하지 않고 수치만 남긴다 —
        // 측면 촬영이라 좌우 다리가 겹쳐 보이는 프레임에서는 깔끔하게 바뀌지 않을 수 있다).
        for (left, right) in [(KeypointType.leftKnee, KeypointType.rightKnee),
                              (.leftAnkle, .rightAnkle), (.leftHeel, .rightHeel)] {
            let swapDistance = abs((1 - mirrored[left].x) - original[right].x)
            print("META,mirror_label_swap,\(left)->\(right),\(swapDistance)")
        }
    }
}
