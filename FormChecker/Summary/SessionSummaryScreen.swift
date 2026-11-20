import PoseEngine
import Storage
import SwiftUI

/// 운동 결과.
///
/// 🔴 **화면 전체가 하나의 스크롤이고 `홈으로`만 스크롤 밖 고정이다.** 고정 높이 카드를
/// 쌓으면 피드백이 길어질 때 해상도에 따라 버튼이 잘린다.
///
/// 🔴 **종합 점수를 만들지 않는다.** 경고 7종에 가중치를 매길 근거가 없다.
struct SessionSummaryScreen: View {

    let sessionId: String
    /// 운동 직후에는 `홈으로`, 기록에서 열었을 때는 `닫기`다 — **버튼이 실제로 가는
    /// 곳을 말해야 한다.** 기록에서 열고 "홈으로"를 누르면 기록으로 돌아오는 게 거짓말이 된다.
    var homeTitle: String = "홈으로"
    let onHome: () -> Void

    @State private var report: SessionReport?
    @State private var records: [RepRecord] = []
    @State private var loadError: String?

    private var warnedRepCount: Int { records.count { $0.warnedCount > 0 } }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header
                    if let report {
                        overview(report)
                        findings(report)
                        notJudged(report)
                        depth(report)
                    } else if let loadError {
                        Text(loadError)
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.danger)
                    }
                    repList
                }
                .padding(Spacing.md)
            }

            Button(action: onHome) {
                Text(homeTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: TouchTarget.min)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.onSolid)
            .background(Palette.lime, in: RoundedRectangle(cornerRadius: Radius.md))
            .padding(Spacing.md)
        }
        .background(Palette.bgBase)
        .task { load() }
    }

    private func load() {
        do {
            let repository = WorkoutRepository()
            records = try repository.reps(sessionId: sessionId)
            report = SessionReporter.build(reps: records.map(RepRecordMapping.reported))
        } catch {
            loadError = "기록을 불러오지 못했어요"
        }
    }

    // ── 개요 ────────────────────────────────────────────────

    private var header: some View {
        Text("이번 운동을 한눈에 확인하세요")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(Palette.textPrimary)
    }

    /// 🔴 **총 횟수 / 확인한 횟수 / 피드백 횟수를 구분한다.**
    /// 하나로 뭉치면 "확인 못 함"과 "괜찮음"이 섞인다.
    private func overview(_ report: SessionReport) -> some View {
        HStack(spacing: Spacing.sm) {
            stat("총 횟수", "\(report.totalReps)번", Palette.lime)
            stat("확인한 횟수", "\(report.judgedReps)번", Palette.textPrimary)
            stat("피드백 횟수", "\(warnedRepCount)번",
                 warnedRepCount > 0 ? Palette.warning : Palette.textPrimary)
        }
    }

    private func card(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .background(Palette.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.md))
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).font(.system(size: 12)).foregroundStyle(Palette.textMuted)
            Text(value).font(.system(size: 22, weight: .bold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(Palette.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.lg))
    }

    // ── 자세 피드백 ─────────────────────────────────────────

    @ViewBuilder
    private func findings(_ report: SessionReport) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("오늘 자세 피드백")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)

            if report.judgedReps == 0 {
                card("자세를 확인할 수 있는 동작이 없었어요. 카메라에 몸 전체가 들어왔는지 확인해 주세요.",
                     color: Palette.textMuted)
            } else if report.noFindings {
                // 🔴 **"자세가 좋았습니다"라고 쓰지 않는다** — 확정된 임계값 전부가
                //    "정상을 오탐하지 않는가"만 검증됐고 "오류를 잡는가"는 미검증이다.
                card("\(report.judgedReps)번 모두 확인했는데 따로 드릴 피드백은 없었어요.",
                     color: Palette.textPrimary)
            } else {
                // 잦은 것부터. 순서를 빈도로 정하면 새 임계값이 필요 없다.
                ForEach(report.findings, id: \.warning) { finding in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Label {
                            Text(FeedbackLabels.sentence(finding))
                                .font(.system(size: 15, weight: .semibold))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .foregroundStyle(Palette.warning)
                        Text(FeedbackLabels.count(finding))
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.md)
                    .background(Palette.warningContainer,
                                in: RoundedRectangle(cornerRadius: Radius.md))
                }
            }
        }
    }

    /// 🔴 **못 본 것을 반드시 말한다.**
    ///
    /// ⚠ 항목을 한 줄씩 쌓지 않는다 — `kneeValgus`와 `kneeFlared`가 **같은 "무릎 방향"**
    /// 이라 같은 문장이 두 번 뜨고, 줄이 여섯이면 "내가 뭘 잘못했나"로 읽힌다.
    /// 중복 제거와 문장 만들기는 `FeedbackLabels` 한 곳에 있다.
    @ViewBuilder
    private func notJudged(_ report: SessionReport) -> some View {
        if !report.notJudged.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("확인하지 못한 것")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Label {
                    Text(FeedbackLabels.notJudgedSentence(report.notJudged))
                        .font(.system(size: 14))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "eye.slash")
                }
                .foregroundStyle(Palette.info)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.md)
                .background(Palette.infoContainer,
                            in: RoundedRectangle(cornerRadius: Radius.md))
            }
        }
    }

    @ViewBuilder
    private func depth(_ report: SessionReport) -> some View {
        if let summary = report.depth {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("앉은 깊이")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                HStack(spacing: Spacing.sm) {
                    ForEach([DepthLevel.shallow, .parallel, .deep], id: \.self) { level in
                        if let count = summary.levels[level], count > 0,
                           let name = FeedbackLabels.depth(level) {
                            Text("\(name) \(count)번")
                                .font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xs)
                                .background(Palette.surfaceVariant, in: Capsule())
                                .foregroundStyle(Palette.textPrimary)
                        }
                    }
                }
            }
        }
    }

    // ── 동작별 기록 ─────────────────────────────────────────

    private var repList: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("동작별 기록")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)

            ForEach(records) { record in
                HStack(spacing: Spacing.md) {
                    Text("\(record.repNumber)번")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.lime)
                        .frame(width: 44, alignment: .leading)

                    Text(String(format: "%.1f초", Double(record.durationMs) / 1000))
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textMuted)

                    Text(record.cameraAngle == CameraAngle.front.rawValue ? "앞에서" : "옆에서")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textMuted)

                    if let level = record.depthLevel.flatMap(DepthLevel.init(rawValue:)),
                       let name = FeedbackLabels.depth(level) {
                        Text(name).font(.system(size: 13)).foregroundStyle(Palette.textMuted)
                    }

                    Spacer()

                    Text(record.warnedCount > 0 ? "피드백 \(record.warnedCount)" : "피드백 없음")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(record.warnedCount > 0 ? Palette.warning : Palette.textMuted)
                }
                .padding(.vertical, Spacing.sm)
                .padding(.horizontal, Spacing.md)
                .background(Palette.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.sm))
            }
        }
    }
}

private extension Array {
    func count(where predicate: (Element) -> Bool) -> Int {
        reduce(0) { predicate($1) ? $0 + 1 : $0 }
    }
}
