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

struct RootView: View {
    var body: some View {
        // Phase 2는 운동 화면 하나다. 홈·기록·설정은 Phase 3에서 붙는다.
        WorkoutScreen()
    }
}
