import Foundation
import Observation
import PoseEngine
import Storage

/// 홈 화면이 그릴 것 전부. **계산은 여기까지 끝나 있고 화면은 그리기만 한다.**
///
/// 🔴 **rep 행을 홈으로 끌어오지 않는다** — DB는 주 범위만 잘라 세션별 횟수를 내고,
/// 요일 칸으로 나누는 것은 순수 함수(`weeklyReps`)가 한다. 기록이 쌓여도 홈은 같은 양을
/// 읽는다.
struct HomeState {
    var loading = true
    /// 아직 정하지 않았으면 nil. **0이나 기본값으로 채우지 않는다.**
    var dailyGoal: Int?
    var week: [DayReps] = []
    var calories: WeeklyCalories?
    /// 기록이 하나라도 있나. "아직 아무것도 안 했다"와 "이번 주만 비었다"는 다른 화면이다.
    var hasAnyRecord = false
    /// 🔴 **0으로 채우지 않는다.** 못 읽은 것과 안 한 것은 다르다.
    var loadError: String?

    /// 오늘이 몇 번째 칸인가. 아직 못 읽었으면 0(월요일).
    var todayIndex: Int { week.firstIndex(where: \.isToday) ?? 0 }
    var todayReps: Int { week.first(where: \.isToday)?.reps ?? 0 }
    var goalProgress: GoalProgress? {
        dailyGoal.map { GoalProgress(goal: $0, done: todayReps) }
    }
    var weekTotalReps: Int { week.reduce(0) { $0 + $1.reps } }
    /// 한 번이라도 센 날. **최소 시간·최소 횟수 기준을 새로 만들지 않는다.**
    var activeDays: Int { week.reduce(0) { $1.reps > 0 ? $0 + 1 : $0 } }

    /// 그 날 하루의 추정 열량. 신체 정보가 없으면 nil — **0이 아니다.**
    ///
    /// 1회당 열량이 상수라 `1회당 × 그날 횟수`가 그날 세션을 따로 더한 것과 같은 값이다.
    /// 0회인 날은 0이 나오고, 화면은 그때 숫자 대신 "기록이 없다"고 말한다.
    func calories(on index: Int) -> Float? {
        guard let calories, week.indices.contains(index) else { return nil }
        return calories.perRepKcal * Float(week[index].reps)
    }
}

@MainActor
@Observable
final class HomeViewModel {

    private(set) var state = HomeState()

    @ObservationIgnored private let repository: WorkoutRepository
    @ObservationIgnored private let settings: AppSettings
    /// 지금이 어느 주인가. **화면에 들어올 때마다 다시 잡는다** — 앱을 켜 둔 채 자정을
    /// 넘기면 "오늘"이 어제 칸에 남는다.
    @ObservationIgnored private var window: WeekWindow
    /// 이번 주 세션별 횟수 원값. 목표만 바뀌었을 때 DB를 다시 읽지 않기 위해 들고 있다.
    @ObservationIgnored private var counts: [SessionRepCount] = []

    init(repository: WorkoutRepository = WorkoutRepository(),
         settings: AppSettings = .shared) {
        self.repository = repository
        self.settings = settings
        self.window = weekWindowOf(nowMs: Self.nowMs())
    }

    func refresh() async {
        window = weekWindowOf(nowMs: Self.nowMs())
        let window = self.window
        let repository = self.repository

        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                let counts = try repository.sessionRepCounts(from: window.startMs, to: window.endMs)
                let total = try repository.sessionCount()
                return (counts, total)
            }.value

            counts = loaded.0
            state.loading = false
            state.loadError = nil
            state.hasAnyRecord = loaded.1 > 0
            rebuild()
        } catch {
            state.loading = false
            state.loadError = "기록을 불러오지 못했어요"
        }
    }

    /// 목표를 바꾼다. nil이면 정하지 않은 상태로 되돌린다.
    func setDailyGoal(_ reps: Int?) {
        settings.dailyRepGoal = reps
        rebuild()
    }

    /// 신체 정보를 바꾼 뒤 열량만 다시 센다. **저장하지 않고 볼 때마다 계산한다.**
    func bodyChanged() { rebuild() }

    private func rebuild() {
        let goal = settings.dailyRepGoal
        state.dailyGoal = goal
        state.week = weeklyReps(sessions: counts, week: window, goal: goal)
        state.calories = settings.bodyInput.profile.flatMap {
            CalorieEstimate.forWeek(repCounts: counts.map(\.repCount), profile: $0)
        }
    }

    private static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
