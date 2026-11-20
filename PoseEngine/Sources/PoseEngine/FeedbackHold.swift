import Foundation

public struct HeldWarning: Sendable, Equatable {
    public let warning: FormWarning
    public let side: Side?
    public let firstShownAtMs: Int64
}

/// 화면 피드백을 읽을 수 있는 시간만큼 붙잡아 둔다.
///
/// 프레임 단위 경고는 그 자세를 유지하는 동안만 참이라, **최저점에서 난 경고가 다 올라온
/// 뒤에는 이미 사라져 있다**(실측 상승 구간 p95 1,171ms). 항목당 하나씩 2초 붙잡는다.
///
/// 🔴 **항목마다 다르게 두지 않는다.** 한때 깊이만 0.9초로 줄였는데, 그건 표시 시간 문제가
/// 아니라 **판정 시점 문제**였고 깊이를 rep 단위로 옮기면서 사라졌다.
///
/// 🔴 **정렬은 도착 순(새로 뜬 것이 맨 위)이다** — 우선순위 순이 아니다. 새 오류가 자기
/// 순위 자리에 끼어들면 눈에 안 띄고, 하단 고정이라 위에 붙여야 기존 줄이 안 밀린다.
public final class FeedbackHold {

    public static let defaultHoldMs: Int64 = 2_000

    private final class Entry {
        let warning: FormWarning
        let side: Side?
        let firstShownAtMs: Int64
        var lastSeenAtMs: Int64

        init(warning: FormWarning, side: Side?, firstShownAtMs: Int64) {
            self.warning = warning
            self.side = side
            self.firstShownAtMs = firstShownAtMs
            self.lastSeenAtMs = firstShownAtMs
        }
    }

    private let holdMs: Int64
    private var held: [FormCheck: Entry] = [:]

    public init(holdMs: Int64 = FeedbackHold.defaultHoldMs) {
        self.holdMs = holdMs
    }

    /// 한 항목(``FormCheck``)에 **하나만** 남긴다 — 같은 항목의 다른 방향(모임/벌어짐)이
    /// 오면 새 것으로 교체한다.
    public func update(
        warnings: [FormWarning], side: Side?, nowMs: Int64
    ) -> [HeldWarning] {
        for warning in warnings {
            if let existing = held[warning.check], existing.warning == warning {
                existing.lastSeenAtMs = nowMs
                continue
            }
            held[warning.check] = Entry(
                warning: warning,
                side: warning.hasSide ? side : nil,
                firstShownAtMs: nowMs
            )
        }
        held = held.filter { nowMs - $0.value.lastSeenAtMs < holdMs }

        return held.values
            .map { HeldWarning(warning: $0.warning, side: $0.side, firstShownAtMs: $0.firstShownAtMs) }
            .sorted { lhs, rhs in
                if lhs.firstShownAtMs != rhs.firstShownAtMs {
                    return lhs.firstShownAtMs > rhs.firstShownAtMs   // 새 것이 위
                }
                // 같은 프레임에 함께 나면 그때만 선언 순서로 가른다.
                return lhs.warning.order < rhs.warning.order
            }
    }

    public func reset() { held.removeAll() }
}

extension FormWarning {
    /// 좌우를 지목할 수 있는 항목인가.
    var hasSide: Bool { check == .kneeAlignment }

    /// 선언 순서. Kotlin `ordinal`에 대응한다.
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}
