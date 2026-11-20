import XCTest
@testable import PoseEngine

final class JointAnglesTests: XCTestCase {

    /// 힙-무릎-발목이 일직선이면 180도 — STANDING 상태에 해당한다.
    func test_똑바로_선_다리는_180도에_가깝다() {
        let pose = PoseFixtures.leg(hip: (0.5, 0.2), knee: (0.5, 0.5), ankle: (0.5, 0.8))
        let angle = try? XCTUnwrap(JointAngles.knees(pose, frameAspectRatio: 1).left)
        XCTAssertEqual(angle ?? 0, 180, accuracy: 1)
    }

    func test_직각으로_굽힌_무릎은_90도다() throws {
        let pose = PoseFixtures.leg(hip: (0.5, 0.2), knee: (0.5, 0.5), ankle: (0.8, 0.5))
        let angle = try XCTUnwrap(JointAngles.knees(pose, frameAspectRatio: 1).left)
        XCTAssertEqual(angle, 90, accuracy: 1)
    }

    /// 같은 정규화 좌표라도 프레임 종횡비가 다르면 실제 각도는 달라야 한다.
    /// 두 값이 같다면 보정이 적용되지 않은 것이고, 그러면 **기기 카메라 비율에 따라
    /// 같은 스쿼트가 다른 각도로 측정된다.**
    func test_종횡비에_따라_각도가_달라진다() throws {
        let pose = PoseFixtures.leg(hip: (0.5, 0.3), knee: (0.5, 0.5), ankle: (0.7, 0.6))
        let square = try XCTUnwrap(JointAngles.knees(pose, frameAspectRatio: 1).left)
        let wide = try XCTUnwrap(JointAngles.knees(pose, frameAspectRatio: 16.0 / 9.0).left)
        XCTAssertGreaterThan(abs(square - wide), 1,
                             "종횡비 보정이 각도에 반영되어야 한다 (1:1=\(square), 16:9=\(wide))")
    }

    /// confidence 0.3 미만으로 계산한 각도는 내놓지 않는다.
    func test_신뢰도가_낮으면_각도를_계산하지_않는다() {
        let pose = PoseFixtures.pose([
            .leftHip: (0.5, 0.2, 0.9),
            .leftKnee: (0.5, 0.5, 0.1),   // 임계값 미만
            .leftAnkle: (0.5, 0.8, 0.9),
        ])
        XCTAssertNil(JointAngles.knees(pose, frameAspectRatio: 1).left)
    }

    func test_한쪽만_신뢰_가능하면_그_값이_대표_각도가_된다() {
        let pose = PoseFixtures.leg(hip: (0.4, 0.2), knee: (0.4, 0.5), ankle: (0.4, 0.8))
        let angles = JointAngles.knees(pose, frameAspectRatio: 1)
        XCTAssertNotNil(angles.left)
        XCTAssertNil(angles.right)
        XCTAssertEqual(angles.left, angles.representative)
        XCTAssertNil(angles.asymmetry, "한쪽만 있으면 비대칭을 계산할 수 없다")
    }

    func test_양쪽_모두_신뢰_가능하면_평균이_대표_각도가_된다() throws {
        let pose = PoseFixtures.pose([
            .leftHip: (0.4, 0.2, 0.9), .leftKnee: (0.4, 0.5, 0.9), .leftAnkle: (0.4, 0.8, 0.9),
            .rightHip: (0.6, 0.2, 0.9), .rightKnee: (0.6, 0.5, 0.9), .rightAnkle: (0.9, 0.5, 0.9),
        ])
        let a = JointAngles.knees(pose, frameAspectRatio: 1)
        let left = try XCTUnwrap(a.left), right = try XCTUnwrap(a.right)
        XCTAssertEqual(try XCTUnwrap(a.representative), (left + right) / 2, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(a.asymmetry), abs(left - right), accuracy: 0.01)
    }

    func test_빈_포즈는_각도가_없다() {
        let angles = JointAngles.knees(PoseFixtures.pose([:]), frameAspectRatio: 1)
        XCTAssertNil(angles.left)
        XCTAssertNil(angles.right)
        XCTAssertNil(angles.representative)
    }
}
