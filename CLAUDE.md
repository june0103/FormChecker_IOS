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

- **Phase 0·1 통과.**
  - 추론 엔진이 Android와 **같은 키포인트**를 낸다 (최대 좌표차 7.16e-07) → `docs/05_Phase0_결과.md`
  - 판정 엔진을 Swift로 옮겼고 **테스트 294개 전부 통과** → `docs/04` §15
- **Phase 2 진행 중.** 앱 타겟이 생겼고 운동 화면이 시뮬레이터에서 돈다 —
  카메라/번들 영상 → 추론 → 판정 → 카운팅, 스켈레톤·기준 자세·피드백·소리.
- 안내는 **동작 예시 → 코치마크** 두 층까지 붙었다. 완료 상태는 Bool이 아니라
  **버전 값**이라, 안내를 고치면 `GuideKey.currentVersion`을 올려 다시 보여줄 수 있다.
- **아직 없는 것**: 온보딩 4쪽·측정 준비 시트, 0회 종료 다이얼로그, 스와이프 백 차단,
  결과 화면, 저장(Phase 3).
- 기준 Android 커밋: `79ef0bb` (2026-09-02)
- 확정된 스택: SwiftPM(CocoaPods 안 씀) · LiteRT C API 직접 래핑 · 최소 iOS 17 · 리샘플링 최근접
- 미확정: 로컬 DB(GRDB 제안) / 폰트 → `docs/03` §17

```bash
tools/fetch_litert.sh                                    # 최초 1회
cd PoseEngine && xcodebuild test -scheme PoseEngine \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'  # 294개 통과해야 한다
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
FormChecker/   앱 — SwiftUI · AVFoundation · DB · 화면
PoseEngine/    Swift Package — 추론과 판정
               의존 허용: Foundation, CoreVideo, CoreGraphics, Accelerate, LiteRT
               의존 금지: SwiftUI, UIKit, AVFoundation, DB
```

`PoseEngine`이 `AVFoundation`을 import하면 **녹화 영상 주입 벤치마크가 불가능해진다.**
새 의존성을 추가할 때 이 원칙을 먼저 확인할 것.

## 작업 순서 (게이트)

```
Phase 0  ✅ 키포인트 동등성 (BGRA·stride·미러링까지)
Phase 1  ✅ 판정 엔진 이식 + Android 테스트 271개 통과
Phase 2  ▶  운동 화면 — 파이프라인·오버레이·기준 자세·피드백·소리·안내 ✅ / 결과 화면 남음
Phase 3     저장·기록·홈·결과 리포트
Phase 4     안내 4층 · 설정 · 디자인 마감 · 성능 측정
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
