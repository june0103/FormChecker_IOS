import CoreVideo
import Foundation
import os

/// 카메라 픽셀 버퍼를 엔진 입력으로 바꾼다.
///
/// ## 왜 엔진이 `AVFoundation`을 import하지 않는가
/// `CVPixelBuffer`는 CoreVideo 타입이고, 카메라가 준 것이든 `AVAssetReader`가 영상에서
/// 뽑은 것이든 여기서는 구분되지 않는다. `AVCaptureOutput`을 직접 받게 하면 이 모듈이
/// 카메라에 묶여 녹화 영상 주입 벤치마크가 불가능해진다.
///
/// ## 엔진은 회전도 미러링도 하지 않는다
/// - **회전**: 카메라 레이어가 `AVCaptureConnection.videoRotationAngle`로 처리한다.
///   여기서 직접 돌리면 프레임마다 버퍼를 새로 만들게 되고, Android에서 그 비용이
///   p95 3.21ms + 300프레임당 GC 3회로 측정됐다(`FramePipelineBenchmark`).
/// - **미러링**: 🔴 **추론 입력을 좌우 반전하면 모델의 좌/우 라벨이 뒤바뀐다.**
///   전면 카메라에서 무릎 판정이 조용히 반대로 나온다. 반전은 **그릴 때만** 한다.
public enum PixelBufferInput {

    private static let log = Logger(
        subsystem: "com.mist.formchecker.poseengine", category: "PixelBuffer"
    )

    /// 지원하는 픽셀 포맷.
    ///
    /// `AVCaptureVideoDataOutput`의 기본 선택지는 **32BGRA**다. Android가 쓰던
    /// `OUTPUT_IMAGE_FORMAT_RGBA_8888`과 **채널 순서가 반대**이므로 반드시 바꿔 읽어야 한다.
    ///
    /// YUV(`420YpCbCr*`)는 **일부러 지원하지 않는다.** 더 싸지만 색 변환이 한 겹 더 들어가고,
    /// 그 변환 계수가 Android 경로에 없던 새 변수가 된다 — 판정 동등성을 위해 카메라를
    /// BGRA로 설정한다.
    public static func channelOrder(for pixelFormat: OSType) -> ChannelOrder? {
        switch pixelFormat {
        case kCVPixelFormatType_32BGRA: .bgra
        case kCVPixelFormatType_32RGBA: .rgba
        case kCVPixelFormatType_32ARGB: .argb
        default: nil
        }
    }

    /// 버퍼를 잠그고 [body]에 [RawFrame]을 넘긴다. 잠금은 [body]가 끝날 때 풀린다.
    ///
    /// - Returns: 포맷을 지원하지 않거나 베이스 주소를 얻지 못하면 `nil`.
    public static func withRawFrame<T>(
        _ pixelBuffer: CVPixelBuffer,
        _ body: (RawFrame) -> T
    ) -> T? {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard let order = channelOrder(for: format) else {
            log.error("지원하지 않는 픽셀 포맷: \(fourCC(format), privacy: .public) — 카메라를 32BGRA로 설정하세요")
            return nil
        }
        guard !CVPixelBufferIsPlanar(pixelBuffer) else {
            log.error("평면 분리(planar) 버퍼는 지원하지 않습니다")
            return nil
        }

        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
            log.error("픽셀 버퍼를 잠그지 못했습니다")
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            log.error("베이스 주소가 없습니다")
            return nil
        }

        // ⚠ bytesPerRow는 width × 4보다 클 수 있다. CoreVideo가 행을 정렬해 패딩을 넣는다.
        //   width × 4로 가정하면 아래로 갈수록 좌표가 사선으로 밀린다.
        let frame = RawFrame(
            baseAddress: base,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            channelOrder: order
        )
        return body(frame)
    }

    /// 로그용 FourCC 문자열. (`'BGRA'` 처럼 보이게)
    static func fourCC(_ value: OSType) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF),
        ]
        let text = String(bytes: bytes, encoding: .ascii) ?? ""
        return text.allSatisfy { $0.isASCII && !$0.isNewline } ? text : String(value)
    }
}

public extension PoseEngine {
    /// 카메라(또는 영상)가 준 픽셀 버퍼로 추론한다.
    ///
    /// - Returns: 포맷 미지원·잠금 실패·추론 실패는 전부 `nil`. 한 프레임 실패로 세션이
    ///   죽지 않게 하기 위함이다.
    func analyze(pixelBuffer: CVPixelBuffer) -> Pose? {
        PixelBufferInput.withRawFrame(pixelBuffer) { frame in
            analyze(frame: frame)
        } ?? nil
    }
}
