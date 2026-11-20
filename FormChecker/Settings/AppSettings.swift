import Foundation
import Observation
import PoseEngine

/// 안내 항목. 완료 상태를 **Bool이 아니라 버전 값으로** 저장한다.
///
/// 🔴 안내 내용이 바뀌면 버전을 올려 **다시 보여줄 수 있어야 한다.** Bool로 두면
/// "이미 봤다"가 영원히 참이라, 바뀐 안내를 아무도 보지 못한다.
enum GuideKey: String, CaseIterable, Sendable {
    /// ① 설치 첫 실행 4쪽.
    case onboarding
    /// ② 첫 운동 전 측정 준비 확인.
    case measurementPrep
    /// ③ 동작 예시.
    case squatExample
    /// ④ 화면별 코치마크.
    case workoutCoachMarks

    /// 안내 내용을 바꾸면 이 값을 올린다.
    var currentVersion: Int {
        switch self {
        case .onboarding: 1
        case .measurementPrep: 1
        case .squatExample: 1
        case .workoutCoachMarks: 1
        }
    }

    /// 설정의 `메뉴 안내 다시 표시`가 되돌리는 대상인가.
    ///
    /// 동작 예시와 측정 준비는 **그 자리에서 바로 다시** 보여주므로 여기 포함하지 않고,
    /// 온보딩은 앱을 켤 때만 뜨는 자리라 `앱 사용법`이 따로 되돌린다.
    var isMenuTutorial: Bool { self == .workoutCoachMarks }
}

/// 기기에만 저장되는 설정.
///
/// 🔴 **기본값을 저장소에 두지 않는다.** 없으면 `nil`을 내고 호출부가 자기 기본값을 쓴다.
/// `0초(바로)`가 유효한 선택지라서 **"저장 안 함"과 구분돼야** 한다 —
/// `UserDefaults.integer(forKey:)`는 없을 때 0을 돌려주므로 그대로 쓰면 둘이 섞인다.
///
/// 🔴 **값은 저장 프로퍼티로 들고 `didSet`에서 기록한다.** 계산 프로퍼티로 매번
/// `UserDefaults`를 직접 읽으면 `@Observable`이 의존성을 잡지 못해, 설정을 바꿔도
/// **화면이 바뀐 값을 그리지 않는다** — 설정 화면에서 실제로 겪었다(토글은 켜지는데
/// 그 아래 설명이 그대로 남았다). 관찰 대상은 여기 있는 저장 프로퍼티들이고,
/// `UserDefaults`는 다음 실행을 위한 기록일 뿐이다.
///
/// 범위를 벗어난 값은 **저장하지 않는다.** 의학적 판단이 아니라 오타 방어다 —
/// 몸무게에 700을 넣으면 열량이 10배로 나오는데 그게 틀렸다는 것을 알 길이 없다.
@MainActor
@Observable
final class AppSettings {

    static let shared = AppSettings()

    @ObservationIgnored private let defaults: UserDefaults

    // ── 측정 준비 시간 ──────────────────────────────────────

    /// 기준 자세 재기를 누른 뒤 측정이 시작되기까지 기다리는 시간.
    /// 한 사람에게는 거의 안 바뀌는 값이라 매 세션 화면을 차지하지 않고 여기 둔다.
    var calibrationPrepSeconds: Int? {
        didSet {
            if let value = calibrationPrepSeconds, !Self.prepRange.contains(value) {
                calibrationPrepSeconds = nil
            }
            write(calibrationPrepSeconds, Self.prepKey)
        }
    }

    /// 호출부의 기본값. **저장소에는 없다.**
    static let defaultPrepSeconds = 5
    static let prepRange = 0...20

    var effectivePrepSeconds: Int { calibrationPrepSeconds ?? Self.defaultPrepSeconds }

    // ── 하루 목표 ───────────────────────────────────────────

    /// 🔴 **기본값이 없다.** 정하지 않았으면 nil이고, 앱이 임의의 숫자를 사실처럼
    /// 보여주지 않는다 — "30회 중 12회"는 사용자가 30을 정했을 때만 맞는 말이다.
    var dailyRepGoal: Int? {
        didSet {
            if let value = dailyRepGoal, !DailyGoal.valid(value) { dailyRepGoal = nil }
            write(dailyRepGoal, Self.goalKey)
        }
    }

    // ── 자세 기준 ───────────────────────────────────────────

    /// 🔴 **판정에 영향을 주는 유일한 사용자 설정이다.** 기본은 꺼짐이고, 꺼진 상태가
    /// 실측 15세션에서 나온 기준이다.
    ///
    /// 켜면 두 가지만 바뀐다 — 무릎–발끝 허용폭과 **깊이의 얕은 쪽 경계**. 깊은 쪽은
    /// 그대로다(더 깊게 앉는 것은 애초에 문제가 아니다). 상체 숙임·뒤꿈치 들림·무릎
    /// 모임은 이 설정과 무관하다.
    ///
    /// ⚠ 완화값(`relaxedKneeToeTolerance` 0.15 등)은 **PROVISIONAL**이다 — 실측이 아니라
    /// 사용자 판단에서 나온 숫자라 `FormThresholds`의 주석에 그렇게 적혀 있다.
    var relaxedForm: Bool {
        didSet { defaults.set(relaxedForm, forKey: Self.relaxedKey) }
    }

    // ── 신체 정보 ───────────────────────────────────────────

    /// 🔴 **네 값이 각각 독립적으로 없을 수 있다.** 반쯤 입력된 상태를 그대로 돌려줘야
    /// 입력칸이 이미 넣은 값을 덮어쓰지 않는다.
    var bodyInput: BodyInput {
        BodyInput(heightCm: heightCm, weightKg: weightKg, age: age, sex: sex)
    }

    var heightCm: Float? {
        didSet {
            if let value = heightCm, !BodyProfile.validHeight(value) { heightCm = nil }
            write(heightCm, Self.heightKey)
        }
    }

    var weightKg: Float? {
        didSet {
            if let value = weightKg, !BodyProfile.validWeight(value) { weightKg = nil }
            write(weightKg, Self.weightKey)
        }
    }

    var age: Int? {
        didSet {
            if let value = age, !BodyProfile.validAge(value) { age = nil }
            write(age, Self.ageKey)
        }
    }

    var sex: Sex? {
        didSet {
            if let sex { defaults.set(sex.rawValue, forKey: Self.sexKey) }
            else { defaults.removeObject(forKey: Self.sexKey) }
        }
    }

    // ── 안내 ────────────────────────────────────────────────

    /// 안내별 완료 버전. **화면은 저장소를 직접 읽지 않는다**(FR-GID-04).
    private var guideVersions: [GuideKey: Int] = [:]

    func version(of key: GuideKey) -> Int { guideVersions[key] ?? 0 }

    func hasSeen(_ key: GuideKey) -> Bool { version(of: key) >= key.currentVersion }

    func markSeen(_ key: GuideKey) {
        guideVersions[key] = key.currentVersion
        defaults.set(key.currentVersion, forKey: key.rawValue)
    }

    /// 🔴 설정의 `다시 표시`는 **여는 것이 아니라 완료 상태를 되돌린다.**
    /// 다음에 그 화면에 들어갈 때 다시 뜬다.
    func reset(_ key: GuideKey) {
        guideVersions[key] = nil
        defaults.removeObject(forKey: key.rawValue)
    }

    func resetMenuTutorials() {
        for key in GuideKey.allCases where key.isMenuTutorial { reset(key) }
    }

    // ── 저장소 ──────────────────────────────────────────────

    private static let prepKey = "calibration_prep_seconds"
    private static let goalKey = "daily_rep_goal"
    private static let relaxedKey = "relaxed_form"
    private static let heightKey = "body_height_cm"
    private static let weightKey = "body_weight_kg"
    private static let ageKey = "body_age"
    private static let sexKey = "body_sex"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 🔴 읽을 때도 범위를 확인한다 — 손상된 값으로 진행률을 그리거나 열량을
        //    10배로 내지 않는다.
        calibrationPrepSeconds = Self.readInt(defaults, Self.prepKey, Self.prepRange.contains)
        dailyRepGoal = Self.readInt(defaults, Self.goalKey, DailyGoal.valid)
        relaxedForm = defaults.bool(forKey: Self.relaxedKey)   // 없으면 false — 여기서는 맞다
        heightCm = Self.readFloat(defaults, Self.heightKey, BodyProfile.validHeight)
        weightKg = Self.readFloat(defaults, Self.weightKey, BodyProfile.validWeight)
        age = Self.readInt(defaults, Self.ageKey, BodyProfile.validAge)
        sex = defaults.string(forKey: Self.sexKey).flatMap(Sex.init(rawValue:))
        for key in GuideKey.allCases {
            let stored = defaults.integer(forKey: key.rawValue)
            if stored > 0 { guideVersions[key] = stored }
        }
    }

    private func write(_ value: Int?, _ key: String) {
        if let value { defaults.set(value, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }

    private func write(_ value: Float?, _ key: String) {
        if let value { defaults.set(value, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }

    private static func readInt(
        _ defaults: UserDefaults, _ key: String, _ valid: (Int) -> Bool
    ) -> Int? {
        guard defaults.object(forKey: key) != nil else { return nil }
        let stored = defaults.integer(forKey: key)
        return valid(stored) ? stored : nil
    }

    private static func readFloat(
        _ defaults: UserDefaults, _ key: String, _ valid: (Float) -> Bool
    ) -> Float? {
        guard defaults.object(forKey: key) != nil else { return nil }
        let stored = defaults.float(forKey: key)
        return valid(stored) ? stored : nil
    }
}
