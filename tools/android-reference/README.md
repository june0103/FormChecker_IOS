# Android 기준값 생성기

**여기 있는 Kotlin 파일은 이 저장소에서 컴파일되지 않는다.** Android 저장소에 복사해
돌리고, 나온 수를 iOS와 맞춰 보는 용도다. 각 파일의 주석이 놓을 자리와 실행 명령을 말한다.

판정 동등성은 눈으로 볼 수 없다. 그래서 **비교 장치를 기능보다 먼저 만든다**(PRD §8).

```
git clone --depth 1 https://github.com/june0103/FormChecker.git
```

| 파일 | 무엇을 맞추나 | 기기 |
|---|---|---|
| `KeypointDumpTest.kt` | **G2** 키포인트 좌표 (Phase 0 — 닫힘, 최대 차 7.16e-07) | 필요 (추론) |
| `G1CountingTest.kt` | **G1** rep 카운팅 | **불필요** (순수 JVM) |

## G1 — rep 카운팅 동등성

### 1. iOS에서 기준값을 뽑는다

```bash
cd PoseEngine && xcodebuild test -scheme PoseEngine \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:PoseEngineTests/PosePipelineSequenceTests
```

두 파일이 이 폴더에 다시 쓰인다.

| 파일 | 내용 |
|---|---|
| `g1_frames.csv` | 상태머신에 들어가기 **전**의 프레임별 입력. 원시 무릎 각도 등 |
| `g1_ios.csv` | iOS가 센 rep 수와 rep별 경고 |

🔴 **스무딩된 값은 들어 있지 않다.** 원시 각도만 주고 EMA·중앙값은 양쪽이 각자 돌린다.
스무딩 결과를 넘기면 상태머신만 비교되고 **스무딩 차이가 그대로 숨는다** — 위상 지연이
한 프레임만 달라도 경계에서 rep 수가 갈린다.

### 2. Android에 옮긴다

```
pose-engine/src/test/java/com/mist/formchecker/poseengine/G1CountingTest.kt
pose-engine/src/test/resources/g1/g1_frames.csv
pose-engine/src/test/resources/g1/g1_ios.csv
```

### 3. 돌린다

```bash
./gradlew :pose-engine:test --tests '*G1CountingTest*'
```

통과하면 그 시퀀스들에 대해 G1의 **카운팅 부분**이 닫힌다. 어긋나면 어느 시퀀스에서
몇 대 몇인지 전부 찍고, 임계값을 건드리기 전에 볼 것 세 가지를 알려준다.

## 아직 닫히지 않은 것

| | 왜 |
|---|---|
| **경고 집합(G3)** | `SquatFormAnalyzer`는 자세가 필요한데 `g1_frames.csv`에는 각도만 있다. 자세 단위 픽스처가 따로 필요하다 |
| **녹화 영상 5개** | PRD가 요구하는 입력은 합성 시퀀스가 아니라 **실제 녹화 영상**이다. 영상도 Android 기준 횟수도 아직 없다 |
| **Android의 최소 체인 ↔ 실제 운동 화면** | 아래 참고 |

### ⚠ Android 쪽에 남은 구조 문제

`G1CountingTest`가 돌리는 것은 `pose-engine`의 **순수 조각**(EMA·중앙값·상태머신)이다.
실제 운동 화면은 `app` 모듈의 `WorkoutViewModel.onResult`(1661줄 `AndroidViewModel`)가
같은 조각을 엮어 돌린다. **그 둘이 같다는 보장이 Android 쪽에는 없다** — ViewModel이
Application·카메라·DB·오디오에 묶여 있어 JVM에서 돌릴 수 없기 때문이다.

iOS는 같은 문제를 겪었고 파이프라인을 패키지로 꺼내 풀었다(`PoseEngine/PosePipeline.swift`).
최소 체인과 전체 파이프라인이 같은 수를 센다는 것도 테스트로 못 박아 뒀다
(`test_최소_체인이_전체_파이프라인과_같은_수를_센다`).

👉 **Android도 `onResult`의 프레임 처리부를 `pose-engine`으로 옮기면 이 간극이 닫힌다.**
임계값 변경이 아니라 구조 변경이므로 Android 저장소에 제기해야 한다.
