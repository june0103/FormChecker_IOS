import XCTest
@testable import PoseEngine

/// "지금 rep 안인가" — 자세 판정을 할 수 있는 구간인가.
///
/// ## 이 규칙은 실기 신고에서 생겼다
/// 화면 쪽에 이 게이트가 없어서 **가만히 서 있어도 "양발로 고르게 일어서세요"가 떴다.**
/// 서 있는 사람에게 일어서라고 말하는 문구다.
///
/// 근거는 임계값의 출처다 — `hipShiftLimit`은 정상 의도 9명 794프레임의 **최저점**
/// 분포에서, `kneeToeToleranceRatio`는 11명 253 rep 최저점의 사람내 MAD에서 나왔다.
/// 선 자세 프레임에 그 값을 대면 **도출 범위 밖에서 판정하는 것**이다.
///
/// **규칙을 되돌리려면 이 테스트가 함께 깨져야 한다.**
final class RepStateInRepTests: XCTestCase {

    func test_하강_최저점_상승은_rep_안이다() {
        XCTAssertTrue(RepState.descending.isInRep)
        XCTAssertTrue(RepState.bottom.isInRep)
        XCTAssertTrue(RepState.ascending.isInRep)
    }

    func test_선_자세는_rep_밖이다() {
        XCTAssertFalse(RepState.standing.isInRep, "서 있을 때 자세 경고가 뜨면 안 된다")
    }

    func test_미인식은_rep_밖이다() {
        XCTAssertFalse(RepState.idle.isInRep)
    }

    /// 새 상태를 추가하면 `switch`가 컴파일 시점에 막아 주지만 **분류를 빠뜨리는 것**은
    /// 막지 못한다. 전체 개수를 붙들어 두면 새 상태가 조용히 한쪽으로 들어가는 것을 알아챈다.
    func test_모든_상태가_분류돼_있다() {
        XCTAssertFalse(RepState.allCases.isEmpty)
        XCTAssertEqual(RepState.allCases.filter(\.isInRep).count, 3, "rep 안 상태가 3개여야 한다")
        XCTAssertEqual(RepState.allCases.filter { !$0.isInRep }.count, 2, "rep 밖 상태가 2개여야 한다")
    }
}
