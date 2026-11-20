import Foundation
import PoseEngine

/// 스플래시가 도는 동안 포즈 모델을 미리 읽어 둔다.
///
/// ## 왜 미리 읽나
/// 모델 로드는 수백 ms가 걸린다. 운동 화면에 들어간 뒤에 읽으면 **카메라는 켜졌는데
/// 아무것도 안 잡히는 구간**이 그만큼 생긴다. 스플래시 모션이 도는 시간은 어차피
/// 비어 있으므로 그 자리에서 읽는다.
///
/// 🔴 **메인 스레드를 막지 않는다**(FR-SPL-05). 읽기는 전용 큐에서 돌고, 스플래시
/// 화면은 그 결과를 기다리지도 않는다 — 모션이 끝나면 그냥 넘어간다.
///
/// ## 엔진은 한 번만 넘어간다
/// `take()`는 가져가면서 비운다. 엔진 하나를 두 파이프라인이 나눠 쓰면 추론 중에
/// 서로의 입력을 덮어쓴다 — `PosePipeline`이 **전용 직렬 큐에서만 동작한다**는 규약이
/// 깨지는 자리다.
///
/// `@unchecked Sendable`: 내부 상태는 전부 `condition`으로 보호한다. 넘겨주는
/// `RTMPoseEngine`은 **가져간 쪽의 큐로 소유권이 옮겨간다** — 여기서는 더 이상 만지지
/// 않는다.
final class ModelPreloader: @unchecked Sendable {

    static let shared = ModelPreloader()

    private enum State {
        case idle
        case loading
        case done(Result<Loaded, Error>)
        /// 이미 가져갔다. 두 번째 `take()`는 **기다리지 않고** nil을 낸다.
        case consumed
    }

    struct Loaded {
        let engine: RTMPoseEngine
        /// 엔진 초기화에 걸린 시간. **앱 콜드스타트가 아니다.**
        let loadMs: Int64
    }

    private let condition = NSCondition()
    private var state: State = .idle
    private let queue = DispatchQueue(label: "com.mist.formchecker.preload", qos: .userInitiated)

    /// 두 번 불러도 한 번만 읽는다.
    func start() {
        condition.lock()
        guard case .idle = state else {
            condition.unlock()
            return
        }
        state = .loading
        condition.unlock()

        queue.async { [self] in
            let result: Result<Loaded, Error>
            do {
                guard let url = RTMPoseEngine.bundledModelURL else {
                    throw NSError(domain: "ModelPreloader", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "모델이 번들에 없습니다",
                    ])
                }
                let started = DispatchTime.now().uptimeNanoseconds
                let engine = try RTMPoseEngine(modelPath: url.path)
                let ms = Int64((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
                result = .success(Loaded(engine: engine, loadMs: ms))
            } catch {
                // 실패해도 여기서 알리지 않는다 — 운동 화면이 직접 읽어 보고
                // 그때 사용자에게 말한다. 스플래시에서 모델 이야기를 꺼낼 일이 없다.
                result = .failure(error)
            }
            condition.lock()
            state = .done(result)
            condition.broadcast()
            condition.unlock()
        }
    }

    /// 미리 읽어 둔 엔진을 가져간다. 없으면 nil — 호출부가 직접 읽는다.
    ///
    /// 🔴 **아직 읽는 중이면 끝날 때까지 기다린다.** 기다리는 시간은 어차피 치렀을
    /// 비용이고, 같은 모델을 두 번 읽는 것보다 싸다. 이 대기는 파이프라인 큐에서
    /// 일어나므로 메인 스레드는 멈추지 않는다.
    func take() -> Loaded? {
        condition.lock()
        defer { condition.unlock() }

        while case .loading = state { condition.wait() }

        switch state {
        case .done(let result):
            state = .consumed
            return try? result.get()
        case .idle, .consumed, .loading:
            return nil
        }
    }
}
