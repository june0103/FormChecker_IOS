import SwiftUI

/// 코치마크 한 단계.
struct CoachStep: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
}

/// 강조할 대상의 화면 좌표를 모은다.
///
/// 🔴 **좌표를 상수로 두지 않는다** — 기기·글꼴 크기마다 달라진다. 대상이 자기 위치를
/// 직접 재서 올리고, **대상이 없으면 그 단계는 자동으로 빠진다.**
struct CoachAnchorKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// 이 뷰를 `id` 단계의 강조 대상으로 등록한다.
    func coachAnchor(_ id: String) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: CoachAnchorKey.self,
                                       value: [id: proxy.frame(in: .global)])
            }
        )
    }
}

/// 스크림 + 구멍 + 말풍선 + 입력 차단.
///
/// 라이브러리를 쓰지 않는다 — 이 세 가지면 충분하고, 라이브러리는 **테마 밖 색을 함께
/// 들고 온다.**
struct CoachMarkOverlay: View {

    let steps: [CoachStep]
    let anchors: [String: CGRect]
    @Binding var index: Int
    let onFinish: () -> Void

    private var visible: [CoachStep] { steps.filter { anchors[$0.id] != nil } }

    var body: some View {
        GeometryReader { proxy in
            if index < visible.count, let rect = anchors[visible[index].id] {
                let local = CGRect(x: rect.minX, y: rect.minY - proxy.frame(in: .global).minY,
                                   width: rect.width, height: rect.height)
                ZStack(alignment: .topLeading) {
                    scrim(cutout: local.insetBy(dx: -6, dy: -6))
                    bubble(for: visible[index], near: local, in: proxy.size)
                }
                // 입력 차단 — 뒤에 있는 버튼이 눌리면 안내 순서가 깨진다.
                .contentShape(Rectangle())
                .onTapGesture { advance() }
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: Motion.medium), value: index)
    }

    private func scrim(cutout: CGRect) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.78))
            .reverseMask {
                RoundedRectangle(cornerRadius: Radius.md).frame(
                    width: cutout.width, height: cutout.height
                )
                .position(x: cutout.midX, y: cutout.midY)
            }
    }

    private func bubble(for step: CoachStep, near rect: CGRect, in size: CGSize) -> some View {
        let below = rect.maxY + 140 < size.height
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(step.title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Palette.lime)
            Text(step.body)
                .font(.system(size: 14))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("\(index + 1) / \(visible.count)")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textMuted)
                Spacer()
                Text(index + 1 == visible.count ? "확인" : "다음")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.lime)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: 320, alignment: .leading)
        .background(Palette.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Palette.outline))
        .padding(.horizontal, Spacing.md)
        .offset(y: below ? rect.maxY + Spacing.md : max(Spacing.md, rect.minY - 160))
    }

    private func advance() {
        if index + 1 < visible.count { index += 1 } else { onFinish() }
    }
}

private extension View {
    /// 구멍 뚫린 스크림.
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            Rectangle()
                .overlay(alignment: .topLeading) { mask().blendMode(.destinationOut) }
                .compositingGroup()
        }
    }
}
