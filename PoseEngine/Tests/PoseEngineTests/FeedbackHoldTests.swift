import XCTest
@testable import PoseEngine

/// 피드백을 **읽을 수 있는 시간만큼** 붙잡는다.
final class FeedbackHoldTests: XCTestCase {

    private var hold = FeedbackHold(holdMs: 2_000)

    override func setUp() {
        super.setUp()
        hold = FeedbackHold(holdMs: 2_000)
    }

    @discardableResult
    private func update(_ warnings: FormWarning..., at: Int64, side: Side? = nil) -> [HeldWarning] {
        hold.update(warnings: warnings, side: side, nowMs: at)
    }

    func test_경고가_사라진_뒤에도_붙잡아_둔다() {
        update(.shallowDepth, at: 0)
        XCTAssertEqual(update(at: 100).map(\.warning), [.shallowDepth])
    }

    /// **상승 구간 p95가 1,171ms** — 다 올라올 때까지 남아야 읽을 수 있다.
    func test_상승_구간이_가장_길었던_rep에서도_다_올라올_때까지_남는다() {
        update(.kneeValgus, at: 0)
        XCTAssertEqual(update(at: 1_171).count, 1)
    }

    func test_붙잡는_시간이_지나면_사라진다() {
        update(.heelRise, at: 0)
        XCTAssertFalse(update(at: 1_999).isEmpty)
        XCTAssertTrue(update(at: 2_000).isEmpty)
    }

    func test_경고가_계속_나면_갱신되어_사라지지_않는다() {
        update(.heelRise, at: 0)
        update(.heelRise, at: 1_500)
        update(.heelRise, at: 3_000)
        XCTAssertFalse(update(at: 4_500).isEmpty)
        XCTAssertTrue(update(at: 5_000).isEmpty)
    }

    func test_이어지는_동안_처음_뜬_시각은_그대로다() throws {
        update(.shallowDepth, at: 500)
        let held = try XCTUnwrap(update(.shallowDepth, at: 1_200).first)
        XCTAssertEqual(held.firstShownAtMs, 500)
    }

    /// 한 항목(``FormCheck``)에 하나만 남는다.
    func test_같은_항목의_반대_방향은_나중_것만_남는다() {
        update(.kneeFlared, at: 0)
        XCTAssertEqual(update(.kneeValgus, at: 300).map(\.warning), [.kneeValgus])
    }

    func test_갈아탄_경고는_그_시점부터_다시_붙잡는다() {
        update(.kneeFlared, at: 0)
        update(.kneeValgus, at: 1_800)
        XCTAssertEqual(update(at: 3_000).count, 1)
        XCTAssertTrue(update(at: 3_800).isEmpty)
    }

    func test_다른_항목은_함께_남는다() {
        update(.shallowDepth, .excessiveLean, at: 0)
        XCTAssertEqual(Set(update(at: 100).map(\.warning)), [.shallowDepth, .excessiveLean])
    }

    func test_한_각도에서_뜰_수_있는_줄_수는_판정_항목_수와_같다() {
        for angle in CameraAngle.allCases {
            let fresh = FeedbackHold(holdMs: 2_000)
            let all = Array(RepScorer.checksFor(angle))
            let held = fresh.update(warnings: all, side: .left, nowMs: 0)
            XCTAssertEqual(held.count, angle.supportedChecks.count,
                           "\(angle) 에서 뜨는 줄 수는 판정 항목 수여야 한다")
        }
    }

    /// 🔴 **도착 순이다** — 우선순위 순이 아니다.
    func test_나중에_뜬_것이_위다() {
        update(.kneeValgus, at: 0)
        XCTAssertEqual(update(.hipShift, at: 100).map(\.warning), [.hipShift, .kneeValgus])
    }

    func test_같은_프레임에_뜨면_우선순위로_가른다() {
        XCTAssertEqual(update(.hipShift, .kneeValgus, at: 0).map(\.warning),
                       [.kneeValgus, .hipShift])
    }

    func test_차례로_뜨면_역순으로_쌓인다() {
        update(.kneeValgus, at: 0)
        update(.excessiveLean, at: 100)
        XCTAssertEqual(update(.hipShift, at: 200).map(\.warning),
                       [.hipShift, .excessiveLean, .kneeValgus])
    }

    func test_먼저_뜬_것이_먼저_사라진다() {
        update(.kneeValgus, at: 0)
        update(.hipShift, at: 500)
        XCTAssertEqual(update(at: 2_000).map(\.warning), [.hipShift])
        XCTAssertTrue(update(at: 2_500).isEmpty)
    }

    func test_무릎_경고에만_쪽이_붙는다() {
        let held = update(.kneeValgus, .hipShift, at: 0, side: .left)
        var bySide: [FormWarning: Side?] = [:]
        for item in held { bySide[item.warning] = item.side }
        XCTAssertEqual(bySide[.kneeValgus], .left)
        XCTAssertEqual(bySide[.hipShift], Side?.none)
    }

    func test_붙잡아_둔_경고의_쪽은_바뀌지_않는다() throws {
        update(.kneeValgus, at: 0, side: .left)
        let held = try XCTUnwrap(hold.update(warnings: [], side: .right, nowMs: 500).first)
        XCTAssertEqual(held.side, .left)
    }

    func test_초기화하면_전부_지운다() {
        update(.shallowDepth, at: 0)
        hold.reset()
        XCTAssertTrue(update(at: 10).isEmpty)
    }
}
