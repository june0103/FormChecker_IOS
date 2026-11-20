import Foundation

public enum Sex: String, Sendable, CaseIterable { case male, female }

/// 추정 소모 열량. **기록된 횟수 기반**으로 낸다.
///
/// ```
/// RMR(kcal/일) = 10×체중 + 6.25×키 − 5×나이 + (남 +5 / 여 −161)   ← Mifflin-St Jeor
/// 1회당 kcal   = 5.0 METs × (RMR / 1440) / 10회
/// ```
///
/// - **키가 여기서 쓰인다** — MET 표준식은 체중만 보지만 기초대사량 식이 키를 쓴다.
/// - **깊이를 보지 않는다** — 원 논문이 반복 빈도 회귀 기울기로 정의했으므로 템포와 무관하다.
/// - 70kg·170cm·25세 남성에서 1회당 **0.570 kcal**이고, 독립 실측인
///   Nakagata et al. 2022(JSCR) 0.50±0.14의 **95% 신뢰구간 안**이다.
///   ⚠ 테스트가 그 일치를 붙들고 있으니 상수를 손대면 깨진다.
/// - **저장하지 않고 볼 때마다 계산한다.**
public enum CalorieEstimate {

    /// 2011 Compendium 코드 `02052` (공식 PDF에서 직접 확인).
    public static let squatMET: Float = 5.0
    public static let repsPerMinute: Float = 10
    public static let assumedAge = 30
    public static let assumedSex = Sex.male
    private static let minutesPerDay: Float = 1440

    public static func restingKcalPerDay(
        heightCm: Float, weightKg: Float, age: Int, sex: Sex
    ) -> Float {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Float(age)
        return base + (sex == .male ? 5 : -161)
    }

    /// 1회당 추정 kcal. 키·몸무게가 없으면 **계산하지 않는다**(nil).
    public static func perRep(
        heightCm: Float, weightKg: Float, age: Int? = nil, sex: Sex? = nil
    ) -> Float? {
        guard heightCm > 0, weightKg > 0 else { return nil }
        let rmr = restingKcalPerDay(
            heightCm: heightCm, weightKg: weightKg,
            age: age ?? assumedAge, sex: sex ?? assumedSex
        )
        guard rmr > 0 else { return nil }
        return squatMET * (rmr / minutesPerDay) / repsPerMinute
    }

    public static func forSession(
        reps: Int, heightCm: Float, weightKg: Float, age: Int? = nil, sex: Sex? = nil
    ) -> SessionCalories? {
        guard reps > 0,
              let perRep = perRep(heightCm: heightCm, weightKg: weightKg, age: age, sex: sex)
        else { return nil }
        return SessionCalories(
            kcal: perRep * Float(reps), perRepKcal: perRep, reps: reps,
            assumedAge: age == nil, assumedSex: sex == nil
        )
    }
}

public struct SessionCalories: Sendable, Equatable {
    public let kcal: Float
    public let perRepKcal: Float
    public let reps: Int
    /// 나이를 가정했는가. **가정했다는 사실을 화면이 밝혀야 한다.**
    public let assumedAge: Bool
    public let assumedSex: Bool

    public var exact: Bool { !assumedAge && !assumedSex }
}
