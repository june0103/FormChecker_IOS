import SwiftUI

/// 설치 후 첫 실행에 한 번 보여주는 4쪽 안내.
///
/// ## 무엇을 말하고 무엇을 말하지 않나
/// **지금 앱이 실제로 하는 것만** 말한다 — 횟수 세기, 자세 안내, 하루 목표와 주간 흐름,
/// 기준 자세를 재고 나서 세기 시작한다는 순서, 촬영 환경. 점수·등급을 준다고 하지 않고,
/// 트레이너나 의료 전문가를 대신한다고 하지 않는다. 문구 정본은 `Onboarding.pages`에 있다.
///
/// ## 여기서 카메라 권한을 묻지 않는다
/// 권한은 카메라를 실제로 켜는 자리(운동 화면)에서 묻는 것이 맞다. 설명만 읽는 화면에서
/// 물으면 **무엇에 쓰는지 모른 채 거절하게 된다.**
///
/// ## 그림은 도형으로만
/// 새 이미지를 만들거나 내려받지 않는다. 1쪽은 앱 심볼이고, 나머지는 화면에서 실제로 보게
/// 될 것(막대그래프·정렬되는 관절점·촬영 구도)을 그대로 옮겼다.
///
/// ## 다시 보기도 같은 화면이다
/// 설정의 `앱 사용법`에서 열면 `review`가 켜진다. 내용은 같고, 끝났을 때 **완료 상태를
/// 바꾸지 않는 것**만 다르다.
struct OnboardingScreen: View {

    /// 다시 보기로 열었나. 버튼 이름이 `시작하기`가 아니라 `닫기`가 된다 —
    /// 이미 쓰고 있는 사람에게 "시작"은 **무엇이 시작되는지 알 수 없는 말**이다.
    var review = false
    let onFinish: () -> Void

    @State private var index = 0

    private var pages: [OnboardingPage] { Onboarding.pages }
    private var isLast: Bool { index == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(review ? "닫기" : "건너뛰기", action: onFinish)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.textMuted)
                    .frame(minHeight: TouchTarget.min)
            }
            .padding(.horizontal, Spacing.md)

            TabView(selection: $index) {
                ForEach(Array(pages.enumerated()), id: \.offset) { offset, page in
                    pageContent(page).tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            indicator
                .padding(.vertical, Spacing.md)

            Button {
                if isLast { onFinish() }
                else { withAnimation(.easeInOut(duration: Motion.medium)) { index += 1 } }
            } label: {
                Text(isLast ? (review ? "닫기" : "시작하기") : "다음")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.onSolid)
            .background(Palette.lime, in: RoundedRectangle(cornerRadius: Radius.md))
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.lg)
        }
        .background(Palette.bgBase)
    }

    /// 점은 **현재 쪽을 말할 뿐 누르는 자리가 아니다** — 4쪽짜리에서 점을 조작 대상으로
    /// 만들면 44pt 타겟 네 개가 가로로 붙어 오터치가 는다.
    private var indicator: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(pages.indices, id: \.self) { page in
                Capsule()
                    .fill(page == index ? Palette.lime : Palette.surfaceVariant)
                    .frame(width: page == index ? 20 : 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pages.count)쪽 중 \(index + 1)쪽")
    }

    // ── 한 쪽 ───────────────────────────────────────────────

    private func pageContent(_ page: OnboardingPage) -> some View {
        // 큰 글자 설정에서 본문이 화면을 넘는다. 넘치면 스크롤한다.
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                OnboardingArtView(art: page.art)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, Spacing.sm)

                Text(page.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(page.body, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        if page.body.count > 1 {
                            // 🔴 **색만으로 목록을 표시하지 않는다** — 글머리 기호가 함께
                            //    있어야 흑백이나 색각 이상에서도 항목으로 읽힌다.
                            Text("·").foregroundStyle(Palette.lime)
                        }
                        Text(line)
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let note = page.note {
                    Text(note)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Spacing.xs)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
        }
    }
}

/// 온보딩 삽화. **앱에서 실제로 보게 될 것**을 도형으로 옮긴 것이라 그림과 화면이 어긋나지
/// 않는다. 새 에셋을 만들지 않으므로 문구가 바뀌어도 그림이 낡지 않는다.
private struct OnboardingArtView: View {

    let art: OnboardingArt

    private static let height: CGFloat = 160

    var body: some View {
        Group {
            switch art {
            case .symbol: symbol
            case .weekBars: weekBars
            case .calibration: calibration
            case .framing: framing
            }
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)   // 그림은 본문이 말하는 것을 되풀이할 뿐이다
    }

    /// 무너진 자세 → 교정된 체크. 스플래시와 같은 한 방향이다.
    private var symbol: some View {
        ZStack {
            Circle()
                .stroke(Palette.limeContainer, lineWidth: 12)
                .frame(width: 120, height: 120)
            Image(systemName: "checkmark")
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(Palette.lime)
        }
    }

    private var weekBars: some View {
        HStack(alignment: .bottom, spacing: Spacing.sm) {
            ForEach(Array([0.35, 0.0, 0.7, 0.5, 1.0, 0.0, 0.2].enumerated()), id: \.offset) { _, h in
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(h >= 1.0 ? Palette.lime : (h > 0 ? Palette.limeDim : Palette.surfaceVariant))
                    .frame(width: 18, height: max(Self.height * 0.75 * h, 8))
            }
        }
    }

    /// 기준 자세 — 곧게 선 사람과 측정 창.
    private var calibration: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(Palette.lime, style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                .frame(width: 110, height: Self.height - 8)
            VStack(spacing: 4) {
                Circle().fill(Palette.lime).frame(width: 16, height: 16)
                Capsule().fill(Palette.limeDim).frame(width: 6, height: 46)
                HStack(spacing: 14) {
                    Capsule().fill(Palette.limeDim).frame(width: 6, height: 50)
                    Capsule().fill(Palette.limeDim).frame(width: 6, height: 50)
                }
            }
        }
    }

    /// 촬영 구도 — 폰을 세우고 전신이 들어오게.
    private var framing: some View {
        HStack(spacing: Spacing.lg) {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Palette.textMuted, lineWidth: 2)
                .frame(width: 44, height: 80)
                .overlay {
                    Image(systemName: "camera")
                        .font(.system(size: 16))
                        .foregroundStyle(Palette.textMuted)
                }
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(Palette.lime, lineWidth: 2)
                    .frame(width: 84, height: Self.height - 16)
                Image(systemName: "figure.stand")
                    .font(.system(size: 76))
                    .foregroundStyle(Palette.lime)
            }
        }
    }
}
