import PoseEngine
import SwiftUI

/// 하루 목표를 정한다.
///
/// 🔴 **기본값을 미리 채워 두지 않는다** — 처음 여는 사람에게는 제안값(30)을 보여주되,
/// 그 값은 **누르기 전까지 저장되지 않는다.** 화면을 여는 것만으로 목표가 생기면
/// "정하지 않음"이 사라진다.
///
/// 조절 단위가 5인 이유: 1회씩 올리면 30회를 맞추는 데 30번을 눌러야 한다.
struct DailyGoalSheet: View {

    let goal: Int?
    let onSave: (Int?) -> Void
    let onCancel: () -> Void

    @State private var value: Int

    /// 처음 여는 사람에게 보여줄 제안값. **저장된 기본값이 아니다.**
    private static let suggestion = 30

    init(goal: Int?, onSave: @escaping (Int?) -> Void, onCancel: @escaping () -> Void) {
        self.goal = goal
        self.onSave = onSave
        self.onCancel = onCancel
        _value = State(initialValue: goal ?? Self.suggestion)
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Text("하루에 몇 회 할까요?")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Palette.textPrimary)

            HStack(spacing: Spacing.lg) {
                stepButton("minus", enabled: value > DailyGoal.range.lowerBound) {
                    value = DailyGoal.clamped(value - DailyGoal.step)
                }
                Text("\(value)회")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Palette.lime)
                    .frame(minWidth: 120)
                    .contentTransition(.numericText())
                stepButton("plus", enabled: value < DailyGoal.range.upperBound) {
                    value = DailyGoal.clamped(value + DailyGoal.step)
                }
            }

            Button {
                onSave(value)
            } label: {
                Text("저장")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: TouchTarget.min)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.onSolid)
            .background(Palette.lime, in: RoundedRectangle(cornerRadius: Radius.md))

            if goal != nil {
                // 🔴 **되돌릴 길을 준다.** 목표를 정한 뒤 "정하지 않음"으로 돌아갈 수
                //    없으면 진행률이 영원히 화면을 차지한다.
                Button("목표 없애기") { onSave(nil) }
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.textMuted)
                    .frame(minHeight: TouchTarget.min)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.bgBase)
        .presentationBackground(Palette.bgBase)
        .overlay(alignment: .topTrailing) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: TouchTarget.min, height: TouchTarget.min)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textMuted)
        }
    }

    private func stepButton(
        _ systemName: String, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .bold))
                .frame(width: TouchTarget.min, height: TouchTarget.min)
                .background(Palette.surfaceVariant, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Palette.textPrimary : Palette.textDisabled)
        .disabled(!enabled)
    }
}
