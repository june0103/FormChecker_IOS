import Foundation
import PoseEngine

/// 사용자 문구. **한 곳에만 둔다** — 운동 중 화면·결과 화면·기록 화면이 함께 쓴다.
///
/// 🔴 **용어를 쓰지 않는다.** `rep`·`패럴렐`·`valgus`는 운동이나 개발을 아는 사람의 말이다.
/// **임계값 숫자도 넣지 않는다** — 사용자가 확인할 수 없는 값이다.
/// 말투는 트레이너가 회원에게 하듯, 지시가 아니라 제안.
enum FeedbackLabels {

    /// 운동 중 한 줄로 띄우는 지시.
    static func instruction(_ warning: FormWarning, side: Side?) -> String {
        let prefix = side.map { $0 == .left ? "왼쪽 " : "오른쪽 " } ?? ""
        switch warning {
        case .shallowDepth: return "조금 더 깊게 앉아 주세요"
        case .excessiveLean: return "가슴을 들고 앞을 보세요"
        case .heelRise: return "뒤꿈치를 바닥에 붙이세요"
        case .kneePastToe: return "무릎을 조금 뒤로 빼세요"
        case .kneeValgus: return "\(prefix)무릎을 벌려 주세요"
        case .kneeFlared: return "\(prefix)무릎을 모아 주세요"
        case .hipShift: return "양발에 고르게 실어 주세요"
        }
    }

    /// 깊이 단계. **선 자세는 표시하지 않는다** — 지금 할 일이 아니다.
    static func depth(_ level: DepthLevel) -> String? {
        switch level {
        case .standing: nil
        case .shallow: "얕음"
        case .parallel: "적당"
        case .deep: "깊음"
        }
    }

    /// 준비 자세 안내. **막는 항목이라 문구가 곧 해결 방법이어야 한다.**
    static func ready(_ issue: ReadyIssue) -> String {
        switch issue {
        case .turnToFront: "카메라를 정면으로 마주 보고 서 주세요"
        case .turnToSide: "카메라가 옆에서 보도록 몸을 돌려 주세요"
        case .faceSquarely: "몸이 비스듬해요 — 똑바로 마주 보거나 옆으로 서 주세요"
        case .kneesBent: "무릎을 곧게 펴고 서 주세요"
        case .stanceTooNarrow: "발을 어깨너비로 벌려 주세요"
        case .stanceTooWide: "발을 조금 모아 주세요"
        case .toesInward: "발끝을 살짝 바깥으로 돌려 주세요"
        case .weightOnOneSide: "체중을 양발에 고르게 실어 주세요"
        }
    }

    /// 왜 세지 않는지. **막는 대신 알린다.**
    static func notCounting(stage: CalibrationStage, readyIssue: ReadyIssue?) -> String? {
        switch stage {
        case .ready: nil
        case .none: "먼저 기준 자세를 재주세요"
        case .preparing, .measuring: readyIssue.map(ready) ?? "그대로 서 계세요"
        case .failed: "기준 자세를 다시 재주세요"
        }
    }

    static func abort(_ reason: RepEvent.AbortReason) -> String? {
        switch reason {
        case .notDeepEnough: "조금 더 앉아야 세어져요"
        case .tooFast: "조금 천천히 해볼까요"
        case .timeout: nil
        case .poseLost: "몸 전체가 보이게 서 주세요"
        }
    }
}
