import PoseEngine
import Storage
import SwiftUI

/// 홈 (대시보드).
///
/// Android 순서를 그대로 쓴다:
/// **오늘의 목표 → 운동 시작 → 이번 주 7일 막대 → 주간 합계·추정 열량 → 기록 → 내 정보**
///
/// 🔴 **홈 문구에 종목 이름을 쓰지 않는다** — `운동 시작`, `이번 주 운동`. 종목이 늘어날
/// 예정이라 이름은 운동을 고르는 자리가 생길 때 붙는다.
struct HomeScreen: View {

    let onStartWorkout: () -> Void
    let onOpenHistory: () -> Void
    let onOpenSettings: () -> Void

    @State private var model = HomeViewModel()
    @State private var settings = AppSettings.shared
    /// 그래프에서 고른 날. nil이면 오늘이다 — **날짜가 넘어가도 "오늘"을 계속 가리킨다.**
    @State private var pickedIndex: Int?
    /// 🔴 **시트 두 개를 각각 `isPresented`로 띄우지 않는다** — 같은 뷰에 `.sheet`를
    /// 두 번 붙이면 SwiftUI가 하나만 살린다(먼저 붙은 쪽). 나머지 버튼은 눌러도 아무
    /// 일이 일어나지 않는다. 열 수 있는 것이 둘 이상이면 **하나의 `item`**으로 모은다.
    @State private var sheet: Sheet?

    private enum Sheet: Int, Identifiable {
        case goal, body
        /// 첫 운동 전. 확인하면 완료로 저장하고 운동으로 간다.
        case prepBeforeWorkout
        /// `측정 팁`에서 다시 열었다. 운동으로 보내지 않는다.
        case prepReview
        var id: Int { rawValue }
    }

    private var state: HomeState { model.state }
    private var selectedIndex: Int { pickedIndex ?? state.todayIndex }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                title
                goalCard
                startButton
                weekCard
                calorieCard
                historyRow
                settingsRow
            }
            .padding(Spacing.md)
        }
        .background(Palette.bgBase)
        // 🔴 화면에 들어올 때마다 다시 읽는다 — 운동을 마치고 돌아온 직후가 가장
        //    자주 보는 순간이고, 자정을 넘겼으면 "오늘" 칸도 옮겨가야 한다.
        .task { await model.refresh() }
        .sheet(item: $sheet) { which in
            switch which {
            case .goal:
                DailyGoalSheet(goal: state.dailyGoal) { newValue in
                    model.setDailyGoal(newValue)
                    sheet = nil
                } onCancel: {
                    sheet = nil
                }
                .presentationDetents([.height(320)])
            case .body:
                BodyProfileSheet {
                    model.bodyChanged()
                    sheet = nil
                }
            case .prepBeforeWorkout:
                MeasurementPrepSheet(mode: .beforeFirstWorkout) {
                    sheet = nil
                } onReady: {
                    // 🔴 `준비됐어요`를 눌렀을 때만 완료로 친다. **취소는 완료가 아니다.**
                    settings.markSeen(.measurementPrep)
                    sheet = nil
                    onStartWorkout()
                }
                .presentationDetents([.large])
            case .prepReview:
                MeasurementPrepSheet(mode: .review) { sheet = nil }
                    .presentationDetents([.large])
            }
        }
    }

    private var title: some View {
        Text("폼체커")
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(Palette.textPrimary)
    }

    // ── 오늘의 목표 ─────────────────────────────────────────

    /// 🔴 **목표를 정하지 않은 것이 "오늘 아무것도 안 했다"는 뜻은 아니다.**
    /// 빈 상태에서도 오늘 센 횟수를 먼저 보여준다.
    ///
    /// 초과분을 감추지 않는다 — `35 / 30회`는 그대로 두고 **진행 바만 100%에서 멈춘다.**
    private var goalCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("오늘의 목표")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                if state.dailyGoal != nil {
                    Button("목표 수정") { sheet = .goal }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.lime)
                }
            }

            if let error = state.loadError {
                Text(error).font(.system(size: 14)).foregroundStyle(Palette.danger)
            } else if state.loading {
                Text("불러오는 중…").font(.system(size: 14)).foregroundStyle(Palette.textMuted)
            } else if let progress = state.goalProgress {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(progress.done)")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(progress.reached ? Palette.lime : Palette.textPrimary)
                    Text(" / \(progress.goal)회")
                        .font(.system(size: 17))
                        .foregroundStyle(Palette.textMuted)
                }
                progressBar(progress)
                Text(goalMessage(progress))
                    .font(.system(size: 14))
                    .foregroundStyle(progress.reached ? Palette.lime : Palette.textMuted)
            } else {
                Text("오늘 \(state.todayReps)회")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                Text("하루에 몇 회 할지 정하면 진행률과 남은 횟수를 보여드려요.")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Button { sheet = .goal } label: {
                    Text("목표 정하기")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: TouchTarget.min)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.lime)
                .overlay(RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(Palette.lime, lineWidth: 1))
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func goalMessage(_ progress: GoalProgress) -> String {
        if progress.over > 0 { return "목표를 \(progress.over)회 넘겼어요" }
        if progress.reached { return "오늘 목표를 달성했어요" }
        return "목표까지 \(progress.remaining)회 남았어요"
    }

    private func progressBar(_ progress: GoalProgress) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.surfaceVariant)
                Capsule().fill(Palette.lime)
                    .frame(width: geometry.size.width * CGFloat(progress.displayRatio))
            }
        }
        .frame(height: 8)
        .accessibilityLabel("진행률 \(progress.percent)퍼센트")
    }

    // ── 운동 시작 ───────────────────────────────────────────

    private var startButton: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Button {
                // 🔴 첫 운동 전에는 측정 준비 안내를 **먼저** 본다. 바로 보내면
                //    안내를 건너뛴 것이 되고, 그 사람은 폰을 세운 뒤에야 무엇이
                //    필요한지 알게 된다.
                if settings.hasSeen(.measurementPrep) { onStartWorkout() }
                else { sheet = .prepBeforeWorkout }
            } label: {
                Text("운동 시작")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.onSolid)
            .background(Palette.lime, in: RoundedRectangle(cornerRadius: Radius.md))

            // 안내를 한 번 본 뒤에도 **핵심 한 줄은 남긴다.** 촬영 준비는 매번 필요한
            // 것이지 한 번 읽고 끝나는 것이 아니다.
            HStack(alignment: .firstTextBaseline) {
                Text(Onboarding.prepShortHint)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.info)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Spacing.sm)
                Button("측정 팁") { sheet = .prepReview }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.lime)
                    .frame(minHeight: TouchTarget.min)
            }
        }
    }

    // ── 이번 주 ─────────────────────────────────────────────

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("이번 주 운동")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)

            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text("총 \(state.weekTotalReps)회")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Palette.lime)
                // "운동한 날"은 한 번이라도 센 날이다. 최소 시간·최소 횟수 기준을
                // 새로 만들지 않는다.
                Text("\(state.activeDays)일 운동")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.textMuted)
            }

            if state.loading {
                Text("불러오는 중…").font(.system(size: 14)).foregroundStyle(Palette.textMuted)
            } else {
                WeekBars(days: state.week, goal: state.dailyGoal,
                         selectedIndex: selectedIndex) { pickedIndex = $0 }

                if !state.hasAnyRecord {
                    Text("아직 기록이 없어요. 첫 운동을 시작해볼까요?")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textMuted)
                } else if let goal = state.dailyGoal {
                    // 🔴 지난 날도 **현재 목표 기준**으로 표시하고 그 사실을 밝힌다.
                    Text("지난 날들도 지금 목표(\(goal)회) 기준으로 표시해요.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.lg))
    }

    // ── 추정 소모 열량 ──────────────────────────────────────

    /// 주간 합계만 있으면 "오늘 얼마나 태웠나"를 알 수 없다. 기본은 **오늘**이고,
    /// 그래프에서 다른 날을 고르면 그 날을 말한다.
    ///
    /// 🔴 **0 kcal은 "안 태웠다"는 뜻이고 여기서 말할 것은 "모른다"다.** 신체 정보가
    /// 없으면 숫자 대신 설정으로 가는 길을 준다. 다만 **기록이 없는 날의 0회는 사실**이라
    /// 그때는 "이 날은 기록이 없어요"라고 말한다.
    private var calorieCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("추정 소모 열량")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)

            Text("\(selectedDayName) \(state.week.indices.contains(selectedIndex) ? state.week[selectedIndex].reps : 0)회")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.textPrimary)

            if state.calories == nil {
                Text("신체 정보를 입력하면 예상 소모 열량을 확인할 수 있어요.")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Button("내 정보 입력하기") { sheet = .body }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.lime)
                    .frame(minHeight: TouchTarget.min)
            } else if state.week.indices.contains(selectedIndex),
                      state.week[selectedIndex].reps == 0 {
                Text("이 날은 기록이 없어요.")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.textMuted)
            } else if let calories = state.calories, let dayKcal = state.calories(on: selectedIndex) {
                Text("약 \(Int(dayKcal.rounded())) kcal 소모")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Palette.lime)
                // 🔴 가정한 것이 있으면 **그 사실을 밝힌다.**
                Text(calories.exact
                     ? "몸무게와 키로 계산한 어림값이에요."
                     : "나이·성별이 없어 기본값으로 어림했어요. 내 정보에 넣으면 더 정확해져요.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Divider().overlay(Palette.outline)
                Text("이번 주 약 \(Int(calories.kcal.rounded())) kcal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var selectedDayName: String {
        selectedIndex == state.todayIndex
            ? "오늘"
            : "\(weekDayLabels.indices.contains(selectedIndex) ? weekDayLabels[selectedIndex] : "")요일"
    }

    // ── 기록 · 내 정보 ──────────────────────────────────────

    private var historyRow: some View {
        navigationRow("기록 보기", systemImage: "list.bullet.rectangle", action: onOpenHistory)
    }

    /// 내 정보는 설정 안으로 들어갔다 — 홈에 입구를 둘로 두면 같은 값을 고치는 자리가
    /// 둘이 되고, 설정에 무엇이 있는지 알 수 없게 된다. 열량 카드의 `내 정보 입력하기`는
    /// **그 자리에서 바로 고치는 길**이라 남긴다.
    private var settingsRow: some View {
        navigationRow("설정", systemImage: "gearshape", action: onOpenSettings)
    }

    private func navigationRow(
        _ title: String, systemImage: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 15, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Palette.textPrimary)
            .padding(Spacing.md)
            .frame(minHeight: TouchTarget.min)
            .background(Palette.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
    }
}
