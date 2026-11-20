import Foundation
import os

/// RTMPose-s (Halpe26) 기반 `PoseEngine` 구현 — **기본 포즈 모델**.
///
/// ## 왜 이 모델인가
/// MoveNet 17개(COCO)와 Apple Vision 19개에는 **발 키포인트가 없다.** 그래서 스쿼트 판정에
/// 중요한 두 가지를 아예 관측할 수 없다 — 뒤꿈치 들림, 무릎–발끝 위치 관계.
/// Halpe26은 COCO17에 Head/Neck/Hip과 발 6개를 더한 구성이라 둘 다 가능해진다.
///
/// ## 모델 입출력 (파일을 직접 파싱해 확인)
/// ```
/// INPUT  [1, 256, 192, 3] FLOAT32   RGB 0~255 raw (정규화는 모델 내부에 포함)
/// OUTPUT [1, 26, 384]     FLOAT32   simcc_x  (192 × split_ratio 2.0)
/// OUTPUT [1, 26, 512]     FLOAT32   simcc_y  (256 × split_ratio 2.0)
/// ```
/// SimCC는 x축·y축 1D 분포를 따로 내놓으므로, 각 축의 argmax를 구해 좌표로 만든다.
public final class RTMPoseEngine: PoseEngine {

    public static let inputWidth = 192
    public static let inputHeight = 256
    public static let modelResourceName = "rtmpose_s_halpe26_256x192_f16"
    /// 실측으로 확정한 기본 리샘플링 (docs/05_Phase0_결과.md).
    public static let defaultResampleMode: ResampleMode = .nearest

    /// SimCC 분포 해상도 배율. 384/192 = 512/256 = 2.0 (파일에서 확인).
    private static let splitRatio: Float = 2.0

    private static let log = Logger(subsystem: "com.mist.formchecker.poseengine", category: "RTMPose")

    public let modelName = "RTMPose-s Halpe26"
    public let modelLoadTimeNanos: UInt64
    /// 현재는 CPU 경로만 완성돼 있다. delegate는 벤치마크 뒤에 붙인다.
    public let activeDelegate: InferenceDelegate = .cpu

    /// 리샘플링 방식. **기본값 `.nearest`는 실측으로 확정했다** (docs/05_Phase0_결과.md).
    ///
    /// Android `Canvas.drawBitmap(src, null, dst, null)`은 paint가 null이라 필터링 플래그가
    /// 꺼져 있고, 결과적으로 최근접 샘플링을 한다. 같은 이미지에서 최근접은 좌표차
    /// 0.000001, 양선형은 **0.416699**였다 — 양선형은 게이트(0.01)를 40배 넘긴다.
    /// **"더 좋은 보간"으로 바꾸면 임계값의 근거가 무효가 된다.**
    public let resampleMode: ResampleMode

    private let interpreter: TFLiteInterpreter
    private let simccXIndex: Int
    private let simccYIndex: Int
    private let simccXBins: Int
    private let simccYBins: Int

    /// 프레임마다 새로 만들지 않고 재사용한다 — 30fps로 흘리면 할당만으로 GC/메모리 압박이 된다.
    private let inputFloats: UnsafeMutableBufferPointer<Float>
    private var simccX: [Float]
    private var simccY: [Float]
    private var cachedTransform: LetterboxTransform?

    /// 번들에 들어 있는 모델 파일 경로.
    public static var bundledModelURL: URL? {
        Bundle.module.url(forResource: "Resources/\(modelResourceName)", withExtension: "tflite")
            ?? Bundle.module.url(forResource: modelResourceName, withExtension: "tflite")
    }

    /// 반드시 백그라운드 스레드에서 호출할 것.
    public init(
        modelPath: String,
        threadCount: Int32 = 4,
        resampleMode: ResampleMode = RTMPoseEngine.defaultResampleMode
    ) throws {
        let started = DispatchTime.now().uptimeNanoseconds
        let interpreter = try TFLiteInterpreter(modelPath: modelPath, threadCount: threadCount)

        // 출력 텐서 순서는 변환기에 따라 달라질 수 있어 **이름이 아니라 마지막 차원 크기로
        // 판별한다.** 입력이 세로로 길어(192×256) x축 bin(384)이 y축(512)보다 항상 작다.
        // 이 순서를 뒤바꾸면 스켈레톤이 90도 돌아간 것처럼 나온다.
        let shape0 = try interpreter.outputShape(at: 0)
        let shape1 = try interpreter.outputShape(at: 1)
        let xIndex = (shape0.last ?? 0) < (shape1.last ?? 0) ? 0 : 1

        self.interpreter = interpreter
        self.simccXIndex = xIndex
        self.simccYIndex = 1 - xIndex
        self.simccXBins = try interpreter.outputShape(at: xIndex).last ?? 0
        self.simccYBins = try interpreter.outputShape(at: 1 - xIndex).last ?? 0
        self.resampleMode = resampleMode

        let count = Self.inputWidth * Self.inputHeight * 3
        self.inputFloats = UnsafeMutableBufferPointer<Float>.allocate(capacity: count)
        self.inputFloats.initialize(repeating: 0)
        self.simccX = [Float](repeating: 0, count: KeypointType.count * simccXBins)
        self.simccY = [Float](repeating: 0, count: KeypointType.count * simccYBins)
        self.modelLoadTimeNanos = DispatchTime.now().uptimeNanoseconds - started
    }

    deinit { inputFloats.deallocate() }

    public func analyze(frame: RawFrame) -> Pose? {
        let transform = transformFor(width: frame.width, height: frame.height)
        do {
            FramePreprocessor.fill(
                destination: inputFloats,
                transform: transform,
                source: frame.baseAddress,
                sourceBytesPerRow: frame.bytesPerRow,
                channelOrder: frame.channelOrder,
                mode: resampleMode
            )

            let started = DispatchTime.now().uptimeNanoseconds
            try interpreter.copyToInput(
                inputFloats.baseAddress!,
                byteCount: inputFloats.count * MemoryLayout<Float>.size
            )
            try interpreter.invoke()
            try simccX.withUnsafeMutableBytes {
                try interpreter.copyFromOutput(at: simccXIndex, into: $0.baseAddress!, byteCount: $0.count)
            }
            try simccY.withUnsafeMutableBytes {
                try interpreter.copyFromOutput(at: simccYIndex, into: $0.baseAddress!, byteCount: $0.count)
            }
            let elapsed = DispatchTime.now().uptimeNanoseconds - started

            return Pose(keypoints: decode(transform: transform), inferenceTimeNanos: elapsed)
        } catch {
            // 한 프레임 실패로 세션이 죽지 않게 한다.
            Self.log.warning("프레임 추론 실패 — 이 프레임은 건너뜁니다: \(String(describing: error))")
            return nil
        }
    }

    private func transformFor(width: Int, height: Int) -> LetterboxTransform {
        if let cached = cachedTransform,
           cached.sourceWidth == width, cached.sourceHeight == height {
            return cached
        }
        let made = LetterboxTransform(
            sourceWidth: width, sourceHeight: height,
            targetWidth: Self.inputWidth, targetHeight: Self.inputHeight
        )
        cachedTransform = made
        return made
    }

    /// SimCC 두 분포에서 키포인트를 뽑는다.
    ///
    /// 각 축의 argmax 인덱스를 `splitRatio`로 나누면 모델 입력 픽셀 좌표가 되고, 이를 입력
    /// 크기로 나눠 정규화한 뒤 letterbox 패딩을 걷어내면 원본 프레임 기준 좌표가 된다.
    /// confidence는 두 축 최댓값 중 **작은 쪽**을 쓴다(참조 구현과 동일).
    private func decode(transform: LetterboxTransform) -> [Keypoint] {
        (0..<KeypointType.count).map { k in
            var xBin = 0, yBin = 0
            var xMax = -Float.greatestFiniteMagnitude
            var yMax = -Float.greatestFiniteMagnitude

            let xBase = k * simccXBins
            for i in 0..<simccXBins where simccX[xBase + i] > xMax {
                xMax = simccX[xBase + i]
                xBin = i
            }
            let yBase = k * simccYBins
            for i in 0..<simccYBins where simccY[yBase + i] > yMax {
                yMax = simccY[yBase + i]
                yBin = i
            }

            let (x, y) = transform.inverse(
                x: (Float(xBin) / Self.splitRatio) / Float(Self.inputWidth),
                y: (Float(yBin) / Self.splitRatio) / Float(Self.inputHeight)
            )
            return Keypoint(
                type: KeypointType(rawValue: k)!,
                x: x, y: y,
                confidence: min(xMax, yMax)
            )
        }
    }
}
