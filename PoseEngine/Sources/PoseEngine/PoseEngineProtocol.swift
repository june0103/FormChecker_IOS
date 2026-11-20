import Foundation

/// 추론 가속기 선택.
///
/// Android에서 "GPU면 빠를 것"이라는 가설이 실측으로 반증된 전례가 있다
/// (`CompiledModel`·GPU = 컴파일 실패, CPU 성능은 두 API가 동일).
/// **iOS에서도 측정 전에는 가속기 선택을 설계 전제로 쓰지 않는다.**
public enum InferenceDelegate: String, Sendable, CaseIterable {
    case cpu
    case coreML
    case metal
}

/// 프레임 하나를 받아 포즈를 추정하는 파이프라인.
///
/// **입력이 카메라 타입이 아닌 것은 의도된 설계다.** `AVCaptureOutput`을 직접 받게 하면
/// 이 모듈이 카메라에 묶여, 녹화 영상을 같은 파이프라인에 주입해 재현 가능한 벤치마크를
/// 돌리는 구조가 불가능해진다.
///
/// 구현체는 스레드 안전하지 않다. 단일 추론 스레드에서만 호출할 것.
public protocol PoseEngine: AnyObject {
    /// 어떤 모델이 돌고 있는지. 두 모델을 비교할 때 화면·로그에 표시한다.
    var modelName: String { get }
    /// 모델 로딩에 걸린 시간(ns).
    var modelLoadTimeNanos: UInt64 { get }
    /// 실제로 사용 중인 가속기. 요청이 실패하면 CPU로 폴백되므로 요청값과 다를 수 있다.
    var activeDelegate: InferenceDelegate { get }

    /// - Returns: 추론 자체가 실패한 프레임은 `nil`. 한 프레임 실패로 세션이 죽지 않게 하기
    ///   위함이다. confidence가 낮은 경우는 실패가 아니라 낮은 confidence를 담은 정상
    ///   결과로 돌려주고, 판단은 호출부에 맡긴다.
    func analyze(frame: RawFrame) -> Pose?
}

/// 추론 입력 프레임. 소유권을 갖지 않는 뷰이므로 `analyze` 호출 동안만 유효해야 한다.
public struct RawFrame {
    public let baseAddress: UnsafeRawPointer
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let channelOrder: ChannelOrder

    public init(
        baseAddress: UnsafeRawPointer,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        channelOrder: ChannelOrder
    ) {
        self.baseAddress = baseAddress
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.channelOrder = channelOrder
    }
}
