import Foundation

/// 한 세션의 성능 표본.
///
/// ## 왜 평균이 아니라 p95인가
/// 추론이 평균 10ms여도 20프레임에 한 번 60ms가 걸리면 **그 프레임에서 rep이 끊긴다.**
/// 평균은 그 사고를 보여주지 않는다. 대표값은 p95로 적는다.
///
/// ## 왜 EMA가 아니라 원표본인가
/// 화면에 띄우는 값은 EMA로 떨리지 않게 만들지만, **p95는 원표본이 없으면 낼 수 없다.**
/// 화면용 평활값과 기록용 표본은 다른 것이다.
///
/// ## 분모를 의심할 것
/// `droppedRatio`의 분모는 **시도한 프레임**(성공 + 실패)이다. 성공한 프레임만 세면
/// 많이 버릴수록 비율이 작아져서, 느릴수록 좋아 보이는 지표가 된다.
public struct PerformanceSamples: Sendable {

    private var values: [Double] = []
    /// 분석에 성공한 프레임 수.
    public private(set) var analyzed = 0
    /// 추론이 실패했거나 백프레셔로 버린 프레임 수.
    public private(set) var dropped = 0

    public init() {}

    public mutating func record(inferenceMs: Double) {
        values.append(inferenceMs)
        analyzed += 1
    }

    public mutating func recordDrop(_ count: Int = 1) {
        dropped += max(count, 0)
    }

    public mutating func reset() {
        values.removeAll(keepingCapacity: true)
        analyzed = 0
        dropped = 0
    }

    public var isEmpty: Bool { values.isEmpty }
    public var count: Int { values.count }

    public var averageMs: Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// 추론 지연 p95.
    ///
    /// 🔴 **Android와 같은 식으로 뽑는다** — 정렬 후 `(n-1) * 95 / 100`번째(정수 나눗셈).
    /// 보간하는 다른 정의를 쓰면 같은 기기에서도 두 앱의 숫자를 나란히 놓을 수 없다.
    public var p95Ms: Double? { percentile(95) }

    public func percentile(_ rank: Int) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = ((sorted.count - 1) * rank) / 100
        return sorted[index]
    }

    /// 버린 프레임 비율. 아무것도 시도하지 않았으면 nil — **0이 아니다.**
    public var droppedRatio: Double? {
        let attempted = analyzed + dropped
        guard attempted > 0 else { return nil }
        return Double(dropped) / Double(attempted)
    }
}

/// 성능 목표(`docs/01_PRD.md` §3.2). **잠정값이고, 실측 전에는 설계 전제로 쓰지 않는다.**
///
/// Android(Galaxy S24 Ultra)는 추론 p95 35.82ms로 **30fps를 못 맞춘다**는 것이 실측으로
/// 확인돼 있다. iOS 목표는 "delegate가 붙으면 빨라질 것"이라는 **가설**이고, Android에서
/// 같은 모양의 가설(GPU면 빨라진다)이 실측으로 반증된 전례가 있다.
public enum PerformanceTarget {
    /// 추론 p95 상한 (ms).
    public static let inferenceP95Ms: Double = 25
    /// 프레임 파이프라인 p95 상한 (ms). 30fps 예산은 33.3ms다.
    public static let pipelineP95Ms: Double = 33
    /// 분석 FPS 하한.
    public static let analysisFps: Double = 25

    /// 목표를 만족하는가. 표본이 없으면 **nil** — "모른다"와 "통과"는 다르다.
    public static func meetsInference(p95Ms: Double?) -> Bool? {
        p95Ms.map { $0 <= inferenceP95Ms }
    }
}
