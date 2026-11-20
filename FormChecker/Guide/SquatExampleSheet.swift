import AVKit
import SwiftUI

/// 동작 예시.
///
/// 🔴 **정면/측면으로 나누지 않는다** — 예시가 사선 촬영이고, 촬영 방향은 앱이 스스로
/// 판별한다. 영상 위에 관절선·수치를 얹지 않는다. 지금 할 일은 "따라 할 동작"을 보는 것이지
/// 자기 자세를 재는 것이 아니다.
struct SquatExampleSheet: View {

    let onClose: () -> Void

    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: Spacing.md) {
            Text("이렇게 움직여 주세요")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if let player {
                    VideoPlayer(player: player)
                        .disabled(true)        // 재생 컨트롤을 보여주지 않는다
                } else {
                    Color.black
                }
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

            Text("발은 어깨너비로, 발끝은 살짝 바깥으로. 가슴을 들고 앉았다 일어나세요.")
                .font(.system(size: 14))
                .foregroundStyle(Palette.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onClose) {
                Text("알겠어요")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: TouchTarget.min)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.onSolid)
            .background(Palette.lime, in: RoundedRectangle(cornerRadius: Radius.md))
        }
        .padding(Spacing.md)
        .background(Palette.bgBase)
        .onAppear(perform: startLoop)
        .onDisappear { player?.pause() }
    }

    private func startLoop() {
        guard player == nil,
              let url = Bundle.main.url(forResource: "squat_demo", withExtension: "mp4")
        else { return }
        let item = AVPlayerItem(url: url)
        let made = AVPlayer(playerItem: item)
        // 🔴 음소거다. 소리는 rep 신호에만 쓴다 — 예시가 울리면 그 신호가 묻힌다.
        made.isMuted = true
        made.actionAtItemEnd = .none
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { _ in
            made.seek(to: .zero)
            made.play()
        }
        made.play()
        player = made
    }
}
