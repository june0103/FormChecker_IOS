import Foundation

/// 키포인트 인덱스. **Halpe26 순서**를 따른다.
///
/// 0~16번은 COCO17과 동일하다. 17~25번(Head/Neck/Hip + 발 6개)은 Halpe26 모델만 출력한다.
///
/// 발 키포인트(20~25)가 이 모델을 쓰는 이유다 — 뒤꿈치 들림과 무릎–발끝 판정이 여기에 달려 있다.
/// Apple Vision의 신체 키포인트 19개에도, MoveNet의 COCO17에도 발이 없다.
public enum KeypointType: Int, CaseIterable, Sendable {
    // ── COCO17 ────────────────────────────────────────────
    case nose = 0
    case leftEye = 1
    case rightEye = 2
    case leftEar = 3
    case rightEar = 4
    case leftShoulder = 5
    case rightShoulder = 6
    case leftElbow = 7
    case rightElbow = 8
    case leftWrist = 9
    case rightWrist = 10
    case leftHip = 11
    case rightHip = 12
    case leftKnee = 13
    case rightKnee = 14
    case leftAnkle = 15
    case rightAnkle = 16

    // ── Halpe26 확장 ──────────────────────────────────────
    /// 머리 중심. 코·귀와 겹쳐 보이므로 표시·판정에 쓰지 않는다.
    case head = 17
    /// 목. 어깨 중점과 사실상 같은 위치라 표시하지 않는다.
    case neck = 18
    /// 골반 중심. 좌우 힙 중점과 겹치므로 표시하지 않는다.
    case hipCenter = 19
    case leftBigToe = 20
    case rightBigToe = 21
    case leftSmallToe = 22
    case rightSmallToe = 23
    /// 뒤꿈치. 발뒤꿈치 들림 판정의 핵심이며 MoveNet·Vision에는 없다.
    case leftHeel = 24
    case rightHeel = 25

    /// COCO17 부분집합 크기.
    public static let coco17Count = 17

    /// MoveNet(COCO17)이 출력하는 범위인가.
    public var isCoco17: Bool { rawValue < Self.coco17Count }

    public static let count = KeypointType.allCases.count
}

/// 키포인트 하나.
///
/// `x`, `y`는 **letterbox가 제거된 원본 프레임 기준 0~1 정규화 좌표**다.
/// 모델이 내놓는 좌표는 패딩이 적용된 입력 기준이라 그대로 쓰면 패딩만큼 어긋난다.
///
/// 픽셀이 아니라 정규화 좌표를 유지하는 이유는 기기·해상도마다 프레임 크기가 다르기
/// 때문이다. 화면에 그릴 때만 실제 크기를 곱한다.
public struct Keypoint: Sendable, Equatable {
    public let type: KeypointType
    public let x: Float
    public let y: Float
    public let confidence: Float

    public init(type: KeypointType, x: Float, y: Float, confidence: Float) {
        self.type = type
        self.x = x
        self.y = y
        self.confidence = confidence
    }
}

/// 한 프레임의 추론 결과.
public struct Pose: Sendable {
    public let keypoints: [Keypoint]
    /// 설계문서 8장의 추론 지연(avg/p95) 측정에 쓴다.
    public let inferenceTimeNanos: UInt64

    public init(keypoints: [Keypoint], inferenceTimeNanos: UInt64) {
        self.keypoints = keypoints
        self.inferenceTimeNanos = inferenceTimeNanos
    }

    public subscript(type: KeypointType) -> Keypoint { keypoints[type.rawValue] }

    /// `minConfidence` 이상인 키포인트만 신뢰할 수 있다고 본다.
    public func isReliable(_ type: KeypointType, minConfidence: Float = Pose.minConfidence) -> Bool {
        self[type].confidence >= minConfidence
    }

    /// confidence 0.3 미만은 무효로 보고 스킵한다(저조도·가려짐 대응).
    /// **에러가 아니라 정상적인 스킵 경로다.**
    public static let minConfidence: Float = 0.3
}
