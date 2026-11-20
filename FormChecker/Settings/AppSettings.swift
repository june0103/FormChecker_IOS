import Foundation
import Observation

/// 안내 항목. 완료 상태를 **Bool이 아니라 버전 값으로** 저장한다.
///
/// 🔴 안내 내용이 바뀌면 버전을 올려 **다시 보여줄 수 있어야 한다.** Bool로 두면
/// "이미 봤다"가 영원히 참이라, 바뀐 안내를 아무도 보지 못한다.
enum GuideKey: String, CaseIterable, Sendable {
    case squatExample
    case workoutCoachMarks

    /// 안내 내용을 바꾸면 이 값을 올린다.
    var currentVersion: Int {
        switch self {
        case .squatExample: 1
        case .workoutCoachMarks: 1
        }
    }

    /// 설정의 `메뉴 안내 다시 표시`가 되돌리는 대상인가.
    /// 동작 예시는 그 자리에서 바로 다시 보여주므로 여기 포함하지 않는다.
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
