import Foundation

/// 기록을 날짜로 자르는 규칙 전부.
///
/// ## 왜 화면이 아니라 여기 있나
/// 자정 경계와 주 바뀜은 **기기 시계로는 재현할 수 없는 조건**이다. 현재 시각과 달력을
/// 인자로 받는 순수 함수로 두면 테스트가 그 순간을 만들 수 있다. 앱 타겟에는 테스트
/// 타겟이 없으므로(→ `docs/03` §17) 테스트가 닿는 패키지에 둔다.
///
/// 🔴 **홈과 기록이 같은 함수를 쓴다.** 날짜 묶는 규칙이 둘이면 홈의 "오늘 32회"와
/// 기록의 "오늘 · 총 32회"가 어긋난다.

// ── 주 ──────────────────────────────────────────────────────

/// 이번 주의 날짜 경계. **월요일 0시부터 다음 월요일 0시까지.**
///
/// - `dayStarts` 7개. `[0]`이 월요일 0시, `[6]`이 일요일 0시.
/// - `todayIndex` 오늘이 몇 번째 칸인가. 월요일이면 0, 일요일이면 6.
public struct WeekWindow: Sendable, Equatable {
    public let dayStarts: [Int64]
    public let endMs: Int64
    public let todayIndex: Int

    public var startMs: Int64 { dayStarts[0] }

    /// 이 시각이 몇 번째 칸인가. 이번 주가 아니면 nil.
    public func dayIndex(of timeMs: Int64) -> Int? {
        guard timeMs >= startMs, timeMs < endMs else { return nil }
        // 7칸뿐이라 뒤에서부터 훑는 것이 이분 탐색보다 읽기 쉽다.
        return dayStarts.lastIndex { timeMs >= $0 }
    }
}

public let daysInWeek = 7

/// `nowMs`가 속한 주의 경계를 만든다.
///
/// 일요일이 아니라 **월요일이 첫 칸**이다 — 화면이 `월 화 수 목 금 토 일`로 읽히기
/// 때문이다. `Calendar.firstWeekday`는 지역 설정에 따라 일요일이 되므로 쓰지 않는다.
public func weekWindowOf(nowMs: Int64, calendar: Calendar = .autoupdatingCurrent) -> WeekWindow {
    let cal = calendar
    let today = cal.startOfDay(for: Date(timeIntervalSince1970: Double(nowMs) / 1000))
    // Calendar.component(.weekday)는 일=1 … 토=7이다. 월=0 … 일=6으로 옮긴다.
    let todayIndex = (cal.component(.weekday, from: today) + 5) % 7
    let monday = cal.date(byAdding: .day, value: -todayIndex, to: today) ?? today

    var starts: [Int64] = []
    starts.reserveCapacity(daysInWeek)
    var cursor = monday
    for _ in 0..<daysInWeek {
        starts.append(ms(cursor))
        // 하루를 24시간으로 더하지 않는다 — 서머타임이 있는 지역에서 경계가 밀린다.
        cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? cursor
    }
    return WeekWindow(dayStarts: starts, endMs: ms(cursor), todayIndex: todayIndex)
}

/// 그래프 한 칸.
public struct DayReps: Sendable, Equatable, Identifiable {
    /// 월요일이 0.
    public let index: Int
    public let reps: Int
    public let isToday: Bool
    /// 이 날 목표를 채웠나. 목표를 정하지 않았으면 항상 false.
    public let metGoal: Bool

    public var id: Int { index }
}

/// 세션들을 요일 칸으로 나눈다. 세션이 없는 날도 **0회 칸으로 남는다** — 빈 칸이 빠지면
/// 그래프가 며칠짜리인지 알 수 없다.
///
/// - Parameter goal: 오늘의 목표. 지난 날들도 **같은 목표**로 달성 여부를 표시한다 —
///   날짜별 목표를 저장하지 않으므로 과거의 목표를 아는 척하지 않고, 화면이 "오늘 목표
///   기준"임을 밝힌다.
public func weeklyReps(sessions: [SessionRepCount], week: WeekWindow, goal: Int?) -> [DayReps] {
    var totals = [Int](repeating: 0, count: daysInWeek)
    for session in sessions {
        guard let index = week.dayIndex(of: session.startedAt) else { continue }
        totals[index] += session.repCount
    }
    return totals.enumerated().map { index, reps in
        DayReps(index: index, reps: reps,
                isToday: index == week.todayIndex,
                metGoal: goal.map { reps >= $0 } ?? false)
    }
}

// ── 날짜별 묶기 ─────────────────────────────────────────────

/// 오늘·어제인가. 화면이 날짜 옆에 붙일 말을 고르는 데 쓴다.
///
/// "3일 전" 같은 상대 표기를 더 만들지 않는다 — 그 이상은 사람이 날짜로 기억하고,
/// 상대 표기가 길어질수록 오히려 언제인지 세어봐야 한다.
public enum RelativeDay: Sendable {
    case today, yesterday, other
}

/// 같은 날에 한 기록을 묶은 것.
///
/// - `startMs` 그날 0시(기기 시간대). **목록 키로도 쓴다** — 세션 id와 달리 날짜 헤더는
///   자기 id가 없다.
/// - `totalReps` 그날 합계. 카드를 더해 보지 않아도 그날 얼마나 했는지 보이게 한다.
/// - `sessions` 최근이 앞. 들어온 순서를 그대로 지킨다.
public struct HistoryDay: Sendable, Identifiable {
    public let startMs: Int64
    public let totalReps: Int
    public let relative: RelativeDay
    public let sessions: [SessionListItem]

    public var id: Int64 { startMs }
}

/// 세션 목록을 날짜별로 묶는다.
///
/// ## 어느 시각으로 묶나
/// **세션 시작 시각**이다. 자정을 넘겨 이어진 세션을 두 날로 쪼개면 "그날 몇 회 했나"가
/// 사용자가 기억하는 것과 어긋난다 (홈 집계와 같은 규칙).
///
/// ## 순서를 다시 정하지 않는다
/// 들어온 순서(저장소가 `started_at DESC`로 낸다)를 그대로 유지한다. 여기서 다시
/// 정렬하면 정렬 규칙이 두 곳에 생긴다.
public func groupByDay(
    sessions: [SessionListItem],
    nowMs: Int64,
    calendar: Calendar = .autoupdatingCurrent
) -> [HistoryDay] {
    guard !sessions.isEmpty else { return [] }

    let today = dayStart(of: nowMs, calendar: calendar)
    let yesterday = dayStart(of: today - 1, calendar: calendar)

    var order: [Int64] = []
    var grouped: [Int64: [SessionListItem]] = [:]
    for session in sessions {
        let key = dayStart(of: session.startedAt, calendar: calendar)
        if grouped[key] == nil { order.append(key) }
        grouped[key, default: []].append(session)
    }

    return order.map { key in
        let items = grouped[key] ?? []
        return HistoryDay(
            startMs: key,
            totalReps: items.reduce(0) { $0 + $1.repCount },
            relative: key == today ? .today : (key == yesterday ? .yesterday : .other),
            sessions: items
        )
    }
}

/// 그 시각이 속한 날의 0시.
///
/// `epochMs - epochMs % 86_400_000`로 계산하지 않는다 — 그건 UTC 기준이라 시간대가 있는
/// 곳에서 하루가 밀리고, 서머타임이 있는 지역에서는 24시간이 아닌 날에 어긋난다.
public func dayStart(of epochMs: Int64, calendar: Calendar = .autoupdatingCurrent) -> Int64 {
    ms(calendar.startOfDay(for: Date(timeIntervalSince1970: Double(epochMs) / 1000)))
}

private func ms(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1000).rounded())
}

private extension Array {
    func lastIndex(where predicate: (Element) -> Bool) -> Int? {
        for index in stride(from: count - 1, through: 0, by: -1) where predicate(self[index]) {
            return index
        }
        return nil
    }
}
