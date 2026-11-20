import CoreGraphics
import Foundation
import ImageIO
@testable import PoseEngine

/// 테스트용 PNG 로더.
///
/// 🔴 **CoreGraphics 컨텍스트에 다시 그리지 않는다.** 다시 그리면 색 공간 변환이 끼어들어
/// 픽셀 값이 조용히 달라지고, 그러면 "전처리가 Android와 같은가"를 재는 테스트가
/// 무엇을 재는지 알 수 없게 된다. 디코딩된 원본 바이트를 그대로 쓴다.
enum TestImageLoader {

    struct Loaded {
        let bytes: Data
        let width: Int
        let height: Int
        let bytesPerRow: Int
        let channelOrder: ChannelOrder
        /// 원본 바이트를 그대로 썼는가. false면 다시 그린 것이라 비교 결과를 믿을 수 없다.
        let usedRawBytes: Bool
        let describedFormat: String
    }

    enum Failure: Error { case notFound(String), decodeFailed(String), unsupportedFormat(String) }

    static func url(_ name: String) throws -> URL {
        guard let base = Bundle.module.resourceURL else { throw Failure.notFound(name) }
        let candidate = base.appendingPathComponent("images/\(name).png")
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            throw Failure.notFound(candidate.path)
        }
        return candidate
    }

    static func load(_ name: String) throws -> Loaded {
        let fileURL = try url(name)
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Failure.decodeFailed(name)
        }

        let bpc = image.bitsPerComponent
        let bpp = image.bitsPerPixel
        let alpha = image.alphaInfo
        let byteOrder = image.bitmapInfo.intersection(.byteOrderMask)
        let format = "bpc=\(bpc) bpp=\(bpp) alpha=\(alpha.rawValue) byteOrder=\(byteOrder.rawValue)"

        if bpc == 8, let provider = image.dataProvider, let data = provider.data as Data? {
            let order: ChannelOrder?
            switch (bpp, alpha, byteOrder) {
            case (24, .none, _):
                order = .rgb
            case (32, .premultipliedLast, .byteOrderDefault), (32, .last, .byteOrderDefault),
                 (32, .noneSkipLast, .byteOrderDefault):
                order = .rgba
            case (32, .premultipliedFirst, .byteOrderDefault), (32, .first, .byteOrderDefault),
                 (32, .noneSkipFirst, .byteOrderDefault):
                order = .argb
            case (32, .premultipliedFirst, .byteOrder32Little), (32, .noneSkipFirst, .byteOrder32Little):
                order = .bgra
            default:
                order = nil
            }
            if let order {
                return Loaded(
                    bytes: data,
                    width: image.width,
                    height: image.height,
                    bytesPerRow: image.bytesPerRow,
                    channelOrder: order,
                    usedRawBytes: true,
                    describedFormat: format
                )
            }
        }
        throw Failure.unsupportedFormat("\(name): \(format)")
    }
}
