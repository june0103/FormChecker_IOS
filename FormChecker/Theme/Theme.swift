import SwiftUI

/// 디자인 시스템 토큰 (02_디자인시스템.md).
///
/// **앱 전체가 다크 단일 테마다** — 시스템 라이트/다크를 따르지 않는다. 카메라 프리뷰 위에
/// 스켈레톤·HUD·피드백을 얹는 화면이 핵심이고, 실제 사용 환경(집, 저녁)도 밝지 않다.
///
/// 🔴 **라임은 "성공/카운트/CTA" 전용이다.** 그 외 상태는 Warning/Danger/Info 중 하나로만
/// 표현하고 새 색을 추가하지 않는다. 추가하고 싶어지면 기존 다섯 시맨틱 컬러로 표현할 수
/// 있는지부터 본다.
enum Palette {
    static let bgBase = Color(hex: 0x0A0A0F)
    static let surfaceCard = Color(hex: 0x1A1A22)
    static let surfaceVariant = Color(hex: 0x24242E)
    static let outline = Color(hex: 0x2E2E38)

    static let textPrimary = Color(hex: 0xF5F5F7)
    static let textMuted = Color(hex: 0x9A9AA5)
    static let textDisabled = Color(hex: 0x5A5A66)

    /// **앱 전체에서 유일한 강조색.**
    static let lime = Color(hex: 0xC6FF00)
    static let limeDim = Color(hex: 0x8FB800)
    static let limeContainer = Color(hex: 0x1F2B00)

    /// 폼 경고. ⚠ 오렌지는 스플래시의 시작 상태에도 쓰인다.
    static let warning = Color(hex: 0xFF6B35)
    static let warningContainer = Color(hex: 0x2E1A10)
    /// 하드 에러 (모델 로드 실패, 카메라 불가).
    static let danger = Color(hex: 0xFF4757)
    static let dangerContainer = Color(hex: 0x2E0F13)
    /// 중립 안내.
    static let info = Color(hex: 0x4DA3FF)
    static let infoContainer = Color(hex: 0x10202E)

    /// 솔리드 배너 위의 글자. **어두운 글자여야 대비 5.9~7.5:1로 AA를 통과한다** —
    /// 초기안의 "진한 배경 + 흰 글자"는 2.63~2.84:1로 미달이었다.
    static let onSolid = Color(hex: 0x0A0A0F)
}

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum Radius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let pill: CGFloat = 999
}

enum Motion {
    static let fast: Double = 0.12
    static let medium: Double = 0.24
    static let slow: Double = 0.40
    /// rep 카운트 증가 시 숫자 펄스 (1.0 → 1.15 → 1.0).
    static let repPulse: Double = 0.18
}

/// 최소 터치 타겟. Android는 48dp, iOS HIG는 **44pt**다.
enum TouchTarget {
    static let min: CGFloat = 44
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension Font {
    /// rep 숫자. 2자리까지 96pt, 3자리부터 72pt(좁은 화면 클리핑 방지).
    static func repCounter(digits: Int) -> Font {
        .system(size: digits >= 3 ? 72 : 96, weight: .black, design: .default)
    }
}
