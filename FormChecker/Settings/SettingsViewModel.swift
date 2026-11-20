import Foundation
import Observation
import PoseEngine
import Storage

/// 설정 화면이 그리는 값.
///
/// ## 왜 `AppSettings`를 화면이 직접 읽지 않나
/// `AppSettings.shared`는 **앱이 소유한 객체**다. 화면이 `body`에서 그 객체의 값을 직접
/// 읽으면, 읽는 뷰마다 스크롤 원점에 한 번 더 그려지는 렌더 artifact를 봤다(값을 읽는
/// 뷰만, 고정 문자열은 멀쩡했다). 이 앱의 다른 화면들이 모두 쓰는 방식 —
/// **화면이 소유한 `@Observable`의 저장 프로퍼티를 읽는다** — 으로 맞춘다.
///
/// 저장소는 그대로 `AppSettings`다. 여기 있는 값은 그 거울이고, 쓰면 바로 넘긴다.
@MainActor
@Observable
final class SettingsViewModel {

    var relaxedForm: Bool { didSet { settings.relaxedForm = relaxedForm } }
    var prepSeconds: Int? { didSet { settings.calibrationPrepSeconds = prepSeconds } }

    private(set) var body: BodyInput
    private(set) var dailyGoal: Int?
    /// 마지막 세션의 성능. 없으면 nil — **0이 아니다.**
    private(set) var metrics: PerformanceMetrics?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let repository: WorkoutRepository

    init(settings: AppSettings = .shared, repository: WorkoutRepository = WorkoutRepository()) {
        self.settings = settings
        self.repository = repository
        relaxedForm = settings.relaxedForm
        prepSeconds = settings.calibrationPrepSeconds
        body = settings.bodyInput
        dailyGoal = settings.dailyRepGoal
    }

    var effectivePrepSeconds: Int { prepSeconds ?? AppSettings.defaultPrepSeconds }

    /// 시트에서 돌아왔을 때처럼 **밖에서 바뀐 값**을 다시 읽는다.
    func reload() {
        body = settings.bodyInput
        dailyGoal = settings.dailyRepGoal
        if prepSeconds != settings.calibrationPrepSeconds {
            prepSeconds = settings.calibrationPrepSeconds
        }
        if relaxedForm != settings.relaxedForm { relaxedForm = settings.relaxedForm }
    }

    func loadMetrics() async {
        let repository = self.repository
        metrics = try? await Task.detached(priority: .utility) { () -> PerformanceMetrics? in
            guard let latest = try repository.recentSessions(limit: 1).first else { return nil }
            return try repository.metrics(sessionId: latest.id)
        }.value
    }

    // ── 안내 ────────────────────────────────────────────────

    func resetOnboarding() { settings.reset(.onboarding) }
    func resetMenuTutorials() { settings.resetMenuTutorials() }
}
