import Storage
import SwiftUI

let weekDayLabels = ["월", "화", "수", "목", "금", "토", "일"]

/// 이번 주 7일 막대그래프. **막대를 누르면 그 날이 선택된다.**
///
/// ## 왜 잔디 칸이 아닌가
/// 기여 그래프식 정사각 칸은 **색 진하기로만** 양을 말한다. 이 앱은 색으로만 상태를
/// 구분하지 않기로 했고, 무엇보다 "몇 회 했나"가 홈에서 가장 궁금한 값이라 높이와 숫자로
/// 함께 보여주는 쪽이 맞다.
///
/// ## 색만으로 달성을 말하지 않는다
/// 목표를 채운 날은 라임 막대 **+ 체크 표시 + 숫자 색**이 함께 바뀐다. 오늘은 **테두리와
/// 굵은 요일 이름**으로 구분한다.
///
/// ## 높이 정규화
/// 기준은 `max(이번 주 최대, 목표, 1)`이다. 목표를 함께 넣는 이유: 목표가 30회인데 최대가
/// 5회인 주에 최대치를 꼭대기로 그리면 **5회가 가득 찬 것처럼 보인다.** 1을 바닥에 두는
/// 것은 0으로 나누는 것을 막기 위함이다.
///
/// 차트 라이브러리를 넣지 않는다 — 막대 7개는 스택으로 충분하고, 의존성이 늘면 테마
/// 토큰 밖의 색이 따라 들어온다.
struct WeekBars: View {

    let days: [DayReps]
    let goal: Int?
    /// 지금 골라 놓은 날. 카드 아래의 하루치 요약이 이 날을 말한다.
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    private static let maxBarHeight: CGFloat = 96
    /// 1회만 해도 막대가 보여야 한다.
    private static let minVisibleBar: CGFloat = 6
    private static let checkSize: CGFloat = 16

    private var scale: Int {
        max(days.map(\.reps).max() ?? 0, goal ?? 0, 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Spacing.xs) {
            ForEach(days) { day in
                column(day)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func column(_ day: DayReps) -> some View {
        let fill = min(max(CGFloat(day.reps) / CGFloat(scale), 0), 1)
        // 0회는 채우지 않는다 — 빈 트랙 자체가 상태다.
        let height = day.reps > 0
            ? max(Self.maxBarHeight * fill, Self.minVisibleBar)
            : 0

        return Button {
            onSelect(day.index)
        } label: {
            VStack(spacing: Spacing.xs) {
                // 달성 표시 자리는 **항상 비워 둔다** — 체크가 있는 날만 높아지면
                // 막대 바닥이 어긋난다.
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.lime)
                    .opacity(day.metGoal ? 1 : 0)
                    .frame(height: Self.checkSize)

                Text("\(day.reps)")
                    .font(.system(size: 12, weight: day.reps > 0 ? .semibold : .regular))
                    .foregroundStyle(day.metGoal ? Palette.lime
                                     : (day.reps > 0 ? Palette.textPrimary : Palette.textDisabled))

                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(Palette.surfaceVariant)
                        .frame(height: Self.maxBarHeight)
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(day.metGoal ? Palette.lime : Palette.limeDim)
                        .frame(height: height)
                }
                .frame(height: Self.maxBarHeight)
                .overlay {
                    if day.isToday {
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .stroke(Palette.textPrimary, lineWidth: 1.5)
                    }
                }

                Text(weekDayLabels[day.index])
                    .font(.system(size: 12, weight: day.isToday ? .bold : .regular))
                    .foregroundStyle(day.isToday || day.index == selectedIndex
                                     ? Palette.textPrimary : Palette.textMuted)
            }
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity)
            // 고른 날은 기둥 전체가 옅은 판 위에 올라간다. 오늘 표시(테두리)와 겹쳐도
            // 서로 다른 신호로 읽히도록 자리를 나눴다 — 판은 기둥 전체, 테두리는 막대다.
            //
            // ⚠ 판 색을 카드와 같은 `surfaceCard`로 두면 **아무것도 보이지 않는다**
            //   (카드 위에 올라가는 판이라 같은 색이면 사라진다). 고른 날은 요일 이름도
            //   함께 밝아진다 — 판 하나만으로는 작은 화면에서 놓치기 쉽다.
            .background(day.index == selectedIndex ? Palette.outline : .clear,
                        in: RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
        // 막대는 그림이라 요일·횟수를 **하나의 문장으로** 읽어준다.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(day.isToday ? "오늘 " : "")\(weekDayLabels[day.index])요일 \(day.reps)회"
            + (day.metGoal ? ", 목표 달성" : "")
        )
        .accessibilityAddTraits(.isButton)
    }
}
