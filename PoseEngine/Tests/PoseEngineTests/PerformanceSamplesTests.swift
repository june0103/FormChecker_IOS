import XCTest
@testable import PoseEngine

/// 성능 표본. **p95 정의와 분모**를 붙든다 — 둘 다 조용히 틀리는 자리다.
final class PerformanceSamplesTests: XCTestCase {

    private func samples(_ values: [Double]) -> PerformanceSamples {
        var s = PerformanceSamples()
        for value in values { s.record(inferenceMs: value) }
        return s
    }

    /// 🔴 **Android와 같은 식**: 정렬 후 `(n-1) * 95 / 100`번째(정수 나눗셈).
    /// 보간하는 정의를 쓰면 같은 기기에서도 두 앱의 숫자를 나란히 놓을 수 없다.
    func testP95MatchesAndroidFormula() {
        // 1...100 → 인덱스 (99*95)/100 = 94 → 95번째 값
        let s = samples((1...100).map(Double.init))
        XCTAssertEqual(s.p95Ms, 95)

        // 1...20 → 인덱스 (19*95)/100 = 18 → 19
        XCTAssertEqual(samples((1...20).map(Double.init)).p95Ms, 19)

        // 1...10 → 인덱스 (9*95)/100 = 8 → 9
        XCTAssertEqual(samples((1...10).map(Double.init)).p95Ms, 9)
    }

    func testP95IgnoresInsertionOrder() {
        let ascending = samples([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        let shuffled = samples([7, 1, 9, 3, 10, 2, 8, 4, 6, 5])
        XCTAssertEqual(ascending.p95Ms, shuffled.p95Ms)
    }

    /// 표본 하나뿐이면 그 값이 곧 p95다 — 터지지 않아야 한다.
    func testSingleSample() {
        let s = samples([12.5])
        XCTAssertEqual(s.p95Ms, 12.5)
        XCTAssertEqual(s.averageMs, 12.5)
    }

    /// 🔴 **표본이 없으면 0이 아니라 nil이다.** 0ms는 "아주 빨랐다"로 읽힌다.
    func testEmptyGivesNilNotZero() {
        let s = PerformanceSamples()
        XCTAssertNil(s.p95Ms)
        XCTAssertNil(s.averageMs)
        XCTAssertNil(s.droppedRatio)
        XCTAssertTrue(s.isEmpty)
    }

    /// 🔴 **p95는 평균이 숨기는 것을 드러낸다.** 100프레임 중 6번 끊기는 것이
    /// 평균에는 거의 안 보이지만 p95에는 그대로 보인다.
    func testP95SurfacesWhatAverageHides() {
        var values = [Double](repeating: 10, count: 94)
        values.append(contentsOf: [Double](repeating: 60, count: 6))
        let s = samples(values)
        XCTAssertEqual(try XCTUnwrap(s.averageMs), 13.0, accuracy: 1e-9)   // 평균은 멀쩡해 보인다
        XCTAssertEqual(s.p95Ms, 60)                                        // p95가 사고를 보여준다
    }

    /// ⚠ **느린 표본이 정확히 5%면 p95는 그것을 넘긴다** — 95%가 그 값 이하라는
    /// 정의 그대로다. 버그로 보고 "최댓값 쪽으로" 고치고 싶어지는 자리라 못 박아 둔다.
    /// 꼬리를 보고 싶으면 p99를 함께 적는 것이 맞지, p95의 정의를 바꾸는 것이 아니다.
    func testExactlyFivePercentSlowStaysBelowP95() {
        var values = [Double](repeating: 10, count: 95)
        values.append(contentsOf: [Double](repeating: 60, count: 5))
        let s = samples(values)
        XCTAssertEqual(s.p95Ms, 10)
        XCTAssertEqual(s.percentile(99), 60)   // 꼬리는 p99가 말한다
    }

    // ── 분모 ────────────────────────────────────────────────

    /// 🔴 **분모는 시도한 프레임(성공 + 실패)이다.** 성공한 것만 세면 많이 버릴수록
    /// 비율이 작아져서 느릴수록 좋아 보이는 지표가 된다.
    func testDroppedRatioDenominatorIsAttemptedFrames() {
        var s = samples([Double](repeating: 10, count: 90))
        s.recordDrop(10)
        XCTAssertEqual(try XCTUnwrap(s.droppedRatio), 0.10, accuracy: 1e-9)
    }

    func testAllDroppedIsOne() {
        var s = PerformanceSamples()
        s.recordDrop(7)
        XCTAssertEqual(s.droppedRatio, 1)
        XCTAssertNil(s.p95Ms)   // 추론한 것이 없으니 지연은 모른다
    }

    func testNothingAttemptedGivesNil() {
        var s = PerformanceSamples()
        s.recordDrop(0)
        XCTAssertNil(s.droppedRatio)
    }

    func testResetClearsEverything() {
        var s = samples([1, 2, 3])
        s.recordDrop(2)
        s.reset()
        XCTAssertTrue(s.isEmpty)
        XCTAssertEqual(s.analyzed, 0)
        XCTAssertEqual(s.dropped, 0)
        XCTAssertNil(s.droppedRatio)
    }

    // ── 목표 ────────────────────────────────────────────────

    /// 🔴 **"모른다"와 "통과"는 다르다.** 표본이 없으면 nil을 낸다 — false로 바꾸면
    /// 측정하지 않은 것이 "목표 미달"로 보고된다.
    func testTargetIsNilWithoutSamples() {
        XCTAssertNil(PerformanceTarget.meetsInference(p95Ms: nil))
        XCTAssertEqual(PerformanceTarget.meetsInference(p95Ms: 24), true)
        XCTAssertEqual(PerformanceTarget.meetsInference(p95Ms: 25), true)   // 경계는 통과
        XCTAssertEqual(PerformanceTarget.meetsInference(p95Ms: 26), false)
    }

    /// 30fps 예산은 33.3ms다. 파이프라인 목표가 그보다 느슨해지면 예산이 무의미해진다.
    func testPipelineTargetFitsInThirtyFpsBudget() {
        XCTAssertLessThanOrEqual(PerformanceTarget.pipelineP95Ms, 1000.0 / 30)
    }
}
