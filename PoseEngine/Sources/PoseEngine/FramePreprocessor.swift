import Foundation

/// 입력 프레임의 채널 배치.
///
/// 🔴 **Android와 iOS가 여기서 갈린다.** CameraX는 RGBA_8888을 주고
/// `AVCaptureVideoDataOutput`은 BGRA를 준다. 바꾸지 않으면 크래시 없이 키포인트만
/// 조용히 틀어진다.
public enum ChannelOrder: String, Sendable, CaseIterable {
    case rgba
    case bgra
    case rgb
    case argb

    var bytesPerPixel: Int { self == .rgb ? 3 : 4 }

    /// (R, G, B) 바이트 오프셋.
    var offsets: (r: Int, g: Int, b: Int) {
        switch self {
        case .rgba, .rgb: (0, 1, 2)
        case .bgra: (2, 1, 0)
        case .argb: (1, 2, 3)
        }
    }
}

/// 리샘플링 방식.
///
/// ⚠ **Android `Canvas.drawBitmap(src, null, dst, null)`이 어떤 보간을 쓰는지가
/// 키포인트 동등성을 가른다.** paint가 null이면 필터링 플래그가 꺼져 있어 최근접일
/// 가능성이 높지만, 추측이 아니라 **실측으로 정한다** — 두 방식 모두로 덤프해 Android
/// 기준값과 대조한다.
public enum ResampleMode: String, Sendable, CaseIterable {
    case nearest
    case bilinear
}

/// 프레임 → 모델 입력 텐서.
///
/// Android `RtmPoseEngine.writeLetterboxed`와 같은 일을 한다.
/// 🔴 **정규화하지 않는다.** 이 모델은 mean/std 정규화가 그래프에 포함돼 있어 0~255 raw
/// 값을 그대로 넣어야 한다. 여기서 한 번 더 나누면 키포인트가 조용히 엉뚱한 곳에 찍힌다.
enum FramePreprocessor {

    /// `destination`(targetWidth × targetHeight × 3 float)을 채운다. 패딩은 검정(0).
    static func fill(
        destination: UnsafeMutableBufferPointer<Float>,
        transform: LetterboxTransform,
        source: UnsafeRawPointer,
        sourceBytesPerRow: Int,
        channelOrder: ChannelOrder,
        mode: ResampleMode
    ) {
        let targetW = transform.targetWidth
        let targetH = transform.targetHeight
        precondition(destination.count == targetW * targetH * 3)

        // 패딩 = 검정. Android는 `inputCanvas.drawColor(Color.BLACK)`로 같은 일을 한다.
        destination.initialize(repeating: 0)

        let src = source.assumingMemoryBound(to: UInt8.self)
        let bpp = channelOrder.bytesPerPixel
        let (ro, go, bo) = channelOrder.offsets
        let srcW = transform.sourceWidth
        let srcH = transform.sourceHeight
        let scaleX = Float(srcW) / Float(transform.scaledWidth)
        let scaleY = Float(srcH) / Float(transform.scaledHeight)

        @inline(__always)
        func sample(_ x: Int, _ y: Int) -> (Float, Float, Float) {
            let o = y * sourceBytesPerRow + x * bpp
            return (Float(src[o + ro]), Float(src[o + go]), Float(src[o + bo]))
        }

        for dy in 0..<transform.scaledHeight {
            let rowBase = (dy + transform.padTop) * targetW
            // 픽셀 중심에서 샘플링한다 (Skia/vImage와 같은 규약).
            let sy = (Float(dy) + 0.5) * scaleY - 0.5

            for dx in 0..<transform.scaledWidth {
                let sx = (Float(dx) + 0.5) * scaleX - 0.5
                let r: Float, g: Float, b: Float

                switch mode {
                case .nearest:
                    let xi = min(srcW - 1, max(0, Int((sx + 0.5).rounded(.down))))
                    let yi = min(srcH - 1, max(0, Int((sy + 0.5).rounded(.down))))
                    (r, g, b) = sample(xi, yi)

                case .bilinear:
                    let x0 = min(srcW - 1, max(0, Int(sx.rounded(.down))))
                    let y0 = min(srcH - 1, max(0, Int(sy.rounded(.down))))
                    let x1 = min(srcW - 1, x0 + 1)
                    let y1 = min(srcH - 1, y0 + 1)
                    let fx = min(1, max(0, sx - Float(x0)))
                    let fy = min(1, max(0, sy - Float(y0)))

                    let (r00, g00, b00) = sample(x0, y0)
                    let (r10, g10, b10) = sample(x1, y0)
                    let (r01, g01, b01) = sample(x0, y1)
                    let (r11, g11, b11) = sample(x1, y1)

                    @inline(__always)
                    func lerp2(_ a: Float, _ b: Float, _ c: Float, _ d: Float) -> Float {
                        let top = a + (b - a) * fx
                        let bottom = c + (d - c) * fx
                        return top + (bottom - top) * fy
                    }
                    r = lerp2(r00, r10, r01, r11)
                    g = lerp2(g00, g10, g01, g11)
                    b = lerp2(b00, b10, b01, b11)
                }

                let o = (rowBase + dx + transform.padLeft) * 3
                destination[o] = r
                destination[o + 1] = g
                destination[o + 2] = b
            }
        }
    }
}
