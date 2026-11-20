import PoseEngine
import SwiftUI

/// 운동 화면.
///
/// 🔴 **프리뷰는 화면 폭 전부 · 3:4 · 상단 고정이고 이게 천장이다.** 3:4는 모델이 정한
/// 값이다 — RTMPose 입력이 192×256이라 letterbox 패딩이 0이고, 16:9로 바꾸면 가로를 75%만
/// 쓰며 정면 판정(전부 수평 측정)의 근거가 흔들린다. 프리뷰 **아래는 스크롤**이다.
///
/// ## 안내 순서가 겹치지 않게 화면이 명시적으로 막는다
/// `권한 → 동작 예시 → 코치마크 → (사용자가 직접) 기준 자세`
/// **측정·카운팅 중에는 코치마크를 띄우지 않는다.**
struct WorkoutScreen: View {

    /// 운동 화면을 닫는다. **저장은 여기서 하지 않는다** — 저장할지 말지는 아래에서
    /// 이미 갈라졌고, 이 닫힘은 결과를 본 뒤든 0회로 나가든 똑같이 홈으로 돌려보낸다.
    let onClose: () -> Void

    @State private var model = WorkoutViewModel()
    @State private var settings = AppSettings.shared
    @State private var repPulse = false

    @State private var showExample = false
    @State private var coachIndex = 0
    @State private var showCoachMarks = false
    @State private var anchors: [String: CGRect] = [:]
    @State private var summary: SessionRef?
    /// 🔴 **확인 대화를 각각 `isPresented`로 띄우지 않는다** — 같은 뷰에
    /// `.confirmationDialog`를 두 번 붙이면 SwiftUI가 하나만 살린다. 둘 다 "나가기"를
    /// 묻는 자리라, 하나가 조용히 죽으면 **나가는 길이 막힌다.**
    @State private var ask: ExitAsk?

    private enum ExitAsk: Int, Identifiable {
        /// 한 번도 세지 못한 채 `운동 종료`를 눌렀다.
        case emptyFinish
        /// 센 것이 있는데 저장하지 않고 나가려 한다.
        case leaveWithoutSaving
        var id: Int { rawValue }

        var title: String {
            switch self {
            case .emptyFinish: "아직 한 번도 세지 않았어요"
            case .leaveWithoutSaving: "운동을 그만둘까요?"
            }
        }
    }

    private static let coachSteps = [
        CoachStep(id: "startCalibration", title: "먼저 기준 자세를 재요",
                  body: "몇 걸음 떨어져 곧게 서면 앱이 다리 길이와 촬영 방향을 확인해요."),
        CoachStep(id: "counter", title: "그 뒤부터 횟수를 세요",
                  body: "기준 자세를 재기 전에는 세지 않아요. 왜 안 세는지는 숫자 아래에 나와요."),
        CoachStep(id: "example", title: "동작이 헷갈리면 여기서",
                  body: "따라 할 동작을 언제든 다시 볼 수 있어요."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            preview
            ScrollView { controls }
        }
        .background(Palette.bgBase)
        .onPreferenceChange(CoachAnchorKey.self) { anchors = $0 }
        .overlay {
            if showCoachMarks {
                CoachMarkOverlay(steps: Self.coachSteps, anchors: anchors,
                                 index: $coachIndex) {
                    showCoachMarks = false
                    settings.markSeen(.workoutCoachMarks)
                }
            }
        }
        .fullScreenCover(item: $summary) { ref in
            // 결과를 닫으면 운동 화면도 함께 닫힌다 — 끝낸 세션으로 되돌아갈 자리가 없다.
            SessionSummaryScreen(sessionId: ref.id) {
                summary = nil
                onClose()
            }
        }
        // 🔴 `운동 종료`를 누른 사람은 **기록이 남는다고 기대한다.** 0회는 저장하지
        //    않으므로 아무 말 없이 홈으로 보내면 "종료했는데 기록에 없다"가 된다.
        //    무엇이 일어나는지 말하고 되돌아갈 길을 함께 준다.
        //
        // 🔴 나가기 쪽은 **세션을 저장하지 않는다.** 화면 모서리는 제스처 중에 실수로
        //    닿기 쉬운 자리라, 한 번의 오터치로 방금 한 운동이 사라질 수 있다.
        //    "저장하고 나가기"를 넣지 않는 이유: 그건 이미 `운동 종료`다. 선택지를
        //    셋으로 늘리면 급할 때 잘못 누른다.
        .confirmationDialog(ask?.title ?? "", isPresented: askBinding,
                            titleVisibility: .visible, presenting: ask) { which in
            Button("계속하기", role: .cancel) {}
            Button(which == .emptyFinish ? "나가기" : "저장 안 하고 나가기",
                   role: .destructive) { onClose() }
        } message: { which in
            switch which {
            case .emptyFinish:
                Text("기록으로 남길 동작이 없어서 저장하지 않아요. 계속하시겠어요?")
            case .leaveWithoutSaving:
                Text("지금까지 센 \(model.snapshot.repCount)번은 저장되지 않아요. "
                     + "기록을 남기려면 '운동 종료'를 눌러 주세요.")
            }
        }
        .sheet(isPresented: $showExample) {
            SquatExampleSheet {
                showExample = false
                settings.markSeen(.squatExample)
                startCoachMarksIfNeeded()
            }
            .presentationDetents([.large])
        }
        .task {
            await model.start()
            // 권한·엔진이 준비된 뒤에 안내를 시작한다.
            if !settings.hasSeen(.squatExample) {
                showExample = true
            } else {
                startCoachMarksIfNeeded()
            }
        }
        .onDisappear { model.stop() }
        .onChange(of: model.snapshot.repCount) { _, _ in
            withAnimation(.easeOut(duration: Motion.repPulse)) { repPulse = true }
            withAnimation(.easeIn(duration: Motion.repPulse).delay(Motion.repPulse)) {
                repPulse = false
            }
        }
    }

    /// `confirmationDialog(_:isPresented:presenting:)`는 `item` 형태가 없어서
    /// 하나의 상태를 Bool로 비춰 준다.
    private var askBinding: Binding<Bool> {
        Binding(get: { ask != nil }, set: { if !$0 { ask = nil } })
    }

    private func startCoachMarksIfNeeded() {
        // 측정·카운팅 중에는 띄우지 않는다.
        guard !settings.hasSeen(.workoutCoachMarks),
              model.snapshot.stage == .none else { return }
        coachIndex = 0
        showCoachMarks = true
    }

    // ── 프리뷰 + HUD ────────────────────────────────────────

    private var preview: some View {
        ZStack {
            Color.black
            if model.usingCamera, let camera = model.cameraSource {
                CameraPreviewView(session: camera.session)
            } else if let image = model.previewImage {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
            }
            // 🔴 추론은 반전 없이 한다. 반전은 **그릴 때만**.
            SkeletonOverlay(pose: model.snapshot.pose, mirrored: model.mirrorPreview)
            hud
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var hud: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                // 🔴 나가는 자리는 **모든 화면에서 좌상단 아이콘 하나**다.
                hudButton("chevron.left") {
                    if model.snapshot.repCount > 0 { ask = .leaveWithoutSaving }
                    else { onClose() }
                }

                Spacer()

                Text(model.snapshot.cameraAngle == .front ? "앞에서" : "옆에서")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Palette.surfaceCard.opacity(0.8), in: Capsule())
                    .foregroundStyle(Palette.textMuted)
                    .padding(.top, Spacing.sm)

                Spacer()

                HStack(spacing: 0) {
                    // ⚠ 동작 예시는 **HUD 우상단**이다. 하단 컨트롤 줄에 넣지 않는다 —
                    //   거기는 지금 할 일만 두는 자리다.
                    hudButton("play.rectangle") { showExample = true }
                        .coachAnchor("example")
                    if model.usingCamera {
                        hudButton("arrow.triangle.2.circlepath.camera") { model.toggleCamera() }
                    }
                }
            }
            .padding(.horizontal, Spacing.sm)

            Spacer()
            counter
            Spacer()
            feedbackStack
        }
    }

    private func hudButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: TouchTarget.min, height: TouchTarget.min)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.textPrimary)
        .shadow(color: .black.opacity(0.6), radius: 4)
    }

    private var counter: some View {
        VStack(spacing: Spacing.xs) {
            Text("\(model.snapshot.repCount)")
                .font(.repCounter(digits: String(model.snapshot.repCount).count))
                .foregroundStyle(Palette.lime)
                .scaleEffect(repPulse ? 1.15 : 1.0)
                .shadow(color: .black.opacity(0.6), radius: 8)
                .coachAnchor("counter")

            // 🔴 **막는 대신 왜 안 세는지 숫자 바로 아래에 알린다.**
            if let reason = FeedbackLabels.notCounting(
                stage: model.snapshot.stage,
                readyIssue: model.snapshot.readyIssues.first
            ) {
                Text(reason)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(Palette.infoContainer.opacity(0.92), in: Capsule())
                    .padding(.horizontal, Spacing.md)
            }
        }
    }

    /// 🔴 정렬은 **도착 순(새로 뜬 것이 맨 위)** — 우선순위 순이 아니다.
    private var feedbackStack: some View {
        VStack(spacing: Spacing.xs) {
            ForEach(model.snapshot.heldWarnings, id: \.warning) { held in
                Label {
                    Text(FeedbackLabels.instruction(held.warning, side: held.side))
                        .font(.system(size: 15, weight: .semibold))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(Palette.warning)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.warningContainer.opacity(0.95), in:
                                RoundedRectangle(cornerRadius: Radius.md))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.sm)
        .animation(.easeInOut(duration: Motion.medium), value: model.snapshot.heldWarnings.count)
    }

    // ── 프리뷰 아래 ─────────────────────────────────────────

    private var controls: some View {
        VStack(spacing: Spacing.md) {
            if let error = model.engineError {
                banner(error, color: Palette.danger, container: Palette.dangerContainer,
                       icon: "xmark.octagon.fill")
            }
            if model.cameraDenied {
                banner("카메라를 쓸 수 없어요 — 설정에서 켜 주세요",
                       color: Palette.info, container: Palette.infoContainer,
                       icon: "info.circle.fill")
            }

            statusRow

            // 🔴 하단 컨트롤 줄에는 **지금 할 일만** 둔다.
            Button {
                model.beginCalibration(prepSeconds: settings.effectivePrepSeconds)
            } label: {
                Text(buttonTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: TouchTarget.min)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.onSolid)
            .background(model.engineReady ? Palette.lime : Palette.textDisabled,
                        in: RoundedRectangle(cornerRadius: Radius.md))
            .disabled(!model.engineReady)
            .coachAnchor("startCalibration")

            Button {
                // 🔴 **0회로 끝낸 세션은 저장하지 않는다** — 기록이 아니라 잘못 누른 흔적이다.
                //    막지 않고 묻는다.
                if model.canSave {
                    if let id = model.finishSession() { summary = SessionRef(id: id) }
                } else {
                    ask = .emptyFinish
                }
            } label: {
                Text("운동 종료")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: TouchTarget.min)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.lime)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Palette.lime, lineWidth: 1))

            diagnostics
        }
        .padding(Spacing.md)
    }

    private var buttonTitle: String {
        switch model.snapshot.stage {
        case .preparing:
            let seconds = Int(ceil(Double(model.snapshot.prepRemainingMs) / 1000))
            return "\(seconds)초 후 시작"
        case .measuring: return "그대로 서 계세요"
        case .ready: return "기준 자세 다시 재기"
        case .none, .failed: return "기준 자세 재기"
        }
    }

    private var statusRow: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if !model.snapshot.calibrationProblems.isEmpty {
                ForEach(model.snapshot.calibrationProblems, id: \.self) { problem in
                    banner(problem.message, color: Palette.warning,
                           container: Palette.warningContainer,
                           icon: "exclamationmark.triangle.fill")
                }
            } else if model.snapshot.stage != .ready {
                ForEach(model.snapshot.readyIssues.prefix(2), id: \.self) { issue in
                    banner(FeedbackLabels.ready(issue), color: Palette.info,
                           container: Palette.infoContainer, icon: "info.circle.fill")
                }
            }

            if model.snapshot.stage == .ready {
                HStack(spacing: Spacing.md) {
                    chip("확인한 방향", model.snapshot.cameraAngle == .front ? "앞에서" : "옆에서")
                    if let depth = model.snapshot.depth,
                       let text = FeedbackLabels.depth(depth) {
                        chip("깊이", text)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12)).foregroundStyle(Palette.textMuted)
            Text(value).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Palette.surfaceVariant, in: RoundedRectangle(cornerRadius: Radius.sm))
    }

    private func banner(_ text: String, color: Color, container: Color,
                        icon: String) -> some View {
        // ⚠ **색만으로 상태를 구분하지 않는다** — 아이콘을 항상 함께 둔다.
        Label {
            Text(text).font(.system(size: 14, weight: .medium))
        } icon: {
            Image(systemName: icon)
        }
        .foregroundStyle(color)
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(container, in: RoundedRectangle(cornerRadius: Radius.md))
    }

    /// 성능 수치. 사용자 화면에서는 꺼야 하지만 Phase 2 동안은 확인용으로 둔다.
    private var diagnostics: some View {
        HStack(spacing: Spacing.md) {
            Text(model.sourceLabel)
            Text("추론 \(model.snapshot.inferenceMs, specifier: "%.1f")ms")
            Text("\(model.snapshot.analysisFps, specifier: "%.0f")fps")
            if model.snapshot.droppedFrames + model.droppedByBackpressure > 0 {
                Text("드랍 \(model.snapshot.droppedFrames + model.droppedByBackpressure)")
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(Palette.textDisabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
