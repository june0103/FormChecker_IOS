# Android → iOS 구현 차이

> **목적**: 같은 제품을 만들면서 **플랫폼 때문에 반드시 달라지는 것**과,
> **달라지면 안 되는데 조용히 달라질 수 있는 것**을 구분한다.
> **기준**: Android `79ef0bb` (2026-09-02) · 작성일 2026-11-20

---

## 0. 요약 — 큰 차이 세 개

| # | 차이 | 영향 |
|---|---|---|
| **A** | **추론 런타임과 전처리** — LiteRT는 양쪽에 있지만 이미지 파이프라인(색 순서·리사이즈 보간)이 다르다 | 🔴 **판정 동등성이 여기서 깨진다.** 임계값 15개의 근거가 전부 걸려 있다 |
| **B** | **백그라운드 실행 모델** — iOS에는 `WorkManager`에 해당하는 보장된 주기 실행이 없다 | 🟡 동기화가 1.0 범위 밖이라 당장은 영향 없음. **설계만 미리 다르게 잡는다** |
| **C** | **소리·안내의 플랫폼 장치 부재** — `ToneGenerator` 없음, GIF 디코더 없음, 가변 폰트 weight 취급이 다름 | 🟡 주 피드백 채널이 소리라 **체감 품질에 직결** |

나머지(UI 프레임워크·DB·DI·네비게이션)는 **대응물이 분명히 있어서 번역 작업**에 가깝다.

---

## 1. 1:1 대응표

| 역할 | Android | iOS 권장 | 난이도 |
|---|---|---|---|
| UI | Jetpack Compose | SwiftUI | 중 — 선언형끼리라 개념이 거의 같다 |
| 네비게이션 | Navigation Compose (타입 안전 `@Serializable` 라우트) | `NavigationStack(path:)` + `Hashable` enum | 하 |
| 화면 상태 | `ViewModel` + `StateFlow` | `@Observable` 클래스 (또는 `ObservableObject`) | 하 |
| 비동기 | Coroutines / Flow | Swift Concurrency (`async`/`await`, `AsyncStream`) | 중 — 취소·스레드 모델이 다르다 |
| DI | Hilt (컴파일 타임) | **직접 주입 + 작은 Container** | 하 — Hilt급 도구가 필요 없을 만큼 그래프가 작다 |
| 로컬 DB | Room (SQLite, KSP, 스키마 export) | **GRDB.swift** (SQLite 직접, 마이그레이션, `ValueObservation`) | 중 |
| 설정 저장 | DataStore Preferences (`Flow`) | `UserDefaults` + `@Observable` 래퍼 | 하 |
| 카메라 | CameraX (`Preview` + `ImageAnalysis`) | AVFoundation (`AVCaptureVideoPreviewLayer` + `AVCaptureVideoDataOutput`) | **상** |
| 추론 | LiteRT `Interpreter` (Java) | LiteRT `Interpreter` (Swift) — `TensorFlowLiteSwift` | 중 |
| 프레임 타입 | `Bitmap` | `CVPixelBuffer` | 중 |
| 소리 | `ToneGenerator` | **대응물 없음** → 번들 오디오 / `AVAudioEngine` 합성 | 중 |
| GIF | 플랫폼 `ImageDecoder` | **대응물 없음** → `CGAnimateImageAtURLWithBlock` 또는 영상 변환 | 하 |
| 백그라운드 작업 | WorkManager | `BGTaskScheduler` (**보장 없음**) | 상 (1.0 범위 밖) |
| 파일 공유 | `FileProvider` + Intent | `ShareLink` / `UIActivityViewController` | 하 |
| 단위 테스트 | JUnit4 | XCTest 또는 Swift Testing | 하 |
| 성능 측정 | Macrobenchmark · JankStats | XCTest `measure` · MetricKit · `os_signpost` · Instruments | 중 |
| 배포 | APK / Play | TestFlight / App Store (심사) | 중 |

---

## 2. 모듈 경계 — 이것만은 똑같이 유지한다

Android는 판정 로직을 `:pose-engine` 모듈에 격리했다. **Compose·CameraX·Hilt에 의존하지 않는다.**
그래서 기기 없이 단위 테스트가 돌고, 녹화 영상을 같은 파이프라인에 주입할 수 있다.

**iOS도 똑같이 한다.**

```
FormChecker (앱 타겟)        SwiftUI · AVFoundation · GRDB · 화면
   └── PoseEngine (로컬 Swift Package)
         의존: Foundation, CoreVideo, CoreGraphics, Accelerate, TensorFlowLiteSwift
         금지: SwiftUI, UIKit, AVFoundation, GRDB
```

⚠ **`PoseEngine`이 `AVFoundation`을 import하는 순간 이 설계가 무너진다.** 입력 타입은
`CVPixelBuffer`로 충분하다 — 카메라가 준 것이든 `AVAssetReader`가 영상에서 뽑은 것이든
엔진에서는 구분되지 않아야 한다. (Android가 `ImageProxy`가 아니라 `Bitmap`을 받는 이유와 같다)

---

## 3. 추론 런타임

### 3.1 선택지

| | ① LiteRT + 같은 `.tflite` | ② Core ML 변환 | ③ Apple Vision |
|---|---|---|---|
| 모델 | `rtmpose_s_halpe26_256x192_f16.tflite` 그대로 | RTMPose 원본 → ONNX → Core ML 재변환 | Apple 기본 포즈 |
| 키포인트 | **Halpe26 (발 6개 포함)** | Halpe26 유지 | **19개, 발 없음** ❌ |
| 판정 동등성 | **가장 높다** — 같은 가중치·같은 출력 | 중 — 변환 과정에서 수치가 미세하게 바뀐다 | **불가능** |
| 가속 | Core ML / Metal delegate 시도 가능 | ANE 직접 사용 (가장 빠를 가능성) | ANE |
| 비용 | 낮음 | **높음** — 원본 모델 확보 + 변환 + 재검증 | — |
| 앱 크기 | 11.4 MB | 비슷 | 0 |

### 3.2 ③ Apple Vision은 **쓸 수 없다** (확인함)

`VNHumanBodyPoseObservation.JointName`의 전체 목록은 다음 19개다:

```
nose, leftEye, rightEye, leftEar, rightEar, neck,
leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist,
root, leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle
```

**뒤꿈치도 발가락도 없다.** 3D(`VNHumanBodyPose3D`)에도 없다.
이것은 Android가 MoveNet(COCO17)을 기본에서 뺀 것과 **정확히 같은 이유**다 —
발 키포인트가 없으면 **뒤꿈치 들림**과 **무릎이 발끝을 넘음** 두 판정을 **아예 계산할 수 없다**.

> Vision은 "iOS니까 Vision 쓰면 되지 않나"라는 질문에 대한 답으로 여기 적어둔다.
> **판정 2종을 버릴 수 있다면** 선택지가 되지만, 그건 다른 제품이다.

### 3.3 권장: **① LiteRT + 같은 모델**, delegate는 측정 후 결정

```ruby
# Podfile
pod 'TensorFlowLiteSwift', :subspecs => ['CoreML', 'Metal']
```

- Swift에서 `import TensorFlowLite`, `Interpreter(modelPath:delegates:)`.
- **Core ML delegate는 float 모델에서만 동작**하고 iOS 12+에서 쓸 수 있다. 이 모델은 f16이라 대상이 된다.
- Metal(GPU) delegate도 선택지다.
- ⚠ **CocoaPods 버전은 Maven 메타데이터 대신 CocoaPods trunk를 직접 조회해서 고정한다.**
  (Android 저장소의 "검색 요약이 아니라 메타데이터를 직접 확인" 규칙을 그대로 적용)

### 3.4 ⚠ Android의 GPU 교훈

Android에서 *"RTMPose는 SimCC 헤드라 GPU가 붙을 것"* 이라는 가설이 **실측으로 반증**됐다
(`CompiledModel`·GPU = 컴파일 실패, CPU 성능은 두 API가 동일).

**iOS에서도 같은 함정이 있다.** "ANE가 있으니까 빠를 것"은 가설이지 사실이 아니다.
Core ML delegate가 연산 일부만 받아가면 **CPU↔ANE 왕복 때문에 오히려 느려질 수 있다.**

👉 **CPU 경로를 기본으로 완성한 뒤**, delegate는 A/B 벤치마크로만 켠다. 그 벤치마크는
Android `DelegateBenchmark`와 같은 모양으로 만든다.

### 3.5 MoveNet은 iOS에 넣지 않는다

Android는 성능 비교와 저사양 폴백을 위해 MoveNet(4.7MB)을 남겨뒀다. iOS 1.0은
**RTMPose 하나만** 번들한다 — 비교 근거는 Android 저장소에 이미 있고, 앱 크기를 4.7MB 줄인다.

---

## 4. 🔴 카메라 → 추론 전처리 (여기가 가장 위험하다)

판정 동등성이 깨진다면 거의 확실히 이 구간이다. 단계별로 **무엇이 다른지**를 적는다.

| 단계 | Android | iOS | 조용히 틀어지는 지점 |
|---|---|---|---|
| 1. 프레임 포맷 | `OUTPUT_IMAGE_FORMAT_RGBA_8888` | `kCVPixelFormatType_32BGRA` (표준) | 🔴 **R과 B가 뒤바뀐다.** 실측 어긋남 **0.0339**(게이트의 3.4배). ✅ 테스트로 고정됨 |
| 2. 회전 | `setOutputImageRotationEnabled(true)` — CameraX가 처리 | `AVCaptureConnection.videoRotationAngle` | 🟡 직접 회전시키면 버퍼 복사 비용이 돌아온다 (Android 실측 p95 3.21ms + GC 3회/300프레임) |
| 3. 미러링 | 하지 않음 (의도) | **하지 않는다** — `isVideoMirrored = false` | 🔴 전면 카메라에서 켜면 **좌/우 라벨이 뒤집혀 무릎 판정이 반대로** 나온다 |
| 4. 해상도 | 480×640 요청 (4:3) | `.vga640x480` → 회전 후 480×640 | 🟡 요청이 실패하면 기기마다 다른 크기가 들어온다. **실제 크기를 로그로 확인할 것** |
| 4b. 행 패딩 | 없음 (`getPixels`) | `bytesPerRow > width × 4` 일 수 있다 | 🔴 실측에서 500×500 버퍼가 **2048**(packed 2000). 가정하면 아래로 갈수록 좌표가 사선으로 밀린다. ✅ 테스트로 고정됨 |
| 5. 백프레셔 | `STRATEGY_KEEP_ONLY_LATEST` | `alwaysDiscardsLateVideoFrames = true` | — 대응이 정확하다 |
| 6. letterbox | `Canvas.drawBitmap(src, null, dstRect, null)` = **최근접**(실측 확인) | **최근접으로 직접 구현** | 🔴 양선형을 쓰면 키포인트가 **최대 0.42** 벌어진다 ([05 문서](05_Phase0_결과.md)) |
| 7. 패딩 색 | `Color.BLACK` | **검정(0,0,0)으로 맞춘다** | 🟡 회색/투명으로 두면 가장자리 키포인트가 달라진다 |
| 8. 텐서 입력 | float32 RGB **0~255 raw** (정규화 안 함) | **동일** | 🔴 iOS에서 습관적으로 ÷255 하면 키포인트가 엉뚱한 곳에 찍힌다 (이중 정규화) |
| 9. 버퍼 쓰기 | `FloatArray`에 모아 **벌크 1회** | `UnsafeMutableBufferPointer` 또는 `Data` 한 번에 | 🟡 Android에서 한 개씩 쓰다 p95 4.44ms → 0.19ms (**23배**) |

### 4.1 Phase 0 비교 테스트 — **실행했고, 통과했다**

같은 PNG 4장을 양 플랫폼 엔진에 넣고 26개 키포인트를 비교했다. 결과는
[05 문서](05_Phase0_결과.md)에 있다.

| 리샘플링 | Android와의 최대 좌표차 |
|---|---|
| **최근접** | **0.000001** ✅ |
| 양선형 | 0.416699 ❌ |

**6번이 실제로 터졌다.** Android `drawBitmap`은 paint가 null이라 필터링을 하지 않는다 —
iOS에서 "당연한" 양선형을 썼다면 키포인트가 조용히 0.42까지 벌어졌을 것이다.

이 비교는 `KeypointEquivalenceTests`로 회귀 테스트가 됐고, Android 기준값은
`PoseEngine/Tests/PoseEngineTests/Resources/reference/keypoints_android.csv`에 커밋돼 있다.

---

## 5. 좌표계

| | Android | iOS |
|---|---|---|
| 모델 출력 | SimCC argmax → 0~1 정규화 | 동일 |
| 엔진이 유지하는 좌표 | **letterbox를 걷어낸 원본 프레임 기준 0~1** | 동일하게 유지 |
| 화면 Y축 | 위가 0 (Compose) | 위가 0 (SwiftUI) ✅ 같다 |
| ⚠ Vision 좌표계 | — | **아래가 0** — Vision을 쓰지 않으므로 해당 없지만, 샘플 코드를 베끼면 섞인다 |
| 비등방 보정 | `aspectRatio = width/height`를 각도 계산에 곱함 | **반드시 동일하게 유지** |

🔴 **정규화 좌표는 x와 y의 "1"이 다른 픽셀 길이다.** 각도를 계산할 때 종횡비로 보정하지
않으면 프레임이 세로로 길수록 값이 틀어진다. Android `Geometry.point(pose, type, aspectRatio)`가
하는 일이고, **iOS에서 이 인자를 빠뜨리면 모든 각도가 조용히 틀린다.**

---

## 6. 수치 연산 — Kotlin → Swift 함정

| 항목 | Kotlin | Swift | 주의 |
|---|---|---|---|
| 기본 부동소수 | `Float` 명시 | `Float` 명시 | Swift에서 리터럴이 `Double`로 추론되기 쉽다. **엔진 전체를 `Float`로 고정** |
| 정수 나눗셈 | `(target - scaled) / 2` | 동일 | 패딩 계산에서 소수점이 생기면 안 된다 |
| 반올림 | `roundToInt()` (half-up) | `Int(x.rounded())` (half-away-from-zero) | 양수에서는 같다. 음수 좌표가 생길 수 있는 letterbox `inverse`에서 주의 |
| 중앙값 | 짝수면 **두 값의 평균** | 동일하게 구현 | `kneePastToeOf`가 이 정의에 의존 |
| 평균 | `List.average()` → Double | `reduce` 후 Double 누적 | Float 누적은 오차가 쌓인다 |
| null 전파 | `?.` / `?:` | `Optional` | **"판정 불가 = nil"** 규칙이 이식의 핵심. `0`이나 `false`로 대체하면 **경고가 영원히 안 뜬다** |
| 열거형 순서 | `enum class` 선언 순서 | `enum` 선언 순서 | 같은 프레임 경고 정렬이 선언 순서에 의존한다 |

🔴 **`nil`을 `false`로 바꾸는 실수**가 이 프로젝트에서 가장 비싼 버그다. Android에서
"각도 대체 경로가 항상 '충분히 깊다'고 답해 경고가 영원히 안 떴던" 사고와 같은 종류다.

---

## 7. 저장소 (Room → GRDB)

| 항목 | Room | GRDB.swift |
|---|---|---|
| 스키마 정의 | `@Entity` 애너테이션 | 마이그레이션에 **SQL 직접** |
| 스키마 export | `room.schemaLocation` → JSON | `migrator` 코드 + 테스트로 고정 |
| 관찰 | `Flow<T>` | `ValueObservation` → `AsyncValueObservation` |
| FK cascade | `ForeignKey(onDelete = CASCADE)` | `PRAGMA foreign_keys = ON` + `ON DELETE CASCADE` ⚠ **PRAGMA를 켜지 않으면 cascade가 동작하지 않는다** |
| 마이그레이션 | 버전 + Migration 객체 | `DatabaseMigrator` |

### 왜 SwiftData가 아닌가

- Supabase DDL이 **정본**이고 양 플랫폼이 같은 모양을 유지해야 한다. SwiftData는 SQL을 감춘다.
- Android는 스키마 JSON을 저장소에 커밋해 **변경을 리뷰할 수 있게** 해뒀다. SwiftData에는 대응물이 없다.
- 기록이 쌓였을 때의 쿼리 성능을 Android에서 이미 한 번 고쳤다(`DbQueryBenchmark`). 같은 인덱스를 쓰려면 SQL이 보여야 한다.

> SwiftData를 고르면 "이 화면에 필요한 쿼리"를 매번 다시 발명하게 된다. **GRDB 권장.**

---

## 8. 설정 저장 (DataStore → UserDefaults)

| 규칙 | 이식 방법 |
|---|---|
| 🔁 **기본값을 저장소에 두지 않는다** | `UserDefaults.object(forKey:) == nil` 로 "없음"을 구분한다. ⚠ `integer(forKey:)`는 **없을 때 0을 돌려준다** — `0초(바로)`가 유효한 값이라 이걸 쓰면 두 상태가 섞인다 |
| 🔁 `Flow`로 읽혀야 화면이 바로 반영된다 | `@Observable` 래퍼 하나로 감싸고 화면은 저장소를 직접 읽지 않는다 |
| 🔁 싱글턴이어야 한다 | Android는 DataStore를 두 개 열면 런타임에 터졌다. iOS는 터지지 않고 **조용히 갈린다** — 더 나쁘다 |

---

## 9. UI와 디자인 시스템

| 항목 | Android | iOS |
|---|---|---|
| 테마 | Material3 `darkColorScheme` **모든 롤 명시** | **M3 대응물이 없다** → 색 토큰을 직접 정의하는 편이 오히려 단순하다 |
| 색 | `ui/theme/Color.kt` + `values/formchecker_brand.xml` **두 번 적음** ⚠ | **한 곳에만 적는다** (Asset Catalog 또는 Swift 상수 중 하나) |
| 타이포 | Noto Sans KR **가변 폰트 1개** | 🔴 가변 폰트의 weight 축을 SwiftUI에서 바로 고르기 어렵다 → **정적 weight 5개 번들** 또는 Pretendard 검토 |
| 크기 | sp (시스템 글꼴 크기 반영) | **Dynamic Type을 쓸지 결정 필요** — rep 숫자 96pt는 고정이어야 한다 |
| 터치 타겟 | 48dp | **44pt** (HIG) |
| 스켈레톤 오버레이 | Compose `Canvas` | SwiftUI `Canvas` (+ 필요하면 `drawingGroup()`) 또는 `CAShapeLayer` |
| 모서리/간격 | 8pt 그리드, Radius 8/12/16/pill | 그대로 |
| 모션 | 120/240/400ms + rep 펄스 180ms | 그대로 |

### 색 대비 규칙은 그대로 가져온다

- 솔리드 배너 = 색 배경 + **어두운 글자**(5.9~7.5:1)
- 은은한 배지 = `xxxContainer` 배경 + 해당 색 글자(5.2~5.8:1)
- ⚠ Android v1.0에서 "진한 배경 + 흰 글자"가 2.63~2.84:1로 **WCAG AA 미달**이었던 전례가 있다. 새 조합을 만들면 **대비를 계산해서** 넣는다.

---

## 10. 소리 — 대응물이 없다

| | Android | iOS |
|---|---|---|
| 장치 | `ToneGenerator` (시스템 톤 프리셋) | **없음** |
| ACK/NACK | `TONE_PROP_ACK` / `TONE_PROP_NACK` | 직접 만들어야 한다 |
| 스트림 | `STREAM_MUSIC` — 미디어 볼륨 0이면 무음 | `AVAudioSession` 카테고리로 결정 |

**이식 방침**

1. 짧은 톤 8종을 **오디오 파일로 번들**하거나 `AVAudioEngine`으로 합성한다.
2. 🔴 **ACK와 NACK이 사람 귀에 구분되는지 반드시 검증한다.** 2~3m 떨어져 듣는다는 전제를 잊지 말 것.
3. 오디오 세션: 운동 중 음악을 듣는 사용자가 많다 → **다른 앱 소리를 끊지 않는 설정**이 기본.
   ⚠ 그 대신 iOS는 무음 스위치 동작이 카테고리에 따라 갈린다. **어느 쪽을 고르든 "안 들릴 수 있다"를 화면에 알리는 Android의 `soundMuted` 처리를 유지한다.**
4. 🔁 **카운트다운 틱은 줄어들 때만** 울린다 — 침묵이 "아직 안 세고 있다"는 신호다. 이 설계를 깨지 말 것.
5. 🆕 **햅틱을 쓰지 않는다.** 폰이 2~3m 떨어져 있어 사용자에게 닿지 않는다.

---

## 11. 동작 예시 GIF

Android는 플랫폼 `ImageDecoder`로 재생한다(이미지 라이브러리를 들이지 않았다).
**iOS에는 GIF를 재생하는 기본 뷰가 없다.**

| 선택지 | 평가 |
|---|---|
| `CGAnimateImageAtURLWithBlock` (ImageIO) | 의존성 0. 프레임 콜백을 직접 그린다. **권장** |
| GIF → `.mp4` 변환 후 `AVPlayer` | 파일이 작아지고 디코딩이 싸다. ⚠ 오디오 세션을 건드리므로 **무음 설정 필수** |
| 이미지 라이브러리 도입 | **하지 않는다** — Android가 Coil을 안 넣은 것과 같은 이유 (이미지를 쓰는 자리가 하나뿐) |

---

## 12. 권한 · 생명주기 · 중단

| 상황 | Android | iOS |
|---|---|---|
| 권한 요청 | 여러 번 요청 가능 | 🔴 **한 번뿐.** 거부 후에는 설정 앱으로 보내야 한다 |
| 권한 설명 | 런타임 UI | `Info.plist`의 `NSCameraUsageDescription` **없으면 앱이 크래시** |
| 카메라 수명 | `LifecycleOwner`에 바인딩 (자동) | **직접 start/stop** — `onAppear`/`onDisappear`와 scene phase를 모두 다뤄야 한다 |
| 전화·Control Center | — | `AVCaptureSessionWasInterrupted` / `InterruptionEnded` **처리 필수** |
| 화면 꺼짐 | 처리 없음(Android도 미구현) | 🆕 `isIdleTimerDisabled = true` (운동 화면에서만, 나갈 때 반드시 복구) |
| 백그라운드 진입 | 카메라 자동 해제 | 세션 정지 + **진행 중 rep 상태를 어떻게 할지 결정 필요** |

🆕 **결정 필요**: 운동 중 앱이 백그라운드로 갔다 돌아왔을 때 —
① 기준 자세를 다시 재게 할지, ② 그대로 이어갈지. **①을 권장한다** (폰이 움직였을 가능성이 높다).

---

## 13. 백그라운드 동기화 (1.0 범위 밖이지만 설계가 다르다)

| | WorkManager | BGTaskScheduler |
|---|---|---|
| 실행 보장 | 제약 충족 시 **실행을 보장** | **보장하지 않는다.** 시스템이 사용 패턴으로 결정한다 |
| 주기 실행 | `PeriodicWorkRequest` (최소 15분) | `BGAppRefreshTask` — 시점은 시스템이 정한다 |
| 긴 작업 | 제한적 | `BGProcessingTask` (충전/네트워크 조건) |
| 등록 | 코드만 | `Info.plist`에 **식별자 선언 필수** |
| 재시도 | 지수 백오프 내장 | **직접 구현** |

👉 설계 영향: iOS는 "언젠가 동기화된다"를 전제로 할 수 없다. **앱을 열 때 동기화**를 1차 경로로 두고,
배경 작업은 보조로 본다. `sync_status` 컬럼은 **지금 넣어둔다**(나중에 마이그레이션하지 않도록).

---

## 14. 테스트와 벤치마크

| Android | iOS |
|---|---|
| JUnit4 — `:pose-engine` 292 / `:app` 98 | XCTest 또는 Swift Testing. **파일 28개 전부 이식** |
| `DelegateBenchmark` (CPU/GPU p95) | 같은 모양으로 다시 만든다 (CPU / Core ML / Metal) |
| `FramePipelineBenchmark` | `os_signpost` + Instruments |
| `DbQueryBenchmark` | 같은 쿼리를 같은 데이터 규모로 |
| Macrobenchmark 콜드스타트 | MetricKit + XCTest `measure` |
| `MediaMetadataRetriever`로 영상 주입 | `AVAssetReader`로 영상 주입 |

⚠ **대표값은 중앙값이 아니라 p95를 쓴다.** Android가 중앙값을 쓰다 "절반이 그보다 느리다"는
사실이 사라지는 문제를 겪고 바꿨다.

---

## 15. 배포

| 항목 | Android | iOS |
|---|---|---|
| 최소 버전 | `minSdk 24` (2016) | **iOS 17.0 권장** `[확정 필요]` — `videoRotationAngle`·`@Observable` 사용 가능 |
| 기기 하한 | — | 모델 성능상 **A13 이상 권장** `[미검증]` |
| 앱 크기 | 모델 16MB (둘 다 번들) | **11.4MB** (RTMPose만) |
| 모델 압축 | `noCompress += "tflite"` (메모리 매핑) | iOS 번들은 압축하지 않는다 ✅ 자동 |
| 심사 | 없음 | **있다.** 카메라 사용 목적 문구, 개인정보 보호 세부정보(수집 없음) 신고 필요 |

---

## 16. 동등성 체크리스트 (이식 중 계속 본다)

- [x] 색 채널 순서를 BGRA→RGB로 **정확히** 바꿨는가
- [x] 입력 텐서에 **÷255를 하지 않았는가**
- [x] letterbox 패딩이 **검정**이고 `padLeft/padTop` 계산이 같은가
- [x] `inverse()`로 패딩을 **걷어냈는가**
- [x] `bytesPerRow`를 **그대로 썼는가** (`width × 4`로 가정하지 않았는가)
- [ ] 각도 계산에 **종횡비 보정**이 들어갔는가
- [x] 추론 입력을 **미러링하지 않았는가**
- [ ] 판정 불가를 `nil`로 돌려주는가 (`0`·`false` 금지)
- [ ] 임계값 숫자가 **04 문서의 표와 글자 그대로** 같은가
- [ ] rep 단위 판정 2종이 **프레임 경고로 새어 나가지 않는가**
- [ ] 뒤꿈치가 떴을 때 깊이 부족 경고를 **내지 않는가**
- [ ] 피드백 정렬이 **도착 순**인가 (우선순위 순 아님)
- [ ] 촬영 방향이 **다수결**인가 (프레임 단위 아님)

---

## 17. 권장 스택 (확정 전 제안)

| 영역 | 제안 | 대안 | 확정 필요도 |
|---|---|---|---|
| 최소 iOS | **17.0** | 16.0 (커버리지↑, API↓) | 🔴 높음 |
| UI | SwiftUI | — | 낮음 |
| 추론 | **LiteRT + 같은 .tflite** | Core ML 변환 | 🔴 높음 |
| 가속 | **CPU 먼저**, delegate는 측정 후 | — | 중 (측정이 결정) |
| DB | **GRDB.swift** | SwiftData | 🟡 중 |
| 설정 | UserDefaults + `@Observable` | — | 낮음 |
| DI | 직접 주입 | swift-dependencies | 낮음 |
| 폰트 | 정적 weight 번들 | Pretendard | 🟡 중 |
| 패키지 관리 | **SPM + CocoaPods 혼용** (LiteRT가 Pod) | — | 낮음 |

---

## 참고

- [LiteRT iOS 시작하기](https://developers.google.com/edge/litert/ios/quickstart)
- [LiteRT iOS GPU(Metal) delegate](https://developers.google.com/edge/litert/ios/gpu)
- [VNHumanBodyPoseObservation](https://developer.apple.com/documentation/vision/vnhumanbodyposeobservation)
