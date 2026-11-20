import SwiftUI

/// 이 안내를 어떤 맥락에서 열었나. 버튼과 **뒷일**이 달라진다.
enum PrepMode: Int, Identifiable {
    /// 첫 운동을 시작하려던 참. 확인하면 완료로 저장하고 운동 화면으로 간다.
    case beforeFirstWorkout
    /// 홈의 `측정 팁`에서 다시 열었다. **운동을 자동으로 시작하지 않는다.**
    case review

    var id: Int { rawValue }
}

/// 카메라 앞에 서기 전에 확인할 것들.
///
/// ## 왜 운동 화면이 아니라 그 앞인가
/// 이 안내는 **폰을 세우기 전에** 읽어야 쓸모가 있다. 카메라 화면에 들어간 뒤에는 이미
/// 자리를 잡은 뒤이고, 그 거리에서는 글이 읽히지도 않는다.
///
/// ## 확인해야 넘어간다 — 다만 강요하지 않는다
/// `준비됐어요`를 눌렀을 때만 완료로 저장하고 운동으로 넘어간다. 닫거나
/// `다음에 운동할게요`를 고르면 홈에 그대로 남고 **완료로 치지 않는다** —
/// 읽지 않은 안내를 읽은 것으로 만들지 않는다.
struct MeasurementPrepSheet: View {

    let mode: PrepMode
    let onDismiss: () -> Void
    var onReady: () -> Void = {}

    /// 두 번 눌러 운동 화면이 두 번 열리는 것을 막는다 — 시트가 닫히는 동안에도
    /// 버튼은 잠깐 살아 있다.
    @State private var starting = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("측정 전, 이것만 확인해 주세요")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.bottom, Spacing.sm)

                    ForEach(Onboarding.prepChecklist, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                            // 색만으로 목록임을 표시하지 않는다.
                            Text("·").foregroundStyle(Palette.lime)
                            Text(line)
                                .font(.system(size: 15))
                                .foregroundStyle(Palette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Text(Onboarding.clothingNote)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.info)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Spacing.sm)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.md)
            }

            // 작은 화면·큰 글자에서도 버튼이 잘리지 않게 스크롤 밖에 고정한다.
            VStack(spacing: Spacing.sm) {
                switch mode {
                case .beforeFirstWorkout:
                    Button {
                        guard !starting else { return }
                        starting = true
                        onReady()
                    } label: {
                        Text("준비됐어요")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.onSolid)
                    .background(starting ? Palette.limeDim : Palette.lime,
                                in: RoundedRectangle(cornerRadius: Radius.md))
                    .disabled(starting)

                    Button("다음에 운동할게요", action: onDismiss)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.textMuted)
                        .frame(maxWidth: .infinity, minHeight: TouchTarget.min)

                case .review:
                    // 다시 보기에서는 **운동으로 가는 길을 주지 않는다** — 확인만 하러 온
                    // 사람을 카메라 화면으로 밀어내지 않는다.
                    Button(action: onDismiss) {
                        Text("확인")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: TouchTarget.min)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.lime)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(Palette.lime, lineWidth: 1))
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.md)
        }
        .background(Palette.bgBase)
        .presentationBackground(Palette.bgBase)
    }
}
