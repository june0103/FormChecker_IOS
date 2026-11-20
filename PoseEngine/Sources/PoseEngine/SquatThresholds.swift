import Foundation

/// 임계값의 출처 등급.
///
/// **새 판정을 추가하기 전에 반드시 정한다.** 근거 없는 숫자를 `provisional` 표시 없이
/// 넣으면 나중에 아무도 되돌릴 수 없다.
public enum ThresholdOrigin: String, Sendable, CaseIterable {
    /// 실측 데이터에서 나온 값.
    case dataDerived
    /// 정의에서 나온 값(측정이 아니라 규칙).
    case definition
    /// 잠정값. 근거가 아직 없다.
    case provisional
}

/// 자세 판정 임계값. **이 파일의 `origins`가 정본이다.**
///
/// 임계값은 **자체 수집 데이터**(15세션 · 정면 12 / 측면 3)로 확정했다. 같은 모델·같은
/// 기기로 찍어 domain gap이 없다는 점이 결정적이었다.
///
/// > ⚠ 확정된 임계값도 **"정상을 오탐하지 않는가"만 검증됐다.** 의도적 오류 세션이 아직
/// > 없어 **"오류를 잡는가"는 미검증**이다.
public struct FormThresholds: Sendable, Equatable {

    // ── 깊이: 엉덩이 높이 기준 (기준선 있음) ──────────────────

    /// 선 자세로 보는 상한. 측면 3세션 / 3명 / 44 rep으로 확정.
    public var standingDepthRatio: Float = -0.40
    /// 패럴렐 허용폭.
    public var parallelToleranceRatio: Float = 0.03
    /// "깊음" 경계. 허용폭과 같은 값이다 — DEEP/PARALLEL은 경고를 바꾸지 않는다.
    public var deepDepthRatio: Float = 0.03
    /// **얕은 쪽 경계만 별도 필드다** — "기준 완화"가 여기만 넓힌다.
    /// `deepDepthRatio`는 그대로라서 "깊음"이 "적당"으로 내려앉지 않는다.
    public var shallowToleranceRatio: Float = 0.03

    // ── 깊이: 정강이 기준 (기준선 없을 때의 대체 경로) ─────────

    public var standingShinDepth: Float = -0.83
    public var parallelShinTolerance: Float = 0.062
    public var shallowShinTolerance: Float = 0.062

    // ── 그 외 ───────────────────────────────────────────────

    /// ⚠ **쓰지 않는다.** 실측 11명에서 정상 표본의 배수가 1.53~2.04라 임계값 1.1로는
    /// 아무것도 잡지 못한다(통과율 100%). `kneeAlignmentByToe`로 대체했다.
    public var valgusSpreadGain: Float = 1.1

    /// 상체 숙임 한계. 측면 3세션 rep 내부 1875프레임, 정상 최대 41.1° 대비 오탐 0%.
    public var torsoLeanLimitDegrees: Float = 45

    /// 뒤꿈치 들림 한계.
    ///
    /// ⚠ **이 판정이 아무것도 못 잡을 수 있다.** 0.11 → 0.18로 올렸는데(기기에서 발바닥이
    /// 바닥에 붙어 있는데 0.15까지 올라갔다), 진짜 들림의 유일한 추정치가 약 0.139라
    /// 0.18보다 아래다. 임계값 문제가 아니라 **측정이 둘을 못 가르는** 문제일 수 있다.
    public var heelRiseLimit: Float = 0.18

    /// 발 가시성 게이트 (발 길이 / 정강이). 실측 측면 3세션 중 1개가 탈락했다.
    public var minHeelFootRatio: Float = 0.45

    /// 무릎–발끝 허용폭. **0이다** — 기준점 자체가 코칭 규칙에서 나온 정의이고,
    /// 노이즈는 임계값이 아니라 `kneePastToe(of:)`의 rep 중앙값이 흡수한다.
    public var kneeOverToeLimit: Float = 0

    /// 좌우 쏠림 한계. 자체 수집 기준 데이터(정상 의도 9명 794프레임)로 확정.
    public var hipShiftLimit: Float = 0.10

    /// 무릎 내/외측 허용폭. 기준점 0은 정의, 허용폭은 사람내 MAD(11명 253 rep)에서 나왔다.
    public var kneeToeToleranceRatio: Float = 0.10

    /// 이보다 얕으면 무릎 판정을 하지 않는다. 선 자세와 최저점 분포가 갈라지는 빈 구간.
    public var kneeToeMinDepth: Float = -0.8

    /// 두 발이 겹치면 분모(발목 간격)가 무너진다.
    public var minStanceWidth: Float = 0.04

    public init() {}

    // ── 판정 ────────────────────────────────────────────────

    /// 엉덩이 높이로 깊이를 판정한다. **기준선이 있을 때 쓴다.**
    ///
    /// ## 왜 무릎 각도가 아닌가
    /// **"패럴렐"의 정의가 대퇴 수평, 즉 엉덩이가 무릎 높이다.** 무릎 각도는 같은 깊이에서도
    /// 대퇴/정강이 비율에 따라 달라지므로, 각도로 패럴렐을 정의하면 사람마다 다른 깊이를
    /// 같다고 하거나 같은 깊이를 다르다고 한다.
    ///
    /// - Parameter depthRatio: `(hip.y − knee.y) / legLength`. 힙이 무릎보다 위면 음수.
    public func depthLevel(byRatio depthRatio: Float) -> DepthLevel {
        if depthRatio <= standingDepthRatio { return .standing }
        if depthRatio >= deepDepthRatio { return .deep }
        // 얕은 쪽 경계만 별도 필드다 — "기준 완화"가 여기만 넓힌다.
        if depthRatio >= -shallowToleranceRatio { return .parallel }
        return .shallow
    }

    /// 정강이 길이로 깊이를 판정한다. **기준선이 없을 때의 대체 경로다.**
    ///
    /// ## 무릎 각도 경로를 이것으로 교체했다
    /// 이전 대체 경로는 무릎 관절각을 `160/120/100°`로 잘랐다. 측면 실측 3세션에서 그
    /// 경로는 깊이비 경로와 **45~67%만 일치**했고, 세 사람의 최저점 관절각이 전부
    /// `deepAngle`(100°) 미만이라 **세 사람 모두 DEEP으로 읽혔다** — 즉 각도 경로에서
    /// 깊이 부족 경고는 발화하지 않는다.
    ///
    /// **각도는 깊이의 대리 변수가 될 수 없다** — 정강이 기울기가 교란한다.
    ///
    /// - Parameter shinDepth: `(hip.y − knee.y) / (ankle.y − knee.y)`. 힙이 무릎보다 위면 음수.
    public func depthLevel(byShinDepth shinDepth: Float) -> DepthLevel {
        if shinDepth <= standingShinDepth { return .standing }
        if shinDepth >= parallelShinTolerance { return .deep }
        if shinDepth >= -shallowShinTolerance { return .parallel }
        return .shallow
    }

    /// rep 하나가 "무릎이 발끝을 넘었다"인가. **rep 단위 판정이다.**
    ///
    /// ## 왜 프레임이 아니라 rep인가
    /// 프레임 하나라도 `kneeOverToeLimit`을 넘으면 경고하는 방식으로는 임계값 0을 쓸 수
    /// 없다 — 실측에서 **정상 rep의 46%**가 걸렸다. 중앙값으로 보면 같은 0에서 **0%**다.
    ///
    /// ## 중앙값이다
    /// 평균이면 한 프레임의 튐이 그대로 들어온다. 최댓값은 프레임 단위와 같아진다.
    /// 중앙값은 rep의 절반 이상이 그 위였는지를 묻는다.
    ///
    /// - Returns: 판정할 값이 없으면 **nil**이다 — false가 아니다.
    ///   "안 넘었다"와 "못 봤다"는 다르고, 리포트가 못 본 항목을 말해야 한다.
    public func kneePastToe(of values: [Float]) -> Bool? {
        if values.isEmpty { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        let median = sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
        return median > kneeOverToeLimit
    }

    /// 무릎–발끝 정렬을 **프레임 단위**로 판정한다. 정면 전용.
    ///
    /// 기준점이 0이라는 것이 정의에서 나오므로 선 자세 기준선이 필요 없다.
    /// 양방향이다 — 안으로 말리는 것과 과도하게 벌리는 것을 모두 잡는다.
    ///
    /// - Parameter deviation: `(무릎 x − 발끝 x) / 발목 간격`. 양수 = 내측.
    public func kneeAlignment(byToe deviation: Float?) -> KneeAlignment? {
        guard let deviation else { return nil }
        if deviation > kneeToeToleranceRatio { return .valgus }
        if deviation < -kneeToeToleranceRatio { return .flared }
        return .good
    }

    /// 무릎폭 증가 배수로 판정하는 기존 방식. **쓰지 않는다.**
    ///
    /// 과거 데이터를 다시 계산할 때만 쓴다.
    public func kneeAlignment(standingRatio: Float?, bottomRatio: Float?) -> KneeAlignment? {
        guard let standingRatio, let bottomRatio else { return nil }
        if standingRatio < Self.minBaselineRatio { return nil }
        return bottomRatio / standingRatio < valgusSpreadGain ? .valgus : .good
    }

    // ── 기준 완화 ───────────────────────────────────────────

    /// 사용자가 "기준 완화"를 켰을 때의 `kneeToeToleranceRatio`. **0.15** (provisional).
    ///
    /// 실측 12세션 240 rep을 프로덕션 공식으로 다시 계산한 rep 경고율:
    ///
    /// | 허용폭 | 모임 | 벌어짐 | 둘 중 하나 |
    /// |---|---|---|---|
    /// | 0.10 (기본) | 28% | 34% | **62%** |
    /// | **0.15** | **15%** | **30%** | **45%** |
    /// | 0.20 | 7% | 28% | 34% |
    /// | 0.25 | **0%** | 18% | 18% |
    ///
    /// 0.25는 모임을 **하나도 못 잡아서** 더 넓히지 않았다.
    public static let relaxedKneeToeTolerance: Float = 0.15

    /// 완화 시 `shallowToleranceRatio`. **0.10은 사용자 판단**이고 실측값이 아니다.
    public static let relaxedShallowTolerance: Float = 0.10
    /// 완화 시 `shallowShinTolerance`.
    public static let relaxedShallowShinTolerance: Float = 0.208

    /// 기준 완화를 적용한 사본. **바뀌는 것은 세 값뿐이다.**
    public func relaxed() -> FormThresholds {
        var copy = self
        copy.kneeToeToleranceRatio = Self.relaxedKneeToeTolerance
        copy.shallowToleranceRatio = Self.relaxedShallowTolerance
        copy.shallowShinTolerance = Self.relaxedShallowShinTolerance
        return copy
    }

    /// 기준선이 이보다 작으면 비율이 불안정해 판정하지 않는다.
    static let minBaselineRatio: Float = 0.2

    /// 각 값의 출처. **정본이다.**
    public static let origins: [String: ThresholdOrigin] = [
        "standingDepthRatio": .dataDerived,
        "parallelToleranceRatio": .definition,
        "deepDepthRatio": .definition,
        "standingShinDepth": .dataDerived,
        "parallelShinTolerance": .definition,
        "shallowToleranceRatio": .definition,
        "shallowShinTolerance": .definition,
        "valgusSpreadGain": .provisional,
        "torsoLeanLimitDegrees": .dataDerived,
        "heelRiseLimit": .provisional,
        "minHeelFootRatio": .provisional,
        "kneeOverToeLimit": .definition,
        "hipShiftLimit": .dataDerived,
        "kneeToeToleranceRatio": .dataDerived,
        "kneeToeMinDepth": .dataDerived,
        "minStanceWidth": .provisional,
    ]
}

/// 촬영 방향 판별 임계값.
///
/// 어깨 폭을 몸통 길이로 나눈 비율을 쓴다 — 정면에서는 두 어깨가 넓게 벌어지고 측면에서는
/// 앞뒤로 겹쳐 거의 한 점이 된다.
///
/// 실측(정면 12 / 측면 3세션): 세션별 중앙값이 **정면 0.675~0.731 / 측면 0.058~0.105**로
/// 0.15와 0.55 사이가 비어 있다. 세션 단위 다수결은 15/15 전부 맞는다.
///
/// 🔴 **프레임 단위로는 쓸 수 없다** — 정면 0.5% / 측면 0.5%가 반대로 읽히고 그게 두
/// 세션에 몰려 있다.
public struct AngleDetectionThresholds: Sendable, Equatable {
    public var frontRatio: Float = 0.55
    public var sideRatio: Float = 0.30
    public var minTorsoLength: Float = 0.05

    public init() {}

    public static let origins: [String: ThresholdOrigin] = [
        "frontRatio": .dataDerived,
        "sideRatio": .dataDerived,
        "minTorsoLength": .provisional,
    ]
}

/// 준비 자세 점검 임계값.
public struct ReadyThresholds: Sendable, Equatable {
    /// 발 간격 = `발목 간격 / 어깨 너비`. 기준점이 1.0이다.
    public var stanceNarrowLimit: Float = 0.85
    public var stanceWideLimit: Float = 1.35
    public var maxStandingKneeFlexion: Float = StandingCalibration.maxStandingFlexion
    public var minFootLengthRatio: Float = 0.10

    public init() {}

    public static let origins: [String: ThresholdOrigin] = [
        "stanceNarrowLimit": .provisional,
        "stanceWideLimit": .provisional,
        "maxStandingKneeFlexion": .provisional,
        "minFootLengthRatio": .dataDerived,
    ]
}

/// rep 카운팅 임계값. **`FormThresholds`와 서로 참조하지 않는다.**
///
/// ## 왜 자세 임계값과 분리하는가
/// 초판 설계는 BOTTOM 진입을 `무릎각 < 100°`로, 깊이 부족 경고를 `BOTTOM 각도 ≥ 120°`로
/// 정의했다. **두 조건은 동시에 참이 될 수 없어** 깊이 부족 경고가 영원히 발생하지 않는다.
///
/// 분리하면 의도한 동작이 자연스럽게 나온다 — 얕은 스쿼트도 **세고, 경고한다.**
/// 세지 않으면 사용자에게는 카운터가 멈춘 것처럼 보인다.
public struct CountingThresholds: Sendable, Equatable {

    public enum Invalid: Error, CustomStringConvertible {
        case noHysteresis(enter: Float, exit: Float)
        case bottomAboveExit(bottom: Float, exit: Float)

        public var description: String {
            switch self {
            case .noHysteresis(let enter, let exit):
                "히스테리시스가 성립하지 않습니다: 선 자세 진입 \(enter)° ≤ 이탈 \(exit)°"
            case .bottomAboveExit(let bottom, let exit):
                "최저 임계값이 하강 임계값보다 큽니다: \(bottom)° ≥ \(exit)°"
            }
        }
    }

    public let standingEnterAngle: Float
    public let standingExitAngle: Float
    public let repBottomAngle: Float
    /// 상태 전이 전 유지 시간.
    public let minHoldMs: Int64
    /// 이보다 빠르면 버린다.
    public let minRepDurationMs: Int64
    public let maxRepDurationMs: Int64
    /// 포즈 소실 허용 시간.
    public let maxMissingMs: Int64

    /// 🔴 **히스테리시스가 성립해야 한다** — 진입과 이탈이 같으면 경계에서 상태가 진동한다.
    /// 최저 임계값도 하강 임계값보다 작아야 한다. 아니면 BOTTOM에 영원히 들어가지 못한다.
    public init(
        standingEnterAngle: Float = 155,
        standingExitAngle: Float = 145,
        repBottomAngle: Float = 130,
        minHoldMs: Int64 = 100,
        minRepDurationMs: Int64 = 700,
        maxRepDurationMs: Int64 = 15_000,
        maxMissingMs: Int64 = 1_000
    ) throws {
        guard standingEnterAngle > standingExitAngle else {
            throw Invalid.noHysteresis(enter: standingEnterAngle, exit: standingExitAngle)
        }
        guard repBottomAngle < standingExitAngle else {
            throw Invalid.bottomAboveExit(bottom: repBottomAngle, exit: standingExitAngle)
        }
        self.standingEnterAngle = standingEnterAngle
        self.standingExitAngle = standingExitAngle
        self.repBottomAngle = repBottomAngle
        self.minHoldMs = minHoldMs
        self.minRepDurationMs = minRepDurationMs
        self.maxRepDurationMs = maxRepDurationMs
        self.maxMissingMs = maxMissingMs
    }

    /// 기본값은 정적으로 유효하므로 던지지 않는다.
    public static let `default` = try! CountingThresholds()

    /// **전부 잠정값이다.** 설계문서의 160°/100°를 그대로 쓰지 않은 이유: 그 값들은
    /// 카운팅과 자세를 구분하지 않은 상태의 숫자다. 카운팅은 더 관대해야 한다.
    public static let origins: [String: ThresholdOrigin] = [
        "standingEnterAngle": .provisional,
        "standingExitAngle": .provisional,
        "repBottomAngle": .provisional,
        "minHoldMs": .provisional,
        "minRepDurationMs": .provisional,
        "maxRepDurationMs": .provisional,
        "maxMissingMs": .provisional,
    ]
}

/// 각도 스무딩 설정.
///
/// 🔴 **두 값 모두 시간 단위다.** 프레임 단위로 두면 분석 fps가 변할 때 스무딩 강도와
/// 창 폭이 함께 변한다. RTMPose 추론이 26~36ms로 변동해 실제 fps가 일정하지 않다.
public struct SmoothingConfig: Sendable, Equatable {
    public var emaTimeConstantMs: Double = 120.0
    public var medianWindowMs: Double = 133.0
    public init() {}
}

public struct SquatAnalyzerConfig: Sendable, Equatable {
    public var form = FormThresholds()
    public var ready = ReadyThresholds()
    public var angleDetection = AngleDetectionThresholds()
    public var smoothing = SmoothingConfig()
    public var minConfidence: Float = Pose.minConfidence
    public init() {}
}
