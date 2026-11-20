import SwiftUI

/// 인앱 스플래시 — 시스템 런치 화면이 사라진 **직후**에 재생하는 관절 교정 모션.
///
/// ## 무엇을 보여주는가
/// `어긋난 자세(오렌지) → 관절 정렬 → 라임 체크 완성`. 앱이 하는 일 자체가 한 장면으로
/// 요약된 것이고, 심볼이 어디서 왔는지를 말한다.
///
/// 🔴 **오렌지는 시작 상태에만 쓴다**(FR-SPL-04). 정렬이 끝난 최종 상태와 성공은
/// 라임이다 — 앱 안에서 경고가 "고쳐야 할 것", 라임이 "된 것"인 규칙과 같다.
///
/// 🔴 **정지 로고를 먼저 띄우지 않는다**(FR-SPL-03). 완성된 체크가 떴다가 모션이
/// 무너진 자세에서 다시 시작하면 순서가 거꾸로 읽힌다.
///
/// ## 왜 시스템 런치 화면과 나눠 맡는가
/// 시스템 런치 화면은 **배경색만** 그린다(움직이지 않는다). 두 층의 배경색이 같아서
/// (`Assets.xcassets/BgBase` == `Palette.bgBase`) 갈아타는 순간이 보이지 않는다.
///
/// ## 여기서 무거운 일을 하지 않는다
/// 모델은 `ModelPreloader`가 **전용 큐에서** 읽는다. 이 화면은 시작 신호만 보내고
/// 결과를 기다리지 않는다 — 기다리면 느린 기기에서 스플래시가 길어진다.
struct SplashScreen: View {

    /// 모션이 끝나면 한 번만 불린다. **갈 곳을 함께 넘긴다** — 홈을 한 프레임 그린 뒤
    /// 온보딩이 덮는 것을 막는다(FR-SPL-06).
    let onFinished: (_ needsOnboarding: Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var alignment: CGFloat = 0
    @State private var pulse: CGFloat = 1
    @State private var finished = false

    private static let symbolSize: CGFloat = 184
    /// 첫 프레임이 그려지고 눈이 따라오기까지의 여유.
    private static let startDelay: Duration = .milliseconds(120)
    private static let alignDuration: Double = 0.64
    private static let pulseDuration: Double = 0.09
    /// 완성된 체크를 읽을 시간. 이만큼은 넘어가지 않는다.
    private static let finalHold: Duration = .milliseconds(240)

    var body: some View {
        VStack(spacing: 0) {
            JointCheckMotion(progress: alignment, scale: pulse)
                .frame(width: Self.symbolSize, height: Self.symbolSize)
                // 그림만 있는 장면이라 이름을 붙인다. 로고 자체가 화면의 내용이다.
                .accessibilityElement()
                .accessibilityLabel("폼체커")

            Text("FORMCHECKER")
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(Palette.textPrimary)
            Text("바른 움직임의 시작")
                .font(.system(size: 13))
                .foregroundStyle(Palette.textMuted)
                .padding(.top, Spacing.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bgBase)
        .task { await play() }
    }

    private func play() async {
        guard !finished else { return }
        finished = true

        // 🔴 모델 읽기는 여기서 시작하고 **기다리지 않는다**(FR-SPL-05).
        ModelPreloader.shared.start()

        // 🔴 갈 곳은 모션이 도는 동안 정한다. iOS는 `UserDefaults`를 동기로 읽으므로
        //    Android처럼 "아직 못 읽었다"를 기다릴 필요가 없다 — 그쪽은 DataStore가
        //    Flow라서 `ready` 게이트가 필요했다(docs/03 §17).
        let needsOnboarding = !AppSettings.shared.hasSeen(.onboarding)

        if reduceMotion {
            // 접근성: 애니메이션을 끈 기기에서는 교정 모션을 생략하고 최종 상태만
            // 보여준다. 그래도 한 박자는 머문다 — 뜨자마자 사라지면 그것대로 깜빡임이다.
            alignment = 1
            try? await Task.sleep(for: Self.finalHold)
        } else {
            try? await Task.sleep(for: Self.startDelay)
            withAnimation(.timingCurve(0.2, 0, 0, 1, duration: Self.alignDuration)) {
                alignment = 1
            }
            try? await Task.sleep(for: .seconds(Self.alignDuration))

            // 정렬이 맞은 순간의 짧은 확인 신호. rep이 인정될 때 숫자가 뛰는 것과
            // 같은 자리의 표현이다.
            withAnimation(.easeOut(duration: Self.pulseDuration)) { pulse = 1.15 }
            try? await Task.sleep(for: .seconds(Self.pulseDuration))
            withAnimation(.easeIn(duration: Self.pulseDuration)) { pulse = 1 }
            try? await Task.sleep(for: .seconds(Self.pulseDuration))

            try? await Task.sleep(for: Self.finalHold)
        }

        onFinished(needsOnboarding)
    }
}

/// 관절점 3개가 흐트러진 자리에서 체크 모양으로 옮겨 붙는 장면.
///
/// 🔴 **`Animatable`을 붙여야 실제로 움직인다.** `Canvas`는 그리기 클로저일 뿐이라
/// 값을 그냥 넘기면 SwiftUI가 중간값으로 다시 그리지 않고 **끝 상태로 건너뛴다** —
/// 그러면 사용자는 완성된 체크만 보게 되고, "무너진 자세에서 교정된다"는 장면
/// 자체가 사라진다(FR-SPL-03이 막으려던 바로 그 그림이다).
private struct JointCheckMotion: View, @MainActor Animatable {

    var progress: CGFloat
    var scale: CGFloat

    nonisolated var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, scale) }
        set {
            progress = newValue.first
            scale = newValue.second
        }
    }

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            // 시작: 무너진 자세(무릎이 안으로 말리고 상체가 앞으로 쏠린 배치).
            let start = [
                CGPoint(x: w * 0.30, y: h * 0.27),
                CGPoint(x: w * 0.58, y: h * 0.49),
                CGPoint(x: w * 0.42, y: h * 0.75),
            ]
            // 끝: 체크 모양의 관절점 3개.
            let end = [
                CGPoint(x: w * 0.24, y: h * 0.56),
                CGPoint(x: w * 0.45, y: h * 0.69),
                CGPoint(x: w * 0.80, y: h * 0.31),
            ]
            let points = zip(start, end).map { from, to in
                CGPoint(x: from.x + (to.x - from.x) * progress,
                        y: from.y + (to.y - from.y) * progress)
            }

            // 🔴 색은 정렬이 **절반 넘게 진행된 뒤부터** 넘어간다. 시작하자마자 라임이
            //    되면 "고쳤다"는 장면이 아니라 그냥 색이 변하는 장면이 된다.
            let resolved = min(max((progress - 0.42) / 0.58, 0), 1)
            let jointColor = Color.mix(Palette.warning, Palette.lime, resolved)
            let guideAlpha = min(max(1 - progress, 0), 1)
            let stroke = 11 * scale
            let radius = 15 * scale

            // 기준선. 정렬이 끝나면 사라진다.
            var guide = Path()
            guide.move(to: CGPoint(x: w * 0.5, y: h * 0.12))
            guide.addLine(to: CGPoint(x: w * 0.5, y: h * 0.86))
            context.stroke(
                guide,
                with: .color(Palette.outline.opacity(guideAlpha * 0.9)),
                style: StrokeStyle(lineWidth: 2, dash: [10, 10])
            )

            var bones = Path()
            bones.move(to: points[0])
            bones.addLine(to: points[1])
            bones.addLine(to: points[2])
            context.stroke(bones, with: .color(jointColor),
                           style: StrokeStyle(lineWidth: stroke, lineCap: .round,
                                              lineJoin: .round))

            for (index, point) in points.enumerated() {
                let r = index == 1 ? radius * 0.9 : radius
                let rect = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(jointColor))
            }
        }
    }
}

extension Color {
    /// 두 색을 RGB에서 섞는다. `Palette`의 색이 전부 sRGB 리터럴이라 성분으로 바로 섞는다.
    static func mix(_ from: Color, _ to: Color, _ t: CGFloat) -> Color {
        let a = from.resolvedComponents
        let b = to.resolvedComponents
        let clamped = min(max(t, 0), 1)
        return Color(
            .sRGB,
            red: a.0 + (b.0 - a.0) * clamped,
            green: a.1 + (b.1 - a.1) * clamped,
            blue: a.2 + (b.2 - a.2) * clamped,
            opacity: 1
        )
    }

    private var resolvedComponents: (Double, Double, Double) {
        let components = UIColor(self).cgColor.components ?? [0, 0, 0]
        guard components.count >= 3 else {
            let gray = Double(components.first ?? 0)
            return (gray, gray, gray)
        }
        return (Double(components[0]), Double(components[1]), Double(components[2]))
    }
}
