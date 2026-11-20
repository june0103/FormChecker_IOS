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

// ─────────────────────────────────────────────────────────────

/// 결과 리포트 문구.
///
/// 🔴 **점수를 내지 않는다.** 잦은 것부터, 횟수를 그대로 적는다.
/// **"몇 % 이상이면 습관인가"를 정하지 않는다** — 그 경계에 근거가 없다.
extension FeedbackLabels {

    static func phase(_ phase: RepPhase?) -> String {
        switch phase {
        case .descending: "내려갈 때 "
        case .bottom: "가장 낮은 지점에서 "
        case .ascending: "올라올 때 "
        case .throughout: "동작 내내 "
        case nil: ""
        }
    }

    /// "내려갈 때 왼쪽 무릎이 안쪽으로 모여요"
    static func sentence(_ finding: Finding) -> String {
        let when = phase(finding.phase)
        let side = finding.side.map { $0 == .left ? "왼쪽 " : "오른쪽 " } ?? ""
        switch finding.warning {
        case .kneeValgus: return "\(when)\(side)무릎이 안쪽으로 모여요"
        case .kneeFlared: return "\(when)\(side)무릎이 발끝보다 바깥으로 벌어져요"
        case .hipShift: return "\(when)체중이 한쪽 발로 쏠려요"
        case .shallowDepth: return "엉덩이가 무릎 높이까지 내려오지 않았어요"
        case .excessiveLean: return "\(when)상체가 많이 숙여져요"
        case .heelRise: return "\(when)뒤꿈치가 바닥에서 떨어져요"
        case .kneePastToe: return "무릎이 발끝보다 앞으로 나가요"
        }
    }

    /// "확인한 10번 중 8번" — **전부일 때만** "모두에서"라고 쓴다.
    /// 그건 임계값이 아니라 `count == denominator`라는 사실이다.
    static func count(_ finding: Finding) -> String {
        finding.everyRep
            ? "확인한 \(finding.judgedReps)번 모두에서 나왔어요"
            : "확인한 \(finding.judgedReps)번 중 \(finding.repCount)번"
    }

    /// 경고 한 가지가 말하는 **몸의 부위/주제**.
    ///
    /// ⚠ 경고와 1:1이 아니다 — `kneeValgus`와 `kneeFlared`는 **같은 "무릎 방향"**이다.
    /// 목록에 그대로 늘어놓으면 같은 말이 두 번 뜬다(`notJudgedSentence`가 중복을 지운다).
    static func topic(_ warning: FormWarning) -> String {
        switch warning {
        case .shallowDepth: "앉은 깊이"
        case .excessiveLean: "상체 숙임"
        case .heelRise: "뒤꿈치"
        case .kneePastToe: "무릎 위치"
        case .kneeValgus, .kneeFlared: "무릎 방향"
        case .hipShift: "좌우 균형"
        }
    }

    /// 🔴 **못 본 것을 반드시 말한다** — 말하지 않으면 "피드백 없음"이 "전부 괜찮다"로 읽힌다.
    ///
    /// 🔴 **이유를 구분해서 말한다** — 각도 때문이면 다른 방향에서 찍으면 풀리고,
    /// 인식 문제면 각도를 바꿔도 안 풀린다. 사용자가 다음에 **무엇을 바꿀지** 알아야 한다.
    ///
    /// 항목을 한 줄씩 쌓지 않고 한 문장으로 묶는 것은 중복 때문만이 아니다 — 여섯 줄짜리
    /// 경고 목록은 "내가 뭘 잘못했나"로 읽힌다. 못 본 것은 잘못이 아니다.
    static func notJudgedSentence(_ items: [NotJudged]) -> String {
        func topics(_ reason: NotJudged.Reason) -> [String] {
            var seen = Set<String>()
            return items.filter { $0.reason == reason }.map { topic($0.warning) }
                .filter { seen.insert($0).inserted }
        }

        // 조사는 마지막 항목의 종성에 따라 갈린다. 박아두면 항목이 늘 때마다
        // "앉은 깊이은" 같은 말이 생긴다.
        func listed(_ names: [String], _ withFinal: String, _ without: String) -> String {
            names.joined(separator: ", ") + josa(names.last ?? "", withFinal, without)
        }

        let byAngle = topics(.cameraAngle)
        let notCaught = topics(.noJudgedRep)

        var text = ""
        if !byAngle.isEmpty {
            text += "이번엔 \(listed(byAngle, "은", "는")) 볼 수 없었어요. "
            text += "카메라 방향 때문이라, 다음엔 다른 방향에서도 한 세트 찍어보시면 같이 봐드릴게요."
        }
        if !notCaught.isEmpty {
            if !text.isEmpty { text += " " }
            text += "\(listed(notCaught, "은", "는")) 몸이 잘 안 잡혀서 확인하지 못했어요."
        }
        return text
    }

    /// 받침이 있으면 `withFinal`, 없으면 `without`.
    static func josa(_ word: String, _ withFinal: String, _ without: String) -> String {
        guard let last = word.unicodeScalars.last else { return withFinal }
        let hangul = UInt32(0xAC00)...UInt32(0xD7A3)
        guard hangul.contains(last.value) else { return withFinal }
        return (last.value - hangul.lowerBound) % 28 == 0 ? without : withFinal
    }
}
