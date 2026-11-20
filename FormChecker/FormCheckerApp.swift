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
    @State private var workoutOpen = false

    enum Route: Hashable {
        case history
        case summary(String)
    }

    var body: some View {
        NavigationStack(path: $path) {
            HomeScreen {
                workoutOpen = true
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
        .fullScreenCover(isPresented: $workoutOpen) {
            WorkoutScreen { workoutOpen = false }
        }
    }
}
