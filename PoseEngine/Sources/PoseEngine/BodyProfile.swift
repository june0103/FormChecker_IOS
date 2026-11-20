import Foundation

/// 저장된 신체 정보 원값. **네 값이 각각 독립적으로 없을 수 있다.**
///
/// `BodyProfile`과 나눈 이유: 이쪽은 "무엇이 저장돼 있나"이고 저쪽은 "계산할 수 있나"다.
/// 화면이 입력칸을 되채우려면 **반쯤 입력된 상태를 그대로 볼 수 있어야 한다** — 키만
/// 넣어 둔 사람의 화면에서 키 칸이 비어 있으면, 다시 넣다가 이미 넣은 값을 덮어쓴다.
public struct BodyInput: Sendable, Equatable {
    public var heightCm: Float?
    public var weightKg: Float?
    public var age: Int?
    public var sex: Sex?

    public init(heightCm: Float? = nil, weightKg: Float? = nil,
                age: Int? = nil, sex: Sex? = nil) {
        self.heightCm = heightCm; self.weightKg = weightKg
        self.age = age; self.sex = sex
    }

    /// 열량을 계산할 수 있으면 프로필, 아니면 nil. **키·몸무게가 둘 다 있어야 한다.**
    public var profile: BodyProfile? {
        guard let heightCm, let weightKg else { return nil }
        return BodyProfile(heightCm: heightCm, weightKg: weightKg, age: age, sex: sex)
    }
}

/// 칼로리 추정에 쓰는 신체 정보.
///
/// ## 범위를 두는 이유
/// 의학적 판단이 아니라 **오타 방어**다. 몸무게에 700을 넣으면 열량이 10배로 나오는데
/// 그게 틀렸다는 것을 사용자가 알 방법이 없다. 사람이 실제로 가질 수 있는 범위를 넘으면
/// 저장하지 않는다.
public struct BodyProfile: Sendable, Equatable {
    public let heightCm: Float
    public let weightKg: Float
    /// 선택. 없으면 열량 추정이 기본값을 쓰고 **그 사실을 화면에 밝힌다.**
    public let age: Int?
    /// 선택. 없으면 위와 같다.
    public let sex: Sex?

    public init(heightCm: Float, weightKg: Float, age: Int? = nil, sex: Sex? = nil) {
        self.heightCm = heightCm; self.weightKg = weightKg
        self.age = age; self.sex = sex
    }

    public static let heightRangeCm: ClosedRange<Float> = 100...250
    public static let weightRangeKg: ClosedRange<Float> = 20...300
    /// 나이 상한을 두는 이유도 오타 방어다 — Mifflin-St Jeor 식은 19~78세에서 도출됐다.
    public static let ageRange: ClosedRange<Int> = 10...100

    public static func validHeight(_ value: Float) -> Bool { heightRangeCm.contains(value) }
    public static func validWeight(_ value: Float) -> Bool { weightRangeKg.contains(value) }
    public static func validAge(_ value: Int) -> Bool { ageRange.contains(value) }
}

/// 하루 목표.
///
/// 🔴 **기본값이 없다.** 정하지 않았으면 nil이고, 앱이 임의의 숫자를 사실처럼 보여주지
/// 않는다 — "오늘 30회 중 12회"는 사용자가 30을 정했을 때만 맞는 말이다.
public enum DailyGoal {
    public static let range: ClosedRange<Int> = 1...500
    /// 증감 버튼의 폭. 1회씩 올리면 30회를 맞추는 데 30번을 눌러야 한다.
    public static let step = 5

    public static func valid(_ value: Int) -> Bool { range.contains(value) }
    public static func clamped(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

/// 오늘의 목표 진행 상황.
///
/// **초과분을 숨기지 않는다** — 막대와 진행 바는 100%에서 멈춰도(`displayRatio`) 숫자는
/// 실제 횟수를 그대로 보여준다. 목표를 넘긴 것은 감출 일이 아니다.
public struct GoalProgress: Sendable, Equatable {
    public let goal: Int
    public let done: Int

    public init(goal: Int, done: Int) {
        self.goal = goal; self.done = done
    }

    public var ratio: Float { goal <= 0 ? 0 : Float(done) / Float(goal) }
    /// 진행 바에 그릴 값. 채움은 100%에서 멈춘다.
    public var displayRatio: Float { min(max(ratio, 0), 1) }
    public var percent: Int { Int((ratio * 100).rounded()) }
    public var remaining: Int { max(goal - done, 0) }
    public var reached: Bool { done >= goal }
    /// 목표를 넘긴 횟수. 달성 전에는 0.
    public var over: Int { max(done - goal, 0) }
}
