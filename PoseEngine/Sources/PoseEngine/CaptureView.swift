import Foundation

/// 촬영 방향. 측면은 **어느 쪽 몸이 카메라를 향하는가**까지 구분한다.
public enum CaptureView: String, Sendable, CaseIterable {
    case front, sideLeft, sideRight

    public var displayName: String {
        switch self {
        case .front: "정면"
        case .sideLeft: "좌측면"
        case .sideRight: "우측면"
        }
    }

    public var isFront: Bool { self == .front }
    public var isSide: Bool { self != .front }

    /// 카메라에 가까운 쪽 다리.
    ///
    /// 측면 촬영에서 **세션 내내 이 쪽으로 고정한다.** 프레임마다 신뢰도가 높은 다리로
    /// 교체하면 관절 좌표가 전환되면서 각도가 크게 튄다 — 실측에서도 확인했다. 선 자세는
    /// 좌우 중점, 최저점은 한쪽만 쓰게 되어 **두 기준의 차를 재고 있었다.**
    ///
    /// `sideLeft`는 신체의 왼쪽이 카메라를 향한다는 뜻이므로 활성 다리는 왼쪽이다.
    public var activeSide: Side? {
        switch self {
        case .front: nil
        case .sideLeft: .left
        case .sideRight: .right
        }
    }

    public var cameraAngle: CameraAngle { isFront ? .front : .side }
}
