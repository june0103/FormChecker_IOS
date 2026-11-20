import CoreVideo
import Foundation
@testable import PoseEngine

/// 테스트용 픽셀 버퍼 만들기.
///
/// 카메라가 주는 것과 같은 모양(32BGRA · 행 패딩 가능 · IOSurface 백업)을 흉내 낸다.
enum TestPixelBuffer {

    enum Failure: Error { case createFailed(CVReturn), lockFailed, noBaseAddress }

    /// 원본(RGBA 또는 RGB)을 **BGRA 바이트**로 바꾼다.
    ///
    /// `extraRowPadding`은 행마다 덧붙일 바이트 수다. CoreVideo가 행을 정렬하면서 넣는
    /// 패딩을 재현해, `bytesPerRow == width * 4`라고 가정한 코드를 깨뜨린다.
    static func bgraBytes(
        from loaded: TestImageLoader.Loaded,
        extraRowPadding: Int = 0
    ) -> (bytes: [UInt8], bytesPerRow: Int) {
        let (ro, go, bo) = loaded.channelOrder.offsets
        let srcBpp = loaded.channelOrder.bytesPerPixel
        let dstBytesPerRow = loaded.width * 4 + extraRowPadding
        var out = [UInt8](repeating: 0xAB, count: dstBytesPerRow * loaded.height)  // 패딩은 쓰레기값으로

        loaded.bytes.withUnsafeBytes { raw in
            let src = raw.bindMemory(to: UInt8.self)
            for y in 0..<loaded.height {
                let srcRow = y * loaded.bytesPerRow
                let dstRow = y * dstBytesPerRow
                for x in 0..<loaded.width {
                    let s = srcRow + x * srcBpp
                    let d = dstRow + x * 4
                    out[d] = src[s + bo]       // B
                    out[d + 1] = src[s + go]   // G
                    out[d + 2] = src[s + ro]   // R
                    out[d + 3] = 255           // A
                }
            }
        }
        return (out, dstBytesPerRow)
    }

    /// 실제 `CVPixelBuffer`(32BGRA)를 만든다. stride는 CoreVideo가 정한다.
    static func makeBGRA(from loaded: TestImageLoader.Loaded) throws -> CVPixelBuffer {
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
        ]
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, loaded.width, loaded.height,
            kCVPixelFormatType_32BGRA, attrs as CFDictionary, &buffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer = buffer else {
            throw Failure.createFailed(status)
        }

        guard CVPixelBufferLockBaseAddress(pixelBuffer, []) == kCVReturnSuccess else {
            throw Failure.lockFailed
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw Failure.noBaseAddress
        }

        let dstBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let (packed, srcBytesPerRow) = bgraBytes(from: loaded)
        let dst = base.assumingMemoryBound(to: UInt8.self)
        packed.withUnsafeBufferPointer { src in
            for y in 0..<loaded.height {
                memcpy(dst + y * dstBytesPerRow,
                       src.baseAddress! + y * srcBytesPerRow,
                       loaded.width * 4)
            }
        }
        return pixelBuffer
    }

    /// 지원하지 않는 포맷(YUV) 버퍼. 거절되는지 확인하는 데만 쓴다.
    static func makeYUV(width: Int, height: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &buffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer = buffer else {
            throw Failure.createFailed(status)
        }
        return pixelBuffer
    }
}
