import PoseEngine
import Storage
import SwiftUI

/// 설정.
///
/// ## 순서는 "찾으러 올 순서"다
/// 자주 바꾸는 항목과 **문제가 생겼을 때 찾게 되는 항목**은 다르다 — "자꾸 지적받는다"고
/// 느낀 사람이 설정을 여는 이유는 기준 완화 하나다. 그래서 그것이 맨 위다.
///
/// ## 설명은 팝업으로 접는다
/// 항목마다 "왜 이 값을 고르나"를 본문에 적었더니 화면이 설명문 덩어리가 됐고 정작
/// 조절기가 밀려났다. **상태는 항상 보이고**(`켜짐`/`기본값이에요`), 이유는 `설명`을
/// 눌렀을 때만 열린다.
///
/// 🔴 **기본값을 저장소에 두지 않는다.** 없으면 nil을 내고 호출부가 자기 기본값을 쓴다 —
/// `0초(바로)`가 유효한 선택지라 "저장 안 함"과 구분돼야 하기 때문이다.
struct SettingsScreen: View {

    let onBack: () -> Void

    /// 🔴 **앱이 소유한 `AppSettings`를 화면이 직접 읽지 않는다** — 그 이유는
    /// `SettingsViewModel`의 주석에 있다. 화면은 자기가 소유한 모델만 읽는다.
    @State private var model = SettingsViewModel()
    @State private var detail: SettingDetail?
    @State private var sheet: Sheet?
    @State private var askResetOnboarding = false
    @State private var askResetCoachMarks = false

    private enum Sheet: Int, Identifiable {
        case onboarding, prep, example, body
        var id: Int { rawValue }
    }

    var body: some View {
        // ⚠ **미해결 — 이 화면에 남은 렌더 artifact.** 스크롤 내용의 **글자만**
        //   헤더 줄에 한 번 더 그려진다(배경은 복제되지 않는다).
        //   좁혀 놓은 조건: **스크롤뷰의 위가 화면 꼭대기가 아니면 난다.**
        //   형제로 둔 헤더·`Color.clear` 한 줄·`safeAreaInset`·`overlay`·시스템
        //   네비게이션 바까지 전부 같은 증상이고, 스크롤뷰만 두면 나지 않는다.
        //   원인이 아닌 것으로 확인: `Stepper`·`Divider`·`if/else` 분기·`.id()`·
        //   `@State` 소유 방식·뷰모델 분리·`LazyVStack`·`.clipped()`·
        //   `scrollEdgeEffectHidden`/`scrollEdgeEffectStyle(.hard)`·접근성 수식어.
        //   → `docs/03` §17
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                    relaxedSection
                    bodySection
                    measurementSection
                    goalSection
                    helpSection
                    developerSection
                }
                .padding(Spacing.md)
            }
        }
        .background(Palette.bgBase)
        .task { await model.loadMetrics() }
        .sheet(item: $detail) { item in
            SettingDetailSheet(detail: item) { detail = nil }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .onboarding:
                // 🔴 **다시 봐도 완료 상태를 바꾸지 않는다** — "지금 보기"는 확인이지
                //    처음 보는 것이 아니다.
                OnboardingScreen(review: true) { sheet = nil }
            case .prep:
                MeasurementPrepSheet(mode: .review) { sheet = nil }
                    .presentationDetents([.large])
            case .example:
                SquatExampleSheet { sheet = nil }
                    .presentationDetents([.large])
            case .body:
                BodyProfileSheet {
                    sheet = nil
                    model.reload()
                }
            }
        }
        .confirmationDialog("앱 사용법을 다시 볼까요?",
                            isPresented: $askResetOnboarding, titleVisibility: .visible) {
            Button("지금 보기") { sheet = .onboarding }
            Button("다음에 켤 때") { model.resetOnboarding() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("지금 바로 보거나, 앱을 껐다 켤 때 처음처럼 다시 보여드릴 수 있어요. "
                 + "목표, 신체 정보, 준비 시간 같은 설정과 지금까지의 기록은 그대로예요.")
        }
        .confirmationDialog("메뉴 안내를 다시 볼까요?",
                            isPresented: $askResetCoachMarks, titleVisibility: .visible) {
            Button("다음에 열 때") { model.resetMenuTutorials() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("화면별 사용법 안내를 각 화면을 열 때 다시 보여드려요. "
                 + "목표, 신체 정보, 준비 시간 같은 설정과 지금까지의 기록은 그대로예요.")
        }
    }

    private var header: some View {
        HStack {
            // 🔴 나가는 자리는 **모든 화면에서 좌상단 아이콘 하나**다.
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: TouchTarget.min, height: TouchTarget.min)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textPrimary)

            Text("설정")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Palette.textPrimary)
            Spacer()
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.sm)
    }

    // ── 자세 기준 ───────────────────────────────────────────

    /// 실제 사용자가 "맞게 하고 있는 것 같은데 계속 주의를 주니까 거부감이 든다"고 했다.
    ///
    /// ⚠ **수치를 화면에 쓰지 않는다** — 0.15는 발목 간격으로 정규화한 무차원값이라
    /// 사용자가 판단에 쓸 수 없고, 보이면 "0.15가 뭔가"를 묻게 된다.
    private var relaxedSection: some View {
        card(title: "자세 기준", detail: .relaxedForm) {
            Toggle(isOn: $model.relaxedForm) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("기준 완화")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                    Text(model.relaxedForm
                         ? "앉은 깊이와 무릎 방향을 넉넉한 기준으로 봐요."
                         : "기본 기준으로 봐요.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Palette.lime)
            .frame(minHeight: TouchTarget.min)

            if model.relaxedForm {
                // 🔴 **지금 적용 중인 세션이 아니라 다음 세션부터**라는 사실을 밝힌다.
                note("운동 중에는 바뀌지 않아요. 다음 운동부터 적용돼요.")
            }
        }
    }

    // ── 내 정보 ─────────────────────────────────────────────

    private var bodySection: some View {
        card(title: "내 정보", detail: .bodyProfile) {
            row("키", value: model.body.heightCm.map { "\(format($0)) cm" })
            row("몸무게", value: model.body.weightKg.map { "\(format($0)) kg" })
            row("나이 (선택)", value: model.body.age.map { "\($0)세" })
            row("성별 (선택)", value: model.body.sex.map { $0 == .male ? "남성" : "여성" })

            note(bodyStatus)

            Button("입력하기") { sheet = .body }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.lime)
                .frame(maxWidth: .infinity, minHeight: TouchTarget.min)
                .overlay(RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(Palette.lime, lineWidth: 1))
        }
    }

    private var bodyStatus: String {
        let input = model.body
        if input.profile != nil { return "열량을 계산할 수 있어요." }
        if input.heightCm == nil && input.weightKg == nil {
            return "지금은 열량을 계산하지 않아요."
        }
        return "둘 다 넣어야 열량을 계산할 수 있어요."
    }

    // ── 측정 ────────────────────────────────────────────────

    private var measurementSection: some View {
        card(title: "측정", detail: .prepSeconds) {
            // 🔴 **`바로`(0초)는 유효한 선택지다.** "저장 안 함"과 구분돼야 해서
            //    저장소는 nil과 0을 다르게 다룬다.
            //
            // ⚠ 시스템 `Stepper`를 쓰지 않는다 — 다크 테마 밖의 색을 들고 온다.
            //   목표 조절기와 같은 ± 버튼이면 충분하다.
            HStack(spacing: Spacing.md) {
                Text("준비 시간")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Text(prepLabel)
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.lime)
                stepButton("minus",
                           enabled: model.effectivePrepSeconds > AppSettings.prepRange.lowerBound) {
                    model.prepSeconds = model.effectivePrepSeconds - 1
                }
                stepButton("plus",
                           enabled: model.effectivePrepSeconds < AppSettings.prepRange.upperBound) {
                    model.prepSeconds = model.effectivePrepSeconds + 1
                }
            }
            .frame(minHeight: TouchTarget.min)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("준비 시간 \(prepLabel)")

            // **상태는 항상 같은 자리에 있고 글자만 바뀐다** — 줄이 생겼다 없어지면
            // 그때마다 아래 내용이 들썩인다.
            HStack {
                Text(model.prepSeconds == nil ? "기본값이에요." : "직접 정한 값이에요.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textMuted)
                Spacer()
                Button("기본값으로") { model.prepSeconds = nil }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(model.prepSeconds == nil
                                     ? Palette.textDisabled : Palette.lime)
                    .disabled(model.prepSeconds == nil)
            }
            .frame(minHeight: TouchTarget.min)
        }
    }

    /// 목표는 홈에서 자주 고치는 값이라 **조절기를 여기 두 번 만들지 않는다.**
    /// 설정에는 지금 값이 무엇인지와 어디서 바꾸는지만 둔다.
    private var goalSection: some View {
        card(title: "하루 목표", detail: nil) {
            HStack {
                Text(model.dailyGoal.map { "\($0)회" } ?? "정하지 않음")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(model.dailyGoal == nil
                                     ? Palette.textMuted : Palette.lime)
                Spacer()
            }
            note("홈의 오늘의 목표 카드에서 바꿀 수 있어요.")
        }
    }

    // ── 도움말 ──────────────────────────────────────────────

    /// 🔴 `앱 사용법`·`메뉴 안내 다시 표시`는 **여는 것이 아니라 완료 상태를 되돌린다.**
    /// 온보딩은 앱을 켤 때 뜨는 자리라 설정에서 "열" 수 없고, 코치마크는 각 화면에 붙어
    /// 있어 여기서 띄울 대상이 없다. 다만 **그 자리에서 바로 볼 수 있는 것**(측정 준비,
    /// 동작 예시)은 바로 보여준다.
    private var helpSection: some View {
        card(title: "도움말", detail: .help) {
            helpRow("앱 사용법", "처음 안내 4쪽을 지금 보거나, 다음에 앱을 켤 때 다시 보여줍니다.") {
                askResetOnboarding = true
            }
            helpRow("측정 전 확인사항", "촬영 환경과 복장 확인 목록을 봅니다.") { sheet = .prep }
            helpRow("스쿼트 동작 예시", "동작 예시를 다시 봅니다.") { sheet = .example }
            helpRow("메뉴 안내 다시 표시", "화면별 사용법 안내를 다음에 각 화면을 열 때 다시 보여줍니다.") {
                askResetCoachMarks = true
            }
        }
    }

    // ── 개발·검증용 ─────────────────────────────────────────

    /// 🔴 **성능 카드는 사용자용 화면에 두지 않는다**(결과 화면에서 뺀 이유와 같다).
    /// 여기 있는 숫자는 사용자가 할 수 있는 일이 없고, 결과 화면에 두면 "내 자세 점수"
    /// 옆에 "내 기기 점수"가 생긴다.
    @ViewBuilder
    private var developerSection: some View {
        card(title: "개발·검증용", detail: nil) {
            if let metrics = model.metrics {
                metricRow("추론 평균", metrics.avgInferenceMs.map { String(format: "%.1f ms", $0) })
                metricRow("추론 p95", metrics.p95InferenceMs.map { String(format: "%.1f ms", $0) },
                          ok: PerformanceTarget.meetsInference(p95Ms: metrics.p95InferenceMs))
                metricRow("분석 FPS", metrics.avgFps.map { String(format: "%.1f", $0) })
                metricRow("버린 프레임", metrics.droppedFrameRatio.map {
                    String(format: "%.1f%%", $0 * 100)
                })
                metricRow("모델 로드", metrics.modelLoadMs.map { "\($0) ms" })
                metricRow("분석 프레임", "\(metrics.analyzedFrameCount)")
                note("마지막 세션 기준. 시뮬레이터 수치는 **기기 성능이 아니다** — "
                     + "호스트 CPU에서 돈 값이다.")
            } else {
                note("아직 측정된 세션이 없어요.")
            }
        }
    }

    private func metricRow(_ title: String, _ value: String?, ok: Bool? = nil) -> some View {
        HStack {
            Text(title).font(.system(size: 14)).foregroundStyle(Palette.textMuted)
            Spacer()
            // 🔴 못 잰 값은 **`—`로 적는다.** 0으로 채우면 "아주 빨랐다"로 읽힌다.
            Text(value ?? "—")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ok == false ? Palette.warning : Palette.textPrimary)
        }
        .frame(minHeight: 28)
    }

    // ── 공통 ────────────────────────────────────────────────

    private func card<Content: View>(
        title: String, detail: SettingDetail?, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                // FR-SET-10 — 항목 옆 설명 버튼으로 "왜 필요한지"를 연다.
                if let detail {
                    Button("설명") { self.detail = detail }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.lime)
                        .frame(minHeight: TouchTarget.min)
                        .accessibilityLabel("\(title) 설명 보기")
                }
            }
            content()
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func row(_ title: String, value: String?) -> some View {
        HStack {
            Text(title).font(.system(size: 15)).foregroundStyle(Palette.textPrimary)
            Spacer()
            Text(value ?? "없음")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(value == nil ? Palette.textMuted : Palette.textPrimary)
        }
        .frame(minHeight: 32)
    }

    private func helpRow(
        _ title: String, _ description: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                    Text(description)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textMuted)
            }
            .frame(minHeight: TouchTarget.min)
        }
        .buttonStyle(.plain)
    }

    private func note(_ text: String) -> some View {
        Text(.init(text))
            .font(.system(size: 13))
            .foregroundStyle(Palette.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var prepLabel: String {
        model.effectivePrepSeconds == 0 ? "바로" : "\(model.effectivePrepSeconds)초"
    }

    private func stepButton(
        _ systemName: String, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .frame(width: TouchTarget.min, height: TouchTarget.min)
                .background(Palette.surfaceVariant, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Palette.textPrimary : Palette.textDisabled)
        .disabled(!enabled)
    }

    private func format(_ value: Float) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
