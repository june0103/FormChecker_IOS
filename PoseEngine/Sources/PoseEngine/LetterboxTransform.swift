import Foundation

/// 직사각형 프레임을 모델 입력 크기로 넣기 위한 비율 유지 변환.
///
/// ## 왜 단순 리사이즈가 아니라 letterbox인가
/// 비율을 무시하고 눌러 넣으면 **관절 각도가 실제와 다르게 계산된다.** 크래시가 없어
/// 조용히 틀리고, 기기 카메라 종횡비가 다르면 같은 스쿼트가 기기마다 다른 각도로 측정된다.
///
/// ## 대상이 정사각형일 필요는 없다
/// RTMPose 입력은 192×256(W×H)이다. 프리뷰가 3:4라 **실제 패딩은 0**이지만, 기기마다
/// 실제 해상도가 다를 수 있으므로 변환은 유지한다.
public struct LetterboxTransform: Sendable, Equatable {
    public let sourceWidth: Int
    public let sourceHeight: Int
    public let targetWidth: Int
    public let targetHeight: Int

    /// 원본을 target 안에 온전히 넣기 위한 축소 배율.
    public let scale: Float
    /// 축소된 이미지가 실제로 차지하는 영역(px). 나머지는 패딩이다.
    public let scaledWidth: Int
    public let scaledHeight: Int
    /// 좌우·상하 패딩(px). 이미지를 가운데 두므로 남는 공간을 절반씩 나눈다.
    public let padLeft: Int
    public let padTop: Int

    public init(sourceWidth: Int, sourceHeight: Int, targetWidth: Int, targetHeight: Int) {
        precondition(sourceWidth > 0 && sourceHeight > 0,
                     "프레임 크기가 유효하지 않습니다: \(sourceWidth)x\(sourceHeight)")
        precondition(targetWidth > 0 && targetHeight > 0,
                     "모델 입력 크기가 유효하지 않습니다: \(targetWidth)x\(targetHeight)")

        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.targetWidth = targetWidth
        self.targetHeight = targetHeight

        let s = min(Float(targetWidth) / Float(sourceWidth),
                    Float(targetHeight) / Float(sourceHeight))
        self.scale = s
        // Kotlin `roundToInt()`와 같은 결과를 내려면 양수에서 반올림 규칙이 같아야 한다.
        // `.rounded()`(away-from-zero)는 양수에서 half-up과 같다.
        self.scaledWidth = min(Int((Float(sourceWidth) * s).rounded()), targetWidth)
        self.scaledHeight = min(Int((Float(sourceHeight) * s).rounded()), targetHeight)
        self.padLeft = (targetWidth - scaledWidth) / 2
        self.padTop = (targetHeight - scaledHeight) / 2
    }

    /// 정사각형 입력 모델용 편의 생성자.
    public init(sourceWidth: Int, sourceHeight: Int, targetSize: Int) {
        self.init(sourceWidth: sourceWidth, sourceHeight: sourceHeight,
                  targetWidth: targetSize, targetHeight: targetSize)
    }

    /// 원본 프레임의 정규화 좌표(0~1)를 letterbox 기준 정규화 좌표로.
    public func forward(x: Float, y: Float) -> (x: Float, y: Float) {
        ((Float(padLeft) + x * Float(scaledWidth)) / Float(targetWidth),
         (Float(padTop) + y * Float(scaledHeight)) / Float(targetHeight))
    }

    /// 모델이 돌려준 letterbox 기준 정규화 좌표를 **원본 프레임 기준 정규화 좌표**로 되돌린다.
    ///
    /// 이 변환을 빠뜨리면 스켈레톤이 패딩 폭만큼 치우쳐 그려지고 각도 계산도 함께 틀어진다.
    /// 패딩 영역에 찍힌 좌표는 0~1 밖으로 나갈 수 있으므로 clamp 여부는 호출부가 정한다.
    public func inverse(x: Float, y: Float) -> (x: Float, y: Float) {
        ((x * Float(targetWidth) - Float(padLeft)) / Float(scaledWidth),
         (y * Float(targetHeight) - Float(padTop)) / Float(scaledHeight))
    }
}
