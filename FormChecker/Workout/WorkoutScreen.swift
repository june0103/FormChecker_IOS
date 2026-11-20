import PoseEngine
import SwiftUI

/// 운동 화면.
///
/// 🔴 **프리뷰는 화면 폭 전부 · 3:4 · 상단 고정이고 이게 천장이다.** 세로 공간을 더 줘도
/// 커지지 않는다. 3:4는 모델이 정한 값이다 — RTMPose 입력이 192×256이라 letterbox 패딩이
/// 0이고, 16:9로 바꾸면 가로를 75%만 쓰며 정면 판정(전부 수평 측정)의 근거가 흔들린다.
///
/// 프리뷰 **아래는 스크롤**이다 — 안내가 길어지면 버튼이 잘린다.
struct WorkoutScreen: View {

    @State private var model = WorkoutViewModel()
    @State private var repPulse = false

    var body: some View {
        VStack(spacing: 0) {
            preview
            ScrollView { controls }
        }
        .background(Palette.bgBase)
        .task { await model.start() }
        .onDisappear { model.stop() }
        .onChange(of: model.snapshot.repCount) { _, _ in
            withAnimation(.easeOut(duration: Motion.repPulse)) { repPulse = true }
            withAnimation(.easeIn(duration: Motion.repPulse).delay(Motion.repPulse)) {
                repPulse = false
            }
        }
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
            SkeletonOverlay(pose: model.snapshot.pose, mirrored: false)
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
                Button {
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: TouchTarget.min, height: TouchTarget.min)
                }
                .foregroundStyle(Palette.textPrimary)

                Spacer()

                Text(model.snapshot.cameraAngle == .front ? "앞에서" : "옆에서")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Palette.surfaceCard.opacity(0.8), in: Capsule())
                    .foregroundStyle(Palette.textMuted)
                    .padding(.top, Spacing.sm)
            }
            .padding(.horizontal, Spacing.sm)

            Spacer()
            counter
            Spacer()
            feedbackStack
        }
    }

    private var counter: some View {
        VStack(spacing: Spacing.xs) {
            Text("\(model.snapshot.repCount)")
                .font(.repCounter(digits: String(model.snapshot.repCount).count))
                .foregroundStyle(Palette.lime)
                .scaleEffect(repPulse ? 1.15 : 1.0)
                .shadow(color: .black.opacity(0.6), radius: 8)

            // 🔴 **막는 대신 왜 안 세는지 숫자 바로 아래에 알린다.**
            if let reason = FeedbackLabels.notCounting(
                stage: model.snapshot.stage,
                readyIssue: model.snapshot.readyIssues.first
            ) {
                Text(reason)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(Palette.infoContainer.opacity(0.92), in: Capsule())
            }
        }
    }

    /// 🔴 정렬은 **도착 순(새로 뜬 것이 맨 위)** — 우선순위 순이 아니다.
    /// 하단 고정이라 위에 붙여야 기존 줄이 밀리지 않는다.
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
            Button(action: model.beginCalibration) {
                Text(buttonTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: TouchTarget.min)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.onSolid)
            .background(model.engineReady ? Palette.lime : Palette.textDisabled,
                        in: RoundedRectangle(cornerRadius: Radius.md))
            .disabled(!model.engineReady)

            Button {
                model.finishSession()
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
                    chip("확인한 자세", model.snapshot.cameraAngle == .front ? "앞에서" : "옆에서")
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
