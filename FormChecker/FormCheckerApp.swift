import SwiftUI

@main
struct FormCheckerApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // 🔴 시스템 라이트/다크를 따르지 않는다. 카메라 오버레이 대비 때문이다.
                .preferredColorScheme(.dark)
        }
    }
}

/// 한 세션을 가리키는 값. `String`에 `Identifiable`을 붙이지 않고 감싸는 이유는
/// 문자열 전역에 적합성을 추가하지 않기 위함이다.
struct SessionRef: Identifiable, Hashable { let id: String }

/// 화면 이동.
///
/// ```
/// 홈 ──(운동 시작)──▶ 운동 ──(운동 종료)──▶ 결과 ──(홈으로)──▶ 홈
///  └──(기록 보기)──▶ 기록 ──(카드)──▶ 결과
/// ```
///
/// 🔴 **운동 화면은 전체 화면 덮기다.** 카메라 프리뷰 위에 네비게이션 바가 얹히면
/// 3:4 프리뷰의 세로가 줄어든다. 되돌아가는 길은 HUD 좌상단 하나다.
///
/// 🔴 **결과 화면은 운동과 기록 양쪽에서 열린다.** 두 길이 같은 화면을 봐야
/// "방금 한 운동"과 "그때 한 운동"이 같은 말을 한다.
struct RootView: View {

    @State private var path: [Route] = []
    @State private var settings = AppSettings.shared
    /// 🔴 **덮개 둘을 각각 `isPresented`로 띄우지 않는다** — 같은 뷰에
    /// `.fullScreenCover`를 두 번 붙이면 SwiftUI가 하나만 살린다(홈의 시트들과 같은
    /// 함정). 온보딩이 죽으면 첫 실행 안내가 영영 안 뜨고, 운동이 죽으면 앱이 아무것도
    /// 못 한다.
    @State private var cover: Cover?

    enum Route: Hashable {
        case history
        case summary(String)
    }

    enum Cover: Int, Identifiable {
        case onboarding, workout
        var id: Int { rawValue }
    }

    var body: some View {
        NavigationStack(path: $path) {
            HomeScreen {
                cover = .workout
            } onOpenHistory: {
                path.append(.history)
            }
            .navigationBarHidden(true)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .history:
                    HistoryScreen {
                        path.removeLast()
                    } onOpen: { sessionId in
                        path.append(.summary(sessionId))
                    }
                    .navigationBarHidden(true)
                case .summary(let sessionId):
                    SessionSummaryScreen(sessionId: sessionId, homeTitle: "닫기") {
                        path.removeLast()
                    }
                    .navigationBarHidden(true)
                }
            }
        }
        // 🔴 **운동 화면은 `NavigationStack`에 쌓지 않는다.** iOS는 푸시된 화면에
        //    가장자리 스와이프 백을 자동으로 붙이는데, 운동 중에 그 제스처가 걸리면
        //    **센 횟수가 저장도 확인도 없이 사라진다**(docs/02 FR-NAV-01).
        //    `fullScreenCover`에는 그 제스처가 없고, 나가는 길은 HUD 좌상단 하나다.
        //    온보딩도 같은 이유로 덮는다 — 읽지 않은 안내를 제스처로 넘기면 다음 실행에
        //    다시 뜨지 않는다(완료 상태는 `시작하기`·`건너뛰기`에서만 기록한다).
        //    `interactiveDismissDisabled`는 나중에 누가 시트로 바꿔도 같은 보장이
        //    유지되도록 함께 둔다.
        .fullScreenCover(item: $cover) { which in
            switch which {
            case .onboarding:
                OnboardingScreen {
                    settings.markSeen(.onboarding)
                    cover = nil
                }
                .interactiveDismissDisabled()
            case .workout:
                WorkoutScreen { cover = nil }
                    .interactiveDismissDisabled()
            }
        }
        // 설치 후 첫 실행인가. **여기서 한 번만 읽는다** — 매 렌더마다 `UserDefaults`를
        // 보면 온보딩을 끝낸 순간 화면이 중간에 갈아끼워진다.
        .task {
            if !settings.hasSeen(.onboarding) { cover = .onboarding }
        }
    }
}
