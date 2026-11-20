import XCTest
@testable import PoseEngine

/// **Phase 0 게이트** — 고정 이미지의 키포인트 26개를 찍어낸다.
///
/// 이 덤프를 Android 쪽 같은 하네스의 출력과 대조해 ±0.01 안에 드는지 본다.
/// 여기서 어긋나면 임계값 15개의 근거(자체 수집 15세션)가 통째로 무효가 되므로,
/// **화면을 만들기 전에** 이 테스트부터 통과시킨다.
///
/// 결과는 `KPDUMP,` 로 시작하는 줄로 표준출력에 나간다 — 시뮬레이터 샌드박스 밖으로
/// 파일을 꺼내는 것보다 단순하고, CI 로그에 그대로 남는다.
final class KeypointDumpTests: XCTestCase {

    private static let images = [
        "squat_bottom_192x256",   // 리사이즈·패딩 없음 → 색 순서·정규화만 검증
        "squat_bottom_480x640",   // 리사이즈만 (패딩 0) → 실제 카메라 경로
        "squat_bottom_500x500",   // 리사이즈 + 상하 패딩
        "standing_480x640",
    ]

    func test_모델이_번들에_들어_있다() throws {
        let url = try XCTUnwrap(RTMPoseEngine.bundledModelURL, "모델이 번들에 없습니다")
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
        print("META,model,\(url.lastPathComponent),\(size ?? -1)")
        XCTAssertGreaterThan(size ?? 0, 1_000_000)
    }

    func test_테스트_이미지가_원본_바이트로_읽힌다() throws {
        for name in Self.images {
            let loaded = try TestImageLoader.load(name)
            print("META,image,\(name),\(loaded.width)x\(loaded.height),"
                  + "order=\(loaded.channelOrder.rawValue),bpr=\(loaded.bytesPerRow),"
                  + "raw=\(loaded.usedRawBytes),\(loaded.describedFormat)")
            XCTAssertTrue(loaded.usedRawBytes, "\(name): 원본 바이트를 쓰지 못했습니다")
        }
    }

    func test_키포인트_덤프_양쪽_리샘플링() throws {
        let modelURL = try XCTUnwrap(RTMPoseEngine.bundledModelURL)

        for mode in ResampleMode.allCases {
            let engine = try RTMPoseEngine(modelPath: modelURL.path, resampleMode: mode)
            print("META,engine,\(engine.modelName),mode=\(mode.rawValue),"
                  + "loadMs=\(String(format: "%.1f", Double(engine.modelLoadTimeNanos) / 1e6))")

            for name in Self.images {
                let loaded = try TestImageLoader.load(name)
                var pose: Pose?
                loaded.bytes.withUnsafeBytes { raw in
                    let frame = RawFrame(
                        baseAddress: raw.baseAddress!,
                        width: loaded.width,
                        height: loaded.height,
                        bytesPerRow: loaded.bytesPerRow,
                        channelOrder: loaded.channelOrder
                    )
                    pose = engine.analyze(frame: frame)
                }
                let result = try XCTUnwrap(pose, "\(name): 추론 실패")
                XCTAssertEqual(result.keypoints.count, 26)

                print("META,infer,\(name),\(mode.rawValue),"
                      + "ms=\(String(format: "%.2f", Double(result.inferenceTimeNanos) / 1e6))")
                for kp in result.keypoints {
                    print(String(
                        format: "KPDUMP,%@,%@,%d,%@,%.6f,%.6f,%.6f",
                        name, mode.rawValue, kp.type.rawValue, "\(kp.type)",
                        kp.x, kp.y, kp.confidence
                    ))
                }
            }
        }
    }

    /// 추론이 실제로 사람을 찾았는지에 대한 최소 신뢰 검사.
    /// (동등성과 별개로, 덤프가 전부 쓰레기값이면 비교 자체가 무의미하다)
    func test_주요_관절이_신뢰할만하게_잡힌다() throws {
        let modelURL = try XCTUnwrap(RTMPoseEngine.bundledModelURL)
        let engine = try RTMPoseEngine(modelPath: modelURL.path, resampleMode: .bilinear)
        let loaded = try TestImageLoader.load("squat_bottom_480x640")

        var pose: Pose?
        loaded.bytes.withUnsafeBytes { raw in
            pose = engine.analyze(frame: RawFrame(
                baseAddress: raw.baseAddress!,
                width: loaded.width, height: loaded.height,
                bytesPerRow: loaded.bytesPerRow, channelOrder: loaded.channelOrder
            ))
        }
        let result = try XCTUnwrap(pose)

        // 스쿼트 판정의 핵심 관절. 발 6개는 이 모델을 쓰는 이유 그 자체다.
        let required: [KeypointType] = [
            .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle,
            .leftHeel, .rightHeel, .leftBigToe, .rightBigToe,
        ]
        for type in required {
            let kp = result[type]
            XCTAssertTrue(
                result.isReliable(type),
                "\(type) confidence \(kp.confidence) < \(Pose.minConfidence)"
            )
            XCTAssertTrue((-0.1...1.1).contains(kp.x), "\(type) x=\(kp.x) 범위 밖")
            XCTAssertTrue((-0.1...1.1).contains(kp.y), "\(type) y=\(kp.y) 범위 밖")
        }
        // 앉은 자세이므로 엉덩이가 무릎보다 아래(y가 큼)이거나 비슷해야 한다.
        print("META,sanity,hipY=\(result[.leftHip].y),kneeY=\(result[.leftKnee].y)")
    }
}
