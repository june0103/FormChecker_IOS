import XCTest
@testable import PoseEngine

/// 목표·신체 정보. **"없음"이 0으로 바뀌지 않는지**를 붙든다.
final class BodyProfileTests: XCTestCase {

    // ── 신체 정보 ───────────────────────────────────────────

    /// 🔴 **키·몸무게가 둘 다 있어야 계산할 수 있다.** 하나만으로 추정하면
    /// Mifflin-St Jeor 식의 항이 빠진 값이 나오는데, 그게 틀렸다는 표시가 없다.
    func testProfileNeedsBothHeightAndWeight() {
        XCTAssertNil(BodyInput(heightCm: 170).profile)
        XCTAssertNil(BodyInput(weightKg: 70).profile)
        XCTAssertNotNil(BodyInput(heightCm: 170, weightKg: 70).profile)
    }

    /// 반쯤 입력된 상태가 **그대로 보존된다** — 입력칸이 이미 넣은 값을 덮어쓰지 않도록.
    func testHalfFilledInputKeepsWhatWasEntered() {
        let input = BodyInput(heightCm: 170, age: 25)
        XCTAssertNil(input.profile)
        XCTAssertEqual(input.heightCm, 170)
        XCTAssertEqual(input.age, 25)
    }

    /// 범위는 의학적 판단이 아니라 **오타 방어**다.
    func testRangesRejectTypos() {
        XCTAssertFalse(BodyProfile.validWeight(700))
        XCTAssertFalse(BodyProfile.validHeight(17))
        XCTAssertFalse(BodyProfile.validAge(300))
        XCTAssertTrue(BodyProfile.validWeight(70))
        XCTAssertTrue(BodyProfile.validHeight(170))
        XCTAssertTrue(BodyProfile.validAge(30))
    }

    /// 나이·성별은 **선택**이고, 없으면 가정했다는 사실이 결과에 남는다.
    func testAssumptionsAreReported() throws {
        let profile = BodyProfile(heightCm: 170, weightKg: 70)
        let week = try XCTUnwrap(CalorieEstimate.forWeek(repCounts: [10], profile: profile))
        XCTAssertTrue(week.assumedAge)
        XCTAssertTrue(week.assumedSex)
        XCTAssertFalse(week.exact)

        let full = BodyProfile(heightCm: 170, weightKg: 70, age: 25, sex: .male)
        let exact = try XCTUnwrap(CalorieEstimate.forWeek(repCounts: [10], profile: full))
        XCTAssertTrue(exact.exact)
    }

    /// 세션마다 계산해 더한 값이 1회당 × 총횟수와 같다 — 1회당이 상수이기 때문이다.
    /// 홈이 "그날 하루치"를 `1회당 × 그날 횟수`로 내도 되는 근거다.
    func testWeeklySumMatchesPerRepTimesTotal() throws {
        let profile = BodyProfile(heightCm: 170, weightKg: 70, age: 25, sex: .male)
        let week = try XCTUnwrap(CalorieEstimate.forWeek(repCounts: [12, 20, 8], profile: profile))
        XCTAssertEqual(week.kcal, week.perRepKcal * 40, accuracy: 1e-3)
    }

    /// 0회인 날이 섞여도 합계가 어긋나지 않는다.
    func testZeroRepDaysContributeNothing() throws {
        let profile = BodyProfile(heightCm: 170, weightKg: 70)
        let withZeros = try XCTUnwrap(
            CalorieEstimate.forWeek(repCounts: [0, 10, 0], profile: profile))
        let without = try XCTUnwrap(CalorieEstimate.forWeek(repCounts: [10], profile: profile))
        XCTAssertEqual(withZeros.kcal, without.kcal, accuracy: 1e-4)
    }

    // ── 목표 ────────────────────────────────────────────────

    /// 🔴 **초과분을 숨기지 않는다.** 진행 바는 100%에서 멈춰도 숫자는 실제를 말한다.
    func testOverGoalIsShownNotClamped() {
        let progress = GoalProgress(goal: 30, done: 35)
        XCTAssertTrue(progress.reached)
        XCTAssertEqual(progress.over, 5)
        XCTAssertEqual(progress.remaining, 0)
        XCTAssertEqual(progress.percent, 117)
        XCTAssertEqual(progress.displayRatio, 1, accuracy: 1e-6)   // 바만 멈춘다
        XCTAssertEqual(progress.ratio, 35.0 / 30.0, accuracy: 1e-6)
    }

    func testBelowGoalCountsDown() {
        let progress = GoalProgress(goal: 30, done: 12)
        XCTAssertFalse(progress.reached)
        XCTAssertEqual(progress.remaining, 18)
        XCTAssertEqual(progress.over, 0)
        XCTAssertEqual(progress.percent, 40)
    }

    /// 0으로 나누지 않는다.
    func testZeroGoalDoesNotDivideByZero() {
        let progress = GoalProgress(goal: 0, done: 5)
        XCTAssertEqual(progress.ratio, 0)
        XCTAssertEqual(progress.displayRatio, 0)
    }

    func testGoalRangeAndStep() {
        XCTAssertFalse(DailyGoal.valid(0))
        XCTAssertFalse(DailyGoal.valid(501))
        XCTAssertTrue(DailyGoal.valid(1))
        XCTAssertTrue(DailyGoal.valid(500))
        XCTAssertEqual(DailyGoal.clamped(-5), 1)
        XCTAssertEqual(DailyGoal.clamped(900), 500)
        XCTAssertEqual(DailyGoal.step, 5)
    }
}
