import XCTest
@testable import PoseEngine

final class RepScoreTests: XCTestCase {

    private let thresholds = FormThresholds()

    func test_측면은_깊이와_상체_숙임과_뒤꿈치와_무릎_위치를_판정한다() {
        XCTAssertEqual(RepScorer.checksFor(.side),
                       [.shallowDepth, .excessiveLean, .heelRise, .kneePastToe])
    }

    func test_정면은_무릎_정렬과_골반_쏠림을_판정한다() {
        XCTAssertEqual(RepScorer.checksFor(.front), [.kneeValgus, .kneeFlared, .hipShift])
    }

    /// 두 각도가 겹치지 않는 것이 **리포트 분모가 각도마다 다른 이유**다.
    func test_두_각도의_판정_항목이_겹치지_않는다() {
        XCTAssertEqual(RepScorer.checksFor(.side).intersection(RepScorer.checksFor(.front)), [])
    }

    func test_판정한_항목_수와_경고_난_항목_수를_센다() {
        let score = RepScorer.score(cameraAngle: .side, warnings: [.shallowDepth],
                                    depthValue: -0.10, depthBasis: .hipHeight,
                                    thresholds: thresholds)
        XCTAssertEqual(score.checkedCount, 4, "측면은 깊이·상체·뒤꿈치·무릎 위치 네 항목")
        XCTAssertEqual(score.warnedCount, 1)
        XCTAssertEqual(score.clean, false)
    }

    func test_판정하지_않은_항목은_플래그에_넣지_않는다() {
        let front = RepScorer.score(cameraAngle: .front, warnings: [.kneeValgus],
                                    depthValue: nil, depthBasis: nil, thresholds: thresholds)
        XCTAssertNotNil(front.errorFlags[.kneeValgus])
        XCTAssertNil(front.errorFlags[.shallowDepth],
                     "정면에서는 깊이를 재지 않으므로 키 자체가 없어야 한다")
    }

    func test_그_각도에서_판정하지_않는_경고는_무시한다() {
        let score = RepScorer.score(cameraAngle: .front,
                                    warnings: [.shallowDepth, .excessiveLean],
                                    depthValue: nil, depthBasis: nil, thresholds: thresholds)
        XCTAssertEqual(score.checkedCount, 3)
        XCTAssertEqual(score.warnedCount, 0, "측면 전용 경고 2개는 세지 않는다")
        XCTAssertEqual(score.clean, true)
    }

    /// **"괜찮다"와 "못 봤다"는 다르다.**
    func test_판정_항목이_없으면_clean은_nil이다() {
        let empty = RepScore(depthScore: nil, checkedCount: 0, warnedCount: 0, errorFlags: [:])
        XCTAssertNil(empty.clean)
    }

    func test_패럴렐이_1점이고_선_자세_경계가_0점이다() throws {
        func score(_ value: Float) throws -> Float {
            try XCTUnwrap(RepScorer.score(cameraAngle: .side, warnings: [],
                                          depthValue: value, depthBasis: .hipHeight,
                                          thresholds: thresholds).depthScore)
        }
        XCTAssertEqual(try score(thresholds.standingDepthRatio), 0, accuracy: 0.001)
        XCTAssertEqual(try score(0), 1, accuracy: 0.001)
        XCTAssertEqual(try score(thresholds.standingDepthRatio / 2), 0.5, accuracy: 0.001,
                       "중간값은 선형")
    }

    func test_패럴렐보다_깊으면_1점으로_자른다() throws {
        let deep = RepScorer.score(cameraAngle: .side, warnings: [], depthValue: 0.20,
                                   depthBasis: .hipHeight, thresholds: thresholds)
        XCTAssertEqual(try XCTUnwrap(deep.depthScore), 1, accuracy: 0.001)
    }

    /// 두 기준은 서로 환산되지 않지만, **점수로 바꾸면 같은 자세가 같은 점수**여야 한다.
    func test_두_정규화_기준이_같은_자세에_같은_점수를_준다() throws {
        func score(_ value: Float, _ basis: DepthBasis) throws -> Float {
            try XCTUnwrap(RepScorer.score(cameraAngle: .side, warnings: [],
                                          depthValue: value, depthBasis: basis,
                                          thresholds: thresholds).depthScore)
        }
        XCTAssertEqual(try score(-0.20, .hipHeight), try score(-0.415, .shinLength), accuracy: 0.01)
    }

    func test_정면에서는_깊이_점수가_없다() {
        let front = RepScorer.score(cameraAngle: .front, warnings: [], depthValue: 0,
                                    depthBasis: .hipHeight, thresholds: thresholds)
        XCTAssertNil(front.depthScore)
    }

    func test_깊이를_못_재면_점수가_없다() {
        let noDepth = RepScorer.score(cameraAngle: .side, warnings: [], depthValue: nil,
                                      depthBasis: nil, thresholds: thresholds)
        XCTAssertNil(noDepth.depthScore)
        XCTAssertEqual(noDepth.checkedCount, 4,
                       "깊이를 못 재도 상체 숙임·뒤꿈치·무릎 위치는 판정한다")
    }
}
