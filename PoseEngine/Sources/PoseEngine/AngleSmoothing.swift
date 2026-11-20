import Foundation

/// 관절 각도 스무딩.
///
/// ## 왜 두 종류가 필요한가
/// 스무딩의 목적이 서로 달라서 같은 방식을 쓸 수 없다.
///
/// | 용도 | 방식 | 이유 |
/// |---|---|---|
/// | rep 상태머신 | ``AngleEma`` | 상태 전이가 노이즈로 진동하지 않아야 한다. 약간의 지연은 허용된다 |
/// | 특징 집계(최저점 탐색) | ``MedianWindow`` | **극값의 위치**를 찾아야 한다. 지연이 있으면 최저점이 뒤로 밀린다 |
///
/// EMA는 저역통과 필터라 위상 지연을 만든다. 최저점을 찾는 데 EMA를 쓰면 실제보다 늦은
/// 프레임을 최저점으로 잡고, 그 시점의 발 좌표를 수집하면 이미 올라오는 중의 자세가 섞인다.
///
/// ## 왜 좌표가 아니라 각도에 적용하는가
/// 키포인트 좌표에 걸면 26개 × 2축을 스무딩해야 하고 관절 간 상대관계가 왜곡될 수 있다.
/// 각도는 1차원이고 상태머신·판정이 실제로 소비하는 값이라 여기에 거는 것이 직접적이다.

/// 지수이동평균. rep 상태머신의 입력 안정화용.
///
/// ## 시간 기반 계수
/// `alpha`를 상수로 두면 **분석 fps가 바뀔 때 스무딩 강도가 함께 바뀐다.** RTMPose 추론이
/// 26~36ms로 변동해 실제 fps가 일정하지 않으므로, **시간상수(ms)로 정의하고 프레임 간격에
/// 맞춰 alpha를 매번 계산**한다.
///
/// `alpha = 1 - exp(-dt / timeConstant)`
public final class AngleEma {

    /// 입력 변화의 약 63%를 따라잡는 데 걸리는 시간. 작을수록 민감하다.
    private let timeConstantMs: Double
    private var value: Float?
    private var lastTimestampMs: Int64?

    public init(timeConstantMs: Double) {
        self.timeConstantMs = timeConstantMs
    }

    public var current: Float? { value }

    /// 새 각도를 반영한다.
    ///
    /// `angle`이 nil이면(저신뢰 프레임) **값을 갱신하지 않고 직전 값을 유지**한다.
    /// 0이나 nil로 갱신하면 스무딩이 무너져 상태머신이 오작동한다. 가림 한두 프레임으로
    /// rep이 끊기지 않게 하려면 이 동결이 필요하다.
    @discardableResult
    public func update(_ angle: Float?, timestampMs: Int64) -> Float? {
        guard let angle, angle.isFinite else { return value }

        let previous = value
        let previousTime = lastTimestampMs
        lastTimestampMs = timestampMs

        guard let previous, let previousTime else {
            value = angle
            return angle
        }

        let dt = Double(max(0, timestampMs - previousTime))
        // 같은 타임스탬프가 연달아 오면 계수가 0이 되어 값이 멈춘다. 그대로 두는 게 맞다.
        let alpha = timeConstantMs <= 0 ? 1.0 : 1.0 - exp(-dt / timeConstantMs)
        value = Float(Double(previous) + Double(angle - previous) * alpha)
        return value
    }

    public func reset() {
        value = nil
        lastTimestampMs = nil
    }
}

/// 이동 중앙값 창. 극값 탐색·특징 집계용.
///
/// 스파이크(키포인트가 한 프레임 튀는 현상)를 제거하면서 **위상 지연이 없다.**
///
/// ## 창 크기를 프레임이 아니라 시간으로 보는 이유
/// 분석 fps가 15~30 사이에서 변동하므로 고정 프레임 수는 실제 시간 폭이 달라진다.
/// 창 5프레임은 30fps에서 167ms, 15fps에서 333ms로 두 배 차이가 난다.
public final class MedianWindow {

    /// 홀수 권장. 짝수면 중앙 두 값의 평균이 되어 미세한 편향이 생긴다.
    public let size: Int
    private var buffer: [Float] = []

    public init(size: Int) {
        precondition(size >= 1, "창 크기는 1 이상이어야 합니다: \(size)")
        self.size = size
        buffer.reserveCapacity(size)
    }

    /// 창에 들어있는 유효 값 개수.
    public var count: Int { buffer.count }

    /// 값을 넣고 현재 중앙값을 돌려준다.
    ///
    /// `angle`이 nil이면 창에 넣지 않는다 — 저신뢰 프레임을 0으로 채우면 중앙값이
    /// 끌려 내려간다. 창이 비어 있으면 nil을 돌려준다.
    @discardableResult
    public func push(_ angle: Float?) -> Float? {
        if let angle, angle.isFinite {
            if buffer.count == size { buffer.removeFirst() }
            buffer.append(angle)
        }
        return median()
    }

    public func median() -> Float? {
        if buffer.isEmpty { return nil }
        let sorted = buffer.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    public func reset() { buffer.removeAll(keepingCapacity: true) }

    /// 목표 시간 폭에 맞는 창 크기를 계산한다. 결과는 홀수로 맞추고 1 이상을 보장한다.
    public static func sizeFor(targetSpanMs: Double, fps: Double) -> Int {
        if fps <= 0 || targetSpanMs <= 0 { return 1 }
        let frames = max(1, Int((targetSpanMs / 1000.0 * fps).rounded()))
        return frames % 2 == 0 ? frames + 1 : frames
    }
}
