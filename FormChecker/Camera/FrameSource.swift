import AVFoundation
import CoreVideo
import Foundation

/// 추론에 넣을 프레임을 흘려보내는 쪽.
///
/// **카메라와 영상이 같은 인터페이스를 쓰는 것은 의도된 설계다.** 시뮬레이터에는 카메라가
/// 없고, 벤치마크는 매번 같은 입력이어야 재현된다. 엔진은 둘을 구분하지 않는다.
protocol FrameSource: AnyObject, Sendable {
    var onFrame: (@Sendable (FramePacket) -> Void)? { get set }
    var label: String { get }
    func start()
    func stop()
}

/// 프레임 하나.
///
/// `timestampMs`는 **단조 증가 시계**다 — 벽시계는 시간대 변경이나 NTP 보정으로 뒤로 갈
/// 수 있어 시간 차 계산이 음수가 된다.
///
/// `@unchecked Sendable`인 이유: `CVPixelBuffer`는 Sendable로 표시돼 있지 않지만, 여기서는
/// **생산자가 넘긴 뒤 다시 건드리지 않고 소비자는 읽기만 한다.** 소유권이 한 방향으로만
/// 넘어가므로 경합이 없다.
struct FramePacket: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let timestampMs: Int64
}

enum Monotonic {
    static var nowMs: Int64 { Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000) }
}

// ─────────────────────────────────────────────────────────────

/// 카메라 프레임.
///
/// 🔴 **미러링하지 않는다.** 모델은 키포인트를 해부학적 기준(그 사람의 실제 왼쪽/오른쪽)으로
/// 라벨링하는데, 반전된 이미지를 넣으면 좌우 라벨이 뒤바뀌어 **무릎 판정이 조용히 반대로**
/// 나간다. 전면 카메라의 거울 효과는 **그릴 때만** 적용한다.
///
/// 회전은 `AVCaptureConnection.videoRotationAngle`이 처리한다 — 직접 돌리면 프레임마다
/// 버퍼를 새로 만들게 되고, Android에서 그 비용이 p95 3.21ms + GC 3회/300프레임로 측정됐다.
/// `@unchecked Sendable`: 상태는 전용 큐(`queue`)와 `AVCaptureSession`이 소유한다.
final class CameraFrameSource: NSObject, FrameSource, @unchecked Sendable,
                               AVCaptureVideoDataOutputSampleBufferDelegate {

    var onFrame: (@Sendable (FramePacket) -> Void)?
    var label: String { "카메라" }

    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.mist.formchecker.camera")
    private(set) var position: AVCaptureDevice.Position

    init(position: AVCaptureDevice.Position = .back) {
        self.position = position
        super.init()
    }

    static var isAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    func configure() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // Android가 480×640(4:3)을 요청하는 것과 같은 크기다. 3:4 프리뷰에서 letterbox 패딩이 0이 된다.
        session.sessionPreset = .vga640x480

        session.inputs.forEach { session.removeInput($0) }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video,
                                                   position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }
        session.addInput(input)

        // 🔴 BGRA다. Android는 RGBA였다 — 엔진에 넘길 때 채널 순서를 바꿔야 한다.
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                    kCVPixelFormatType_32BGRA]
        // 밀린 프레임은 버린다 (Android `STRATEGY_KEEP_ONLY_LATEST`).
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }

        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90      // 세로
            }
            // 반전은 그릴 때만 한다.
            if connection.isVideoMirroringSupported { connection.isVideoMirrored = false }
        }
        return true
    }

    func start() {
        queue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(FramePacket(pixelBuffer: buffer, timestampMs: Monotonic.nowMs))
    }
}

// ─────────────────────────────────────────────────────────────

/// 번들 영상 프레임. **시뮬레이터에는 카메라가 없다.**
///
/// 매번 같은 입력을 같은 파이프라인에 넣으므로 재현 가능한 확인·벤치마크에도 쓴다
/// (Android가 `MediaMetadataRetriever`로 하던 일).
/// `@unchecked Sendable`: 재생 루프 하나만 상태를 만진다.
final class VideoFrameSource: FrameSource, @unchecked Sendable {

    var onFrame: (@Sendable (FramePacket) -> Void)?
    var label: String { "번들 영상" }

    private let url: URL
    private var isRunning = false

    init?(resource: String = "squat_demo", ext: String = "mp4") {
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            return nil
        }
        self.url = url
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        Task.detached(priority: .userInitiated) { [weak self] in await self?.pump() }
    }

    func stop() { isRunning = false }

    private func pump() async {
        while isRunning {
            // ⚠ 사이클마다 기준 시각을 **다시 잡는다.** 한 번만 잡으면 두 번째 재생부터
            //   presentation 시간이 0으로 돌아가 목표 시각이 과거가 되고, 대기 없이
            //   프레임이 쏟아진다(실측 1,000fps 이상). 그러면 상태머신의 시간 조건이
            //   전부 무의미해지고 작업 큐가 밀린다.
            let startedMs = Monotonic.nowMs
            guard let reader = await makeReader() else { return }
            guard let track = reader.outputs.first else { return }
            reader.startReading()

            while isRunning, let sample = track.copyNextSampleBuffer() {
                guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                let presentation = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                // 영상 시간에 맞춰 흘린다 — 한 번에 쏟으면 상태머신의 시간 조건이 깨진다.
                let targetMs = startedMs + Int64(presentation * 1000)
                let waitMs = targetMs - Monotonic.nowMs
                if waitMs > 0 {
                    try? await Task.sleep(for: .milliseconds(waitMs))
                }
                onFrame?(FramePacket(pixelBuffer: buffer, timestampMs: Monotonic.nowMs))
            }
            reader.cancelReading()
            if !isRunning { return }
            // 반복 재생 — 한 사이클에 스쿼트 한 번이다.
        }
    }

    private func makeReader() async -> AVAssetReader? {
        let asset = AVURLAsset(url: url)
        guard let reader = try? AVAssetReader(asset: asset),
              let videoTrack = try? await asset.loadTracks(withMediaType: .video).first
        else { return nil }

        // 🔴 카메라와 **같은 BGRA**로 받는다 — 두 경로가 다른 픽셀을 보면 비교가 무의미해진다.
        let output = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String:
                                kCVPixelFormatType_32BGRA]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        return reader
    }
}
