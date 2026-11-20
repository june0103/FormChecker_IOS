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
@MainActor
@Observable
final class AppSettings {

    static let shared = AppSettings()

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // ── 측정 준비 시간 ──────────────────────────────────────

    private static let prepKey = "calibration_prep_seconds"

    /// 기준 자세 재기를 누른 뒤 측정이 시작되기까지 기다리는 시간.
    /// 한 사람에게는 거의 안 바뀌는 값이라 매 세션 화면을 차지하지 않고 여기 둔다.
    var calibrationPrepSeconds: Int? {
        get {
            guard defaults.object(forKey: Self.prepKey) != nil else { return nil }
            return defaults.integer(forKey: Self.prepKey)
        }
        set {
            if let newValue { defaults.set(newValue, forKey: Self.prepKey) }
            else { defaults.removeObject(forKey: Self.prepKey) }
        }
    }

    /// 호출부의 기본값. **저장소에는 없다.**
    static let defaultPrepSeconds = 5
    static let prepRange = 0...20

    var effectivePrepSeconds: Int { calibrationPrepSeconds ?? Self.defaultPrepSeconds }

    // ── 하루 목표 ───────────────────────────────────────────

    private static let goalKey = "daily_rep_goal"

    /// 🔴 **기본값이 없다.** 정하지 않았으면 nil이고, 앱이 임의의 숫자를 사실처럼
    /// 보여주지 않는다 — "30회 중 12회"는 사용자가 30을 정했을 때만 맞는 말이다.
    var dailyRepGoal: Int? {
        get {
            guard defaults.object(forKey: Self.goalKey) != nil else { return nil }
            let stored = defaults.integer(forKey: Self.goalKey)
            // 범위 밖은 없는 것으로 친다 — 손상된 값으로 진행률을 그리지 않는다.
            return DailyGoal.valid(stored) ? stored : nil
        }
        set {
            if let newValue, DailyGoal.valid(newValue) {
                defaults.set(newValue, forKey: Self.goalKey)
            } else {
                defaults.removeObject(forKey: Self.goalKey)
            }
        }
    }

    // ── 신체 정보 ───────────────────────────────────────────

    private static let heightKey = "body_height_cm"
    private static let weightKey = "body_weight_kg"
    private static let ageKey = "body_age"
    private static let sexKey = "body_sex"

    /// 🔴 **네 값이 각각 독립적으로 없을 수 있다.** 반쯤 입력된 상태를 그대로 돌려줘야
    /// 입력칸이 이미 넣은 값을 덮어쓰지 않는다.
    var bodyInput: BodyInput {
        BodyInput(heightCm: heightCm, weightKg: weightKg, age: age, sex: sex)
    }

    var heightCm: Float? {
        get { float(Self.heightKey, valid: BodyProfile.validHeight) }
        set { setFloat(newValue, Self.heightKey, valid: BodyProfile.validHeight) }
    }

    var weightKg: Float? {
        get { float(Self.weightKey, valid: BodyProfile.validWeight) }
        set { setFloat(newValue, Self.weightKey, valid: BodyProfile.validWeight) }
    }

    var age: Int? {
        get {
            guard defaults.object(forKey: Self.ageKey) != nil else { return nil }
            let stored = defaults.integer(forKey: Self.ageKey)
            return BodyProfile.validAge(stored) ? stored : nil
        }
        set {
            if let newValue, BodyProfile.validAge(newValue) {
                defaults.set(newValue, forKey: Self.ageKey)
            } else {
                defaults.removeObject(forKey: Self.ageKey)
            }
        }
    }

    var sex: Sex? {
        get { defaults.string(forKey: Self.sexKey).flatMap(Sex.init(rawValue:)) }
        set {
            if let newValue { defaults.set(newValue.rawValue, forKey: Self.sexKey) }
            else { defaults.removeObject(forKey: Self.sexKey) }
        }
    }

    /// 범위를 벗어난 값은 **저장하지 않는다.** 의학적 판단이 아니라 오타 방어다 —
    /// 몸무게에 700을 넣으면 열량이 10배로 나오는데 그게 틀렸다는 것을 알 길이 없다.
    private func float(_ key: String, valid: (Float) -> Bool) -> Float? {
        guard defaults.object(forKey: key) != nil else { return nil }
        let stored = defaults.float(forKey: key)
        return valid(stored) ? stored : nil
    }

    private func setFloat(_ value: Float?, _ key: String, valid: (Float) -> Bool) {
        if let value, valid(value) { defaults.set(value, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }

    // ── 안내 ────────────────────────────────────────────────

    func version(of key: GuideKey) -> Int {
        defaults.integer(forKey: key.rawValue)   // 없으면 0 — 여기서는 0이 "안 봤다"라 맞다
    }

    func hasSeen(_ key: GuideKey) -> Bool {
        version(of: key) >= key.currentVersion
    }

    func markSeen(_ key: GuideKey) {
        defaults.set(key.currentVersion, forKey: key.rawValue)
    }

    /// 🔴 설정의 `다시 표시`는 **여는 것이 아니라 완료 상태를 되돌린다.**
    /// 다음에 그 화면에 들어갈 때 다시 뜬다.
    func reset(_ key: GuideKey) {
        defaults.removeObject(forKey: key.rawValue)
    }

    func resetMenuTutorials() {
        for key in GuideKey.allCases where key.isMenuTutorial { reset(key) }
    }
}
