import Foundation
import XCTest
@testable import Storage

/// 날짜 경계. **기기 시계로는 재현할 수 없는 조건**(자정, 주 바뀜, 서머타임)을
/// 인자로 만들어서 붙든다.
final class SessionCalendarTests: XCTestCase {

    /// 서머타임이 없는 곳. 대부분의 테스트가 여기 쓴다.
    private let seoul = SessionCalendarTests.calendar(zone: "Asia/Seoul")

    private static func calendar(zone: String) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zone)!
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }

    private static func calendar(zone: String, firstWeekday: Int) -> Calendar {
        var cal = calendar(zone: zone)
        cal.firstWeekday = firstWeekday
        return cal
    }

    private func ms(_ text: String, _ cal: Calendar? = nil) -> Int64 {
        let formatter = DateFormatter()
        formatter.calendar = cal ?? seoul
        formatter.timeZone = (cal ?? seoul).timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let date = formatter.date(from: text)!
        return Int64(date.timeIntervalSince1970 * 1000)
    }

    // ── 주 경계 ─────────────────────────────────────────────

    /// 🔴 **주는 월요일에 시작한다.** 화면이 `월 화 수 목 금 토 일`로 읽히기 때문이다.
    func testWeekStartsOnMonday() {
        // 2026-11-20은 금요일.
        let week = weekWindowOf(nowMs: ms("2026-11-20 14:30:00"), calendar: seoul)
        XCTAssertEqual(week.dayStarts.count, 7)
        XCTAssertEqual(week.startMs, ms("2026-11-16 00:00:00"))   // 월
        XCTAssertEqual(week.endMs, ms("2026-11-23 00:00:00"))     // 다음 월
        XCTAssertEqual(week.todayIndex, 4)                        // 금 = 4
    }

    /// 일요일은 **다음 주가 아니라 이번 주의 마지막 칸**이다.
    func testSundayIsTheLastSlot() {
        let week = weekWindowOf(nowMs: ms("2026-11-22 23:59:59"), calendar: seoul)
        XCTAssertEqual(week.startMs, ms("2026-11-16 00:00:00"))
        XCTAssertEqual(week.todayIndex, 6)
    }

    func testMondayMidnightIsTheFirstSlot() {
        let week = weekWindowOf(nowMs: ms("2026-11-16 00:00:00"), calendar: seoul)
        XCTAssertEqual(week.startMs, ms("2026-11-16 00:00:00"))
        XCTAssertEqual(week.todayIndex, 0)
    }

    /// 🔴 `Calendar.firstWeekday`를 **보지 않는다** — 지역 설정에 따라 일요일이 된다.
    func testIgnoresLocaleFirstWeekday() {
        let sundayFirst = Self.calendar(zone: "Asia/Seoul", firstWeekday: 1)
        let week = weekWindowOf(nowMs: ms("2026-11-22 10:00:00"), calendar: sundayFirst)
        XCTAssertEqual(week.startMs, ms("2026-11-16 00:00:00"))
        XCTAssertEqual(week.todayIndex, 6)
    }

    func testDayIndexOutsideTheWeekIsNil() {
        let week = weekWindowOf(nowMs: ms("2026-11-20 14:30:00"), calendar: seoul)
        XCTAssertNil(week.dayIndex(of: ms("2026-11-15 23:59:59")))
        XCTAssertNil(week.dayIndex(of: ms("2026-11-23 00:00:00")))
        XCTAssertEqual(week.dayIndex(of: ms("2026-11-16 00:00:00")), 0)
        XCTAssertEqual(week.dayIndex(of: ms("2026-11-22 23:59:59")), 6)
    }

    /// 🔴 **하루를 24시간으로 더하지 않는다.** 서머타임이 있는 지역에서 경계가 밀린다.
    /// 뉴욕은 2026-11-01에 시계를 되돌리므로 그 주의 일요일은 25시간이다.
    func testDaylightSavingWeekKeepsMidnightBoundaries() {
        let newYork = Self.calendar(zone: "America/New_York")
        let week = weekWindowOf(nowMs: ms("2026-11-01 12:00:00", newYork), calendar: newYork)
        XCTAssertEqual(week.startMs, ms("2026-10-26 00:00:00", newYork))
        XCTAssertEqual(week.endMs, ms("2026-11-02 00:00:00", newYork))
        XCTAssertEqual(week.todayIndex, 6)
        // 25시간짜리 날이 하나 있으므로 한 주가 7×24시간보다 길다.
        XCTAssertEqual(week.endMs - week.startMs, 7 * 86_400_000 + 3_600_000)
    }

    // ── 요일 칸 ─────────────────────────────────────────────

    /// 세션이 없는 날도 **0회 칸으로 남는다.**
    func testWeeklyRepsKeepsEmptyDays() {
        let week = weekWindowOf(nowMs: ms("2026-11-20 14:30:00"), calendar: seoul)
        let days = weeklyReps(
            sessions: [
                SessionRepCount(id: "a", startedAt: ms("2026-11-16 09:00:00"), repCount: 10),
                SessionRepCount(id: "b", startedAt: ms("2026-11-16 20:00:00"), repCount: 12),
                SessionRepCount(id: "c", startedAt: ms("2026-11-20 08:00:00"), repCount: 7),
            ],
            week: week, goal: nil
        )
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.map(\.reps), [22, 0, 0, 0, 7, 0, 0])
        XCTAssertEqual(days.filter(\.isToday).map(\.index), [4])
    }

    /// 지난 날도 **현재 목표 기준**으로 표시한다. 날짜별 목표를 저장하지 않으므로
    /// 과거의 목표를 아는 척하지 않는다.
    func testGoalAppliesToPastDaysToo() {
        let week = weekWindowOf(nowMs: ms("2026-11-20 14:30:00"), calendar: seoul)
        let days = weeklyReps(
            sessions: [
                SessionRepCount(id: "a", startedAt: ms("2026-11-16 09:00:00"), repCount: 30),
                SessionRepCount(id: "b", startedAt: ms("2026-11-17 09:00:00"), repCount: 29),
            ],
            week: week, goal: 30
        )
        XCTAssertEqual(days.map(\.metGoal), [true, false, false, false, false, false, false])
    }

    func testWithoutGoalNoDayCountsAsMet() {
        let week = weekWindowOf(nowMs: ms("2026-11-20 14:30:00"), calendar: seoul)
        let days = weeklyReps(
            sessions: [SessionRepCount(id: "a", startedAt: ms("2026-11-16 09:00:00"), repCount: 99)],
            week: week, goal: nil
        )
        XCTAssertFalse(days.contains { $0.metGoal })
    }

    /// 다른 주의 세션은 **조용히 버린다** — 범위를 DB가 잘라도 경계에서 한 건이
    /// 넘어오면 그래프가 틀린다.
    func testSessionsOutsideTheWeekAreIgnored() {
        let week = weekWindowOf(nowMs: ms("2026-11-20 14:30:00"), calendar: seoul)
        let days = weeklyReps(
            sessions: [
                SessionRepCount(id: "old", startedAt: ms("2026-11-15 22:00:00"), repCount: 50),
                SessionRepCount(id: "new", startedAt: ms("2026-11-23 01:00:00"), repCount: 50),
            ],
            week: week, goal: nil
        )
        XCTAssertEqual(days.map(\.reps), [0, 0, 0, 0, 0, 0, 0])
    }

    // ── 날짜별 묶기 ─────────────────────────────────────────

    /// 🔴 **세션 시작 시각으로 묶는다** — 자정을 넘겨 이어진 세션을 두 날로 쪼개면
    /// "그날 몇 회 했나"가 사용자의 기억과 어긋난다.
    func testGroupsByStartTimeNotEndTime() {
        let now = ms("2026-11-20 14:30:00")
        let days = groupByDay(
            sessions: [
                SessionListItem(id: "a", startedAt: ms("2026-11-19 23:50:00"),
                                endedAt: ms("2026-11-20 00:20:00"), repCount: 12)
            ],
            nowMs: now, calendar: seoul
        )
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].startMs, ms("2026-11-19 00:00:00"))
        XCTAssertEqual(days[0].relative, .yesterday)
    }

    func testRelativeDayLabels() {
        let now = ms("2026-11-20 14:30:00")
        let days = groupByDay(
            sessions: [
                SessionListItem(id: "a", startedAt: ms("2026-11-20 09:00:00"), repCount: 5),
                SessionListItem(id: "b", startedAt: ms("2026-11-19 09:00:00"), repCount: 5),
                SessionListItem(id: "c", startedAt: ms("2026-11-18 09:00:00"), repCount: 5),
            ],
            nowMs: now, calendar: seoul
        )
        XCTAssertEqual(days.map(\.relative), [.today, .yesterday, .other])
    }

    /// 하루 합계는 카드를 더해 보지 않아도 보여야 한다.
    func testDayTotalSumsItsSessions() {
        let days = groupByDay(
            sessions: [
                SessionListItem(id: "a", startedAt: ms("2026-11-20 20:00:00"), repCount: 12),
                SessionListItem(id: "b", startedAt: ms("2026-11-20 09:00:00"), repCount: 20),
            ],
            nowMs: ms("2026-11-20 22:00:00"), calendar: seoul
        )
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].totalReps, 32)
        XCTAssertEqual(days[0].sessions.map(\.id), ["a", "b"])   // 들어온 순서 그대로
    }

    func testEmptyInputGivesNoDays() {
        XCTAssertTrue(groupByDay(sessions: [], nowMs: 0, calendar: seoul).isEmpty)
    }

    /// 🔴 `epochMs % 86_400_000`로 계산하면 **시간대가 있는 곳에서 하루가 밀린다.**
    /// 서울 09:00(UTC 00:00)은 UTC 기준으로는 그날 0시와 같은 값이 나온다.
    func testDayStartUsesTheDeviceTimeZoneNotUTC() {
        let morning = ms("2026-11-20 08:00:00")
        XCTAssertEqual(dayStart(of: morning, calendar: seoul), ms("2026-11-20 00:00:00"))
        XCTAssertNotEqual(dayStart(of: morning, calendar: seoul),
                          morning - morning % 86_400_000)
    }
}
