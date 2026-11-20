import Foundation
import Observation
import PoseEngine
import Storage
import SwiftUI

@MainActor
@Observable
final class HistoryViewModel {

    private(set) var days: [HistoryDay] = []
    private(set) var pendingCount = 0
    private(set) var loading = true
    private(set) var loadError: String?

    @ObservationIgnored private let repository: WorkoutRepository

    init(repository: WorkoutRepository = WorkoutRepository()) {
        self.repository = repository
    }

    func refresh() async {
        let repository = self.repository
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                let sessions = try repository.recentSessions()
                let pending = try repository.pendingCount()
                return (sessions, pending)
            }.value
            // 🔴 **묶는 것은 화면이 아니라 순수 함수다** — 홈과 같은 규칙(세션 시작
            //    시각의 날짜)을 써야 "오늘 32회"가 두 화면에서 같은 값이 된다.
            days = groupByDay(sessions: loaded.0, nowMs: Int64(Date().timeIntervalSince1970 * 1000))
            pendingCount = loaded.1
            loading = false
            loadError = nil
        } catch {
            loading = false
            loadError = "기록을 불러오지 못했어요"
        }
    }

    func delete(sessionId: String) async {
        let repository = self.repository
        _ = try? await Task.detached(priority: .userInitiated) {
            try repository.delete(sessionId: sessionId)
        }.value
        await refresh()
    }
}

/// 기록.
///
/// 🔴 **날짜 헤더가 날짜를 말하므로 카드 제목에는 날짜를 쓰지 않는다**(시각만).
/// 같은 말을 두 번 쓰면 카드가 길어지고, 정작 궁금한 횟수가 뒤로 밀린다.
struct HistoryScreen: View {

    let onBack: () -> Void
    let onOpen: (String) -> Void

    @State private var model = HistoryViewModel()
    /// 삭제는 **두 번 눌러야** 지워진다. 어느 카드가 확인 대기인지만 들고 있다.
    @State private var confirmingDelete: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.loading {
                centered("불러오는 중…", color: Palette.textMuted)
            } else if let error = model.loadError {
                centered(error, color: Palette.danger)
            } else if model.days.isEmpty {
                centered("아직 기록이 없어요.\n운동을 마치면 여기에 하나씩 쌓여요.",
                         color: Palette.textMuted)
            } else {
                list
            }
        }
        .background(Palette.bgBase)
        .task { await model.refresh() }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: TouchTarget.min, height: TouchTarget.min)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textPrimary)

            Text("기록")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Palette.textPrimary)

            Spacer()

            // 🔴 **"동기화"는 개발자 말이다.** 사용자에게는 "아직 안 올라간 것"이 전부다.
            //    위장하면 "저장됐고 전송됐다"로 읽힌다 — 서버가 붙으면 이 숫자가 저절로 준다.
            if model.pendingCount > 0 {
                Text("업로드 대기 \(model.pendingCount)건")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Palette.infoContainer, in: Capsule())
                    .foregroundStyle(Palette.info)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.sm)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.lg, pinnedViews: []) {
                ForEach(model.days) { day in
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(dayHeader(day))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.textMuted)
                        ForEach(day.sessions) { session in
                            card(session)
                        }
                    }
                }
            }
            .padding(Spacing.md)
        }
    }

    private func dayHeader(_ day: HistoryDay) -> String {
        let date = Date(timeIntervalSince1970: Double(day.startMs) / 1000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일"
        let suffix: String
        switch day.relative {
        case .today: suffix = " (오늘)"
        case .yesterday: suffix = " (어제)"
        case .other: suffix = ""
        }
        return "\(formatter.string(from: date))\(suffix)  ·  총 \(day.totalReps)회"
    }

    private func card(_ session: SessionListItem) -> some View {
        let confirming = confirmingDelete == session.id
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            Button { onOpen(session.id) } label: {
                HStack(spacing: Spacing.sm) {
                    Text(timeText(session.startedAt))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)

                    Text(repText(session))
                        .font(.system(size: 14))
                        .foregroundStyle(session.warnedRepCount > 0
                                         ? Palette.warning : Palette.textMuted)

                    if session.pendingCount > 0 {
                        Text("대기 \(session.pendingCount)")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, 2)
                            .background(Palette.infoContainer, in: Capsule())
                            .foregroundStyle(Palette.info)
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.textMuted)
                }
                .frame(minHeight: TouchTarget.min)
            }
            .buttonStyle(.plain)

            // 🔴 **두 번 눌러야 지워진다.** 되돌릴 수 없는 동작을 한 번의 오터치에
            //    맡기지 않는다. 두 번째 문구가 무엇이 일어날지 그대로 말한다.
            Button {
                if confirming {
                    let id = session.id
                    confirmingDelete = nil
                    Task { await model.delete(sessionId: id) }
                } else {
                    confirmingDelete = session.id
                }
            } label: {
                Text(confirming ? "정말 지울까요? 한 번 더 누르시면 삭제돼요" : "삭제")
                    .font(.system(size: 13, weight: confirming ? .semibold : .regular))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: TouchTarget.min)
            }
            .buttonStyle(.plain)
            .foregroundStyle(confirming ? Palette.danger : Palette.textMuted)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Palette.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.md))
    }

    private func repText(_ session: SessionListItem) -> String {
        var text = "\(session.repCount)번"
        if session.warnedRepCount > 0 { text += " · 피드백 \(session.warnedRepCount)번" }
        return text
    }

    private func timeText(_ startedAt: Int64) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a h:mm"
        return formatter.string(from: Date(timeIntervalSince1970: Double(startedAt) / 1000))
    }

    private func centered(_ text: String, color: Color) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(color)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
