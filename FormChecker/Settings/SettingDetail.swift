import SwiftUI

/// 설정 항목의 "왜 필요한지".
///
/// 🔴 **본문이 아니라 팝업이다.** 항목마다 이유를 본문에 적었더니 화면이 설명문 덩어리가
/// 되고 정작 조절기가 밀려났다. 상태는 항상 보이고, 이유는 눌렀을 때만 열린다.
///
/// 문구를 화면이 아니라 여기 모아 두는 이유는 온보딩과 같다 — 흩어져 있으면 **무엇이
/// 바뀌었는지 보이지 않는다.**
enum SettingDetail: Int, Identifiable {
    case relaxedForm, bodyProfile, prepSeconds, help

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .relaxedForm: "기준 완화"
        case .bodyProfile: "내 정보"
        case .prepSeconds: "준비 시간"
        case .help: "도움말"
        }
    }

    /// ⚠ **수치를 쓰지 않는다.** 허용폭은 발목 간격으로 정규화한 무차원값이라 사용자가
    /// 판단에 쓸 수 없고, 보이면 "0.15가 뭔가"를 묻게 된다.
    var body: String {
        switch self {
        case .relaxedForm:
            """
            자세를 지적하는 기준을 조금 넉넉하게 잡아요. 자세가 맞는데도 자꾸 지적받는다고 \
            느껴지면 켜 보세요.

            앉은 깊이와 무릎 방향 두 가지에 적용돼요. 깊이는 무릎 높이에 조금 못 미쳐도 \
            넘어가고, 무릎은 발끝에서 조금 벗어나도 넘어가요.

            켜도 확실히 어긋난 자세는 그대로 알려드려요 — 무릎이 안쪽으로 모이는 것도 계속 \
            봐 드리고, 더 깊게 앉는 것은 어차피 문제가 아니라 그대로예요.

            다만 살짝 어긋난 것은 넘어갈 수 있어요. 자세를 정확히 보고 싶을 때는 끄는 편이 \
            맞아요.

            상체 숙임과 뒤꿈치 들림은 이 설정과 무관하게 그대로예요.
            """
        case .bodyProfile:
            """
            키와 몸무게를 넣으면 운동이 끝난 뒤 소모 열량을 대략 알려드려요. 넣지 않으면 \
            열량만 빠지고 나머지는 그대로예요.

            둘 다 필요한 이유는 기초대사량을 구하는 식이 키와 몸무게를 함께 쓰기 때문이에요. \
            하나만 넣으면 계산이 성립하지 않아요.

            나이와 성별은 선택이에요. 넣지 않아도 열량은 계산되고, 30세·남성으로 가정했다는 \
            사실을 홈에서 함께 알려드려요.

            넣은 값은 이 기기에만 저장되고, 칸을 비우면 지워져요.
            """
        case .prepSeconds:
            """
            기준 자세 재기를 누른 뒤 측정이 시작되기까지 기다리는 시간이에요. 버튼을 누른 \
            자리에서 카메라 앞까지 걸어갈 시간입니다.

            삼각대를 앞에 두고 화면에 손이 닿으면 "바로"가 맞고, 방 건너편에 두었으면 10초도 \
            짧아요.

            사람마다 다르지만 한 사람에게는 거의 바뀌지 않는 값이라, 매 운동마다 묻지 않고 \
            여기 둡니다.
            """
        case .help:
            """
            처음에 봤던 안내를 다시 볼 수 있어요.

            앱 사용법은 지금 바로 보거나, 다음에 앱을 켤 때 다시 보게 할 수 있어요.

            메뉴 안내는 각 화면에 붙어 있어서 여기서 띄울 수 없어요 — 다시 보도록 되돌리면 \
            홈·운동·결과·기록을 열 때 나타나요.

            어느 쪽도 목표·신체 정보·준비 시간 같은 설정과 지금까지의 기록은 건드리지 않아요.
            """
        }
    }
}

struct SettingDetailSheet: View {

    let detail: SettingDetail
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text(detail.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                    Text(detail.body)
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.md)
            }

            Button(action: onClose) {
                Text("닫기")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: TouchTarget.min)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.lime)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Palette.lime, lineWidth: 1))
            .padding(Spacing.md)
        }
        .background(Palette.bgBase)
        .presentationBackground(Palette.bgBase)
        .presentationDetents([.medium, .large])
    }
}
