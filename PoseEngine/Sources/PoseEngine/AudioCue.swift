import Foundation

/// 소리로 알려야 할 **사실**. 어떤 소리를 낼지는 앱이 정한다.
///
/// ## 왜 신호만 여기 있나
/// 파이프라인은 "기준 자세가 잡혔다"·"rep이 경고와 함께 끝났다"까지 말하고 끝낸다.
/// 톤을 합성하고 세션을 여는 일은 `AVFoundation`이 필요하고, 그것이 패키지에 들어오면
/// **녹화 좌표를 주입해 돌리는 검증이 불가능해진다**(PoseEngine 의존 규칙).
///
/// 그래서 신호는 패키지에, 소리는 앱(`AudioCues`)에 둔다.
public enum AudioCue: String, Sendable, CaseIterable {
    case countdown, calibrated, failed, repDone, repWarned, sessionEnd
}
