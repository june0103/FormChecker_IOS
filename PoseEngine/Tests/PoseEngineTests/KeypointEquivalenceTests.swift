import XCTest
@testable import PoseEngine

/// **Phase 0 게이트를 코드로 고정한다.**
///
/// Android에서 같은 이미지 4장을 프로덕션 경로(`RtmPoseEngine.analyze(Bitmap)`)에 넣어 받은
/// 키포인트가 `Resources/keypoints_android.csv`에 들어 있다. iOS가 그 값에서 벗어나면
/// 여기서 깨진다.
///
/// ## 왜 이 테스트가 이 저장소에서 가장 중요한가
/// 이 앱의 임계값 15개는 **자체 수집 15세션**으로 확정됐고, 그 값을 믿는 근거는
/// "같은 모델·같은 기기라 domain gap이 없다"였다. iOS가 다른 키포인트를 내면
/// **그 근거가 통째로 사라진다** — 임계값을 처음부터 다시 재야 한다.
///
/// 기준값 갱신: `tools/phase0.sh` (Android 저장소 경로를 `FORMCHECKER_AOS`로 준다)
final class KeypointEquivalenceTests: XCTestCase {

    /// PRD §3.1 G2. 0.01은 480px 폭에서 약 4.8px이다.
    private static let gate: Float = 0.01
    /// 실측은 이보다 두 자릿수 더 좋다. 조용한 퇴행을 잡으려면 실제 수준에서 조여야 한다.
    private static let tightGate: Float = 0.001

    private struct Reference {
        let x: Float
        let y: Float
        let confidence: Float
    }

    private func loadReference() throws -> [String: [Int: Reference]] {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "keypoints_android", withExtension: "csv",
                              subdirectory: "reference")
                ?? Bundle.module.resourceURL?
                    .appendingPathComponent("reference/keypoints_android.csv"),
            "Android 기준값 CSV가 번들에 없습니다"
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        var out: [String: [Int: Reference]] = [:]
        for line in text.split(separator: "\n").dropFirst() {
            let f = line.split(separator: ",", omittingEmptySubsequences: false)
            guard f.count >= 6,
                  let index = Int(f[1]),
                  let x = Float(f[3]), let y = Float(f[4]), let c = Float(f[5]) else { continue }
            out[String(f[0]), default: [:]][index] = Reference(x: x, y: y, confidence: c)
        }
        return out
    }

    private func pose(for image: String, mode: ResampleMode) throws -> Pose {
        let modelURL = try XCTUnwrap(RTMPoseEngine.bundledModelURL)
        let engine = try RTMPoseEngine(modelPath: modelURL.path, resampleMode: mode)
        let loaded = try TestImageLoader.load(image)
        var result: Pose?
        loaded.bytes.withUnsafeBytes { raw in
            result = engine.analyze(frame: RawFrame(
                baseAddress: raw.baseAddress!,
                width: loaded.width, height: loaded.height,
                bytesPerRow: loaded.bytesPerRow, channelOrder: loaded.channelOrder
            ))
        }
        return try XCTUnwrap(result, "\(image): 추론 실패")
    }

    func test_기본_설정이_Android와_같은_키포인트를_낸다() throws {
        let reference = try loadReference()
        XCTAssertFalse(reference.isEmpty, "기준값이 비어 있습니다")

        var worst: (image: String, index: Int, distance: Float) = ("", -1, 0)

        for (image, expected) in reference.sorted(by: { $0.key < $1.key }) {
            // 기본 생성자를 쓴다 — 기본값이 바뀌면 이 테스트가 깨져야 한다.
            let result = try pose(for: image, mode: RTMPoseEngine.defaultResampleMode)
            for (index, ref) in expected {
                let kp = result.keypoints[index]
                let d = hypot(kp.x - ref.x, kp.y - ref.y)
                if d > worst.distance { worst = (image, index, d) }
                XCTAssertLessThanOrEqual(
                    d, Self.gate,
                    "\(image) #\(index) \(kp.type): Android(\(ref.x), \(ref.y)) vs iOS(\(kp.x), \(kp.y))"
                )
            }
        }
        print("META,equivalence,worst=\(worst.distance),image=\(worst.image),index=\(worst.index)")
        XCTAssertLessThanOrEqual(
            worst.distance, Self.tightGate,
            "게이트(\(Self.gate))는 통과했지만 실측 수준(\(Self.tightGate))보다 나빠졌습니다 "
            + "— 전처리가 조용히 바뀌지 않았는지 보세요"
        )
    }

    /// 양선형 보간을 쓰면 **게이트를 크게 벗어난다**는 사실 자체를 붙들어 둔다.
    ///
    /// "더 좋은 보간으로 바꾸자"는 제안이 왜 틀렸는지를 이 테스트가 숫자로 답한다.
    func test_양선형_보간은_Android와_어긋난다() throws {
        let reference = try loadReference()
        let image = "squat_bottom_500x500"
        let expected = try XCTUnwrap(reference[image])
        let result = try pose(for: image, mode: .bilinear)

        let worst = expected.map { index, ref in
            hypot(result.keypoints[index].x - ref.x, result.keypoints[index].y - ref.y)
        }.max() ?? 0

        XCTAssertGreaterThan(
            worst, Self.gate,
            "양선형이 갑자기 일치한다면 Android 쪽 전처리가 바뀐 것이다 — 기준값을 다시 뜨세요"
        )
        print("META,bilinear_drift,\(worst)")
    }
}
