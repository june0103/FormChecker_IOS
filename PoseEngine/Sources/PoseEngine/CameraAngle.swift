import Foundation

/// 촬영 각도. **어느 판정을 신뢰할 수 있는지가 여기서 갈린다.**
///
/// 2D 단일 카메라로는 깊이와 무릎 정렬을 동시에 정확히 볼 수 없다. 측면에서는 무릎과
/// 발목이 x축으로 겹쳐 보여 무릎이 안으로 말리는지 알 수 없고, 정면에서는 원근 때문에
/// 힙-무릎-발목 각도가 실제보다 왜곡된다. 그래서 각도별로 **그에 맞는 판정만 켠다.**
public enum CameraAngle: String, Sendable, CaseIterable {
    /// 측면 — 깊이·상체 기울기 판정에 적합. rep 카운팅의 기준이 되는 각도.
    case side
    /// 정면 — 무릎 정렬·좌우 비대칭 판정에 적합.
    case front

    public func supports(_ check: FormCheck) -> Bool { supportedChecks.contains(check) }

    public var supportedChecks: Set<FormCheck> {
        switch self {
        case .side: [.depth, .torsoLean, .heelLift, .kneeOverToe]
        case .front: [.kneeAlignment, .symmetry]
        }
    }
}

/// 자세 판정 항목.
///
/// 지원하지 않는 각도에서는 **아예 계산하지 않는다** — 틀린 값을 내놓는 것보다
/// "이 각도에서는 판정 불가"가 정직하고, 사용자도 각도를 바꿀 판단을 할 수 있다.
public enum FormCheck: String, Sendable, CaseIterable {
    /// 깊이 — 충분히 앉았는가.
    case depth
    /// 상체 기울기 — 과도한 전방 숙임. 측면에서만 보인다.
    case torsoLean
    /// 뒤꿈치 들림 — 측면에서만 보인다.
    ///
    /// ## ``depth``와 짝이다
    /// 올바른 스쿼트의 깊이는 "뒤꿈치가 뜨지 않는 범위까지"다. 그래서 이 항목이 걸리면
    /// 깊이 부족 경고를 내지 않는다 — 두 경고가 함께 뜨면 "뒤꿈치가 떴는데 더 깊게
    /// 앉으라"는 **서로 반대인 지시**가 된다.
    case heelLift
    /// 무릎 앞쪽 이동 — 측면에서만 보인다.
    ///
    /// ## ``heelLift``와 원인이 같다
    /// 정강이가 앞으로 기울면 무릎이 앞으로 나가고, 더 기울면 뒤꿈치가 뜬다 — 같은
    /// 움직임의 정도 차이다. 둘이 함께 뜰 수 있고 **지시도 같은 방향**이라("덜 앞으로")
    /// 서로 배제하지 않는다. 깊이-뒤꿈치 관계와 다른 점이 이것이다.
    case kneeOverToe
    /// 무릎 정렬 — 무릎이 안으로 말리는가(valgus). 정면에서만 보인다.
    case kneeAlignment
    /// 좌우 비대칭 — 한쪽으로 체중이 쏠리는가. 정면에서만 양쪽이 모두 보인다.
    case symmetry
}
