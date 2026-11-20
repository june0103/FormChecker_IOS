# 폼체커 iOS — Claude Code 컨텍스트

이 저장소는 **[Android 폼체커](https://github.com/june0103/FormChecker)의 iOS 이식**이다.
새 제품을 설계하는 자리가 아니다.

## 작업 전에 반드시 읽을 것

| 순서 | 문서 | 왜 |
|---|---|---|
| 1 | [`docs/01_PRD.md`](docs/01_PRD.md) | 무엇이 성공인가 — **판정 동등성**이 1순위라는 것 |
| 2 | [`docs/03_AOS_iOS_구현차이.md`](docs/03_AOS_iOS_구현차이.md) | 조용히 틀어지는 자리가 어디인가 |
| 3 | [`docs/04_판정엔진_포팅명세.md`](docs/04_판정엔진_포팅명세.md) | 임계값과 알고리즘 정본 |
| 4 | [`docs/02_기능명세서.md`](docs/02_기능명세서.md) | 화면·문구·설정 |

**판정 로직을 건드리는 작업이면 4번을 건너뛰더라도 3번은 읽는다.**

## 현재 상태 (2026-11-20)

- **Phase 0·1·2 통과.**
  - 추론 엔진이 Android와 **같은 키포인트**를 낸다 (최대 좌표차 7.16e-07) → `docs/05_Phase0_결과.md`
  - 판정 엔진을 Swift로 옮겼고 **테스트 304개 전부 통과** → `docs/04` §15
  - 운동 화면이 시뮬레이터에서 돈다 — 카메라/번들 영상 → 추론 → 판정 → 카운팅,
    스켈레톤·기준 자세·피드백·소리.
- **Phase 3 진행 중.** `Storage` 패키지(GRDB)·결과 리포트·날짜별 기록·홈 대시보드가 붙었고
  **홈 → 운동 → 결과 → 기록**이 끝까지 이어진다. Storage 테스트 28개 통과.
- 안내 **4층이 전부 붙었다** — 온보딩 4쪽 → 측정 준비 시트 → 동작 예시 → 코치마크.
  완료 상태는 Bool이 아니라 **버전 값**이라, 안내를 고치면 `GuideKey.currentVersion`을
  올려 다시 보여줄 수 있다. 문구 정본은 `Guide/OnboardingPages.swift` 한 곳이다.
- 운동 화면은 **`fullScreenCover`로 띄운다** — `NavigationStack`에 쌓으면 iOS가 가장자리
  스와이프 백을 붙이고, 운동 중 오터치 한 번에 센 횟수가 사라진다.
- **Phase 4 진행 중.** 설정 화면(자세 기준·내 정보·측정·하루 목표·도움말·개발용)과
  성능 측정(p95)이 붙었다. **자세 기준 완화가 판정에 연결된 유일한 사용자 설정**이고,
  세션이 시작될 때 한 번 읽어 끝까지 바꾸지 않는다.
- 성능 대표값은 `PerformanceSamples`가 **원표본에서** 낸다 — Android와 같은 식으로
  `정렬 후 (n-1)*95/100`번째다. 식을 바꾸면 두 앱의 숫자를 나란히 놓을 수 없다.
- 스플래시 두 층이 붙었다 — 시스템 런치 화면(배경색만, `Assets.xcassets/BgBase`)과
  앱이 재생하는 **오렌지 → 라임 교정 모션**. 모션이 도는 동안 `ModelPreloader`가
  포즈 모델을 **전용 큐에서** 읽어 두고, 운동 화면은 그걸 가져다 쓴다.
- **명세 FR 118개를 전수 대조했다**(2026-11-20). 빠진 것은 셋뿐이었고 셋 다 🆕 —
  카메라 인터럽션 복구·권한 거부 시 설정 열기·스키마 export. 전부 채웠다.
  앞의 둘은 시뮬레이터에서 경로를 탈 수 없어 **실기기 확인이 남았다** → `docs/03` §17.
- **미해결**: 설정 화면에서 값이 바뀌는 뷰가 스크롤 원점에 한 번 더 그려진다
  (기능 영향 없음) → `docs/03` §17.
- 기준 Android 커밋: `79ef0bb` (2026-09-02)
- 확정된 스택: SwiftPM(CocoaPods 안 씀) · LiteRT C API 직접 래핑 · 최소 iOS 17 ·
  리샘플링 최근접 · **로컬 DB는 GRDB 7.12.0**
- 미확정: 폰트 → `docs/03` §17

```bash
tools/fetch_litert.sh                                    # 최초 1회
cd PoseEngine && xcodebuild test -scheme PoseEngine \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'  # 316개 통과해야 한다
cd Storage   && xcodebuild test -scheme Storage \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'  # 28개 통과해야 한다
```

## 이 프로젝트에서 가장 비싼 실수

1. **`nil`을 `0`이나 `false`로 바꾸는 것.** 판정 불가와 "문제 없음"이 섞이면
   경고가 영원히 안 뜬다. Android에서 깊이 각도 경로가 정확히 이 사고를 냈다.
2. **임계값을 "iOS에 맞게" 조정하는 것.** 그 숫자들은 실측 15세션에서 나왔다.
   조정이 필요해 보이면 **Android 저장소에 먼저 제기하고 양쪽을 함께 바꾼다.**
3. **전처리를 "당연한 방식"으로 짜는 것.** iOS의 당연함(BGRA, ÷255 정규화, Core Graphics
   보간)이 전부 Android와 다르다. → `docs/03` §4의 9단계 표를 그대로 따른다.
   ⚠ **실제로 터진 적이 있다** — 양선형 보간을 쓰면 키포인트가 최대 0.42 벌어진다.
   `RTMPoseEngine.defaultResampleMode`를 바꾸지 말 것.
4. **판정 로직을 View에 넣는 것.** 화면이 둘이면 두 화면이 다른 답을 낸다.

## 지켜야 할 경계

```
FormChecker/   앱 — SwiftUI · AVFoundation · 화면
PoseEngine/    Swift Package — 추론과 판정
               의존 허용: Foundation, CoreVideo, CoreGraphics, Accelerate, LiteRT
               의존 금지: SwiftUI, UIKit, AVFoundation, DB
Storage/       Swift Package — SQLite(GRDB)와 날짜 경계
               의존 허용: Foundation, GRDB, PoseEngine
               의존 금지: SwiftUI, UIKit, AVFoundation
```

앱 타겟에는 **테스트 타겟이 없다**(서명 문제로 접었다 → `docs/03` §17). 그래서 테스트가
닿아야 하는 순수 로직은 패키지에 둔다 — 날짜 경계(`weekWindowOf`·`groupByDay`),
목표 진행률(`GoalProgress`), 신체 정보 범위(`BodyProfile`)가 그래서 저기 있다.

`PoseEngine`이 `AVFoundation`을 import하면 **녹화 영상 주입 벤치마크가 불가능해진다.**
새 의존성을 추가할 때 이 원칙을 먼저 확인할 것.

## 작업 순서 (게이트)

```
Phase 0  ✅ 키포인트 동등성 (BGRA·stride·미러링까지)
Phase 1  ✅ 판정 엔진 이식 + Android 테스트 271개 통과
Phase 2  ✅ 운동 화면 — 파이프라인·오버레이·기준 자세·피드백·소리·안내
Phase 3  ✅ 저장·기록·홈·결과 리포트 · 안내 4층
Phase 4  ▶  설정 화면 ✅ · 성능 측정(p95) ✅ · 폰트 확정 ✅ · 스플래시 ✅
            / 실기기 측정 남음 (기기가 없어 보류)
```

Phase 2에서는 **판정 로직을 화면에 넣지 않는다** — 넣으면 두 화면이 다른 답을 낸다.
판정은 전부 `PosePipeline`과 `PoseEngine`에 있고, 화면은 `WorkoutSnapshot`을 그리기만 한다.

⚠ **프레임을 큐에 쌓지 말 것.** `work.async`는 무제한 버퍼라 프레임이 추론보다 빨리
들어오면 조작(버튼)까지 그 뒤에 줄을 선다. `FrameGate`가 처리 중이면 버린다 —
Android `STRATEGY_KEEP_ONLY_LATEST`가 카메라 단에서 하던 일이다.

## 코드 규칙

- 엔진 전체를 **`Float`로 고정**한다. Swift 리터럴이 `Double`로 추론되기 쉽다.
- 임계값에는 **출처 등급을 주석으로** 함께 옮긴다 (`DATA_DERIVED`/`DEFINITION`/`PROVISIONAL`).
  근거 없는 숫자를 `PROVISIONAL` 표시 없이 넣으면 나중에 아무도 되돌릴 수 없다.
- 사용자 문구에 **`rep`·`패럴렐`·`valgus`·임계값 숫자**를 쓰지 않는다.
  용어 매핑은 `FeedbackLabels` 한 곳에 두고 세 화면이 공유한다.
- 버전은 검색 요약이 아니라 **레지스트리를 직접 조회해서** 고정한다
  (CocoaPods trunk / SPM 태그).
- 성능 대표값은 중앙값이 아니라 **p95**를 쓴다.

## Android 저장소를 참조해야 할 때

판정 동작이 애매하면 **문서가 아니라 코드를 본다.**

```bash
git clone --depth 1 https://github.com/june0103/FormChecker.git
```

핵심 파일: `pose-engine/src/main/java/com/mist/formchecker/poseengine/`
(`SquatThresholds.kt` · `FrameFeatures.kt` · `RepStateMachine.kt` · `SquatFormAnalyzer.kt`)

Android 쪽 `CLAUDE.md`는 **"왜 그렇게 되어 있는지"** 를 담고 있다. 임계값을 바꾸고 싶어지면
그 파일의 해당 KDoc을 먼저 읽을 것 — 대부분 이미 한 번 시도해보고 되돌린 길이다.
