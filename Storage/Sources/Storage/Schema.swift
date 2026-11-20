import Foundation
import GRDB

/// 동기화 상태. 서버는 아직 없지만 **컬럼은 지금 넣는다** — 나중에 마이그레이션으로
/// 붙이면 그 사이에 쌓인 행의 상태를 알 수 없다.
public enum SyncStatus: String, Codable, Sendable, DatabaseValueConvertible {
    case pending = "PENDING"
    case synced = "SYNCED"
    case failed = "FAILED"
}

/// 운동 세션.
///
/// `id`는 **클라이언트가 UUID로 미리 만든다** — 오프라인 큐에서 재전송해도 upsert로
/// 멱등 처리된다.
public struct WorkoutSession: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "workout_sessions"

    public var id: String
    /// 인증 미구현 구간에는 nil. 나중에 마이그레이션으로 채운다.
    public var userId: String?
    public var exerciseType: String = "squat"
    public var deviceModel: String?
    public var osVersion: String?
    public var poseModel: String?
    public var startedAt: Int64
    public var endedAt: Int64?
    /// 나머지 임계값 전부의 스냅샷.
    ///
    /// 🔴 **형식을 정하지 않은 것이 의도다.** 손으로 필드를 나열하면 임계값을 새로 추가한
    /// 사람이 여기를 고쳐야 하는 줄 모른다.
    public var formThresholds: String?
    public var syncStatus: SyncStatus = .pending

    public init(
        id: String, userId: String? = nil, exerciseType: String = "squat",
        deviceModel: String? = nil, osVersion: String? = nil, poseModel: String? = nil,
        startedAt: Int64, endedAt: Int64? = nil, formThresholds: String? = nil,
        syncStatus: SyncStatus = .pending
    ) {
        self.id = id; self.userId = userId; self.exerciseType = exerciseType
        self.deviceModel = deviceModel; self.osVersion = osVersion; self.poseModel = poseModel
        self.startedAt = startedAt; self.endedAt = endedAt
        self.formThresholds = formThresholds; self.syncStatus = syncStatus
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case exerciseType = "exercise_type"
        case deviceModel = "device_model"
        case osVersion = "os_version"
        case poseModel = "pose_model"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case formThresholds = "form_thresholds"
        case syncStatus = "sync_status"
    }
}

/// 세트. **세션당 1행이다** — 세트 개념이 아직 없고, `rep_records`가 `set_id`를 참조하는
/// DDL을 지키기 위해 둔다.
public struct WorkoutSet: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "workout_sets"

    public var id: String
    public var sessionId: String
    public var setNumber: Int = 1
    public var targetReps: Int?
    public var completedReps: Int = 0
    public var syncStatus: SyncStatus = .pending

    public init(id: String, sessionId: String, setNumber: Int = 1,
                targetReps: Int? = nil, completedReps: Int = 0,
                syncStatus: SyncStatus = .pending) {
        self.id = id; self.sessionId = sessionId; self.setNumber = setNumber
        self.targetReps = targetReps; self.completedReps = completedReps
        self.syncStatus = syncStatus
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case setNumber = "set_number"
        case targetReps = "target_reps"
        case completedReps = "completed_reps"
        case syncStatus = "sync_status"
    }
}

/// rep 하나의 기록.
///
/// 🔴 **점수 대신 사실을 저장한다.** `formScore`는 항상 nil이고 `checkedCount` /
/// `warnedCount`로 대체한다 — 경고 7종에 가중치를 매길 근거가 없고, 숫자 하나로 뭉치면
/// 무엇을 고쳐야 하는지도 함께 사라진다.
///
/// 🔴 **어느 기준으로 판정했는지를 함께 남긴다**(`relaxedForm`·`kneeTolerance`·
/// `shallowTolerance`) — 나중에 임계값을 재분석할 때 섞인 데이터가 되지 않도록.
public struct RepRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "rep_records"

    public var id: String
    public var setId: String
    public var repNumber: Int
    public var recordedAt: Int64
    public var durationMs: Int64

    /// 패럴렐 도달률 0~1. **측면 전용**(정면은 영구히 nil).
    public var depthScore: Double?
    /// ⚠ **항상 nil이다.** 위 주석 참고.
    public var formScore: Double?
    public var checkedCount: Int
    public var warnedCount: Int
    public var isValid: Bool = true
    /// `{"shallow_depth":true,...}` — 임계값이 바뀌면 재계산할 수 있게 원값과 함께 남긴다.
    public var errorFlags: String
    /// 🔴 이 컬럼이 없으면 nil이 "판정 불가"인지 "측정 실패"인지 구분할 수 없다.
    public var cameraAngle: String

    public var depthLevel: String?
    public var depthBasis: String?
    public var depthRatio: Double?
    public var minKneeAngle: Double?
    public var maxTorsoLean: Double?
    public var validFrameRatio: Double
    public var kneeToeSide: String?
    public var warningPhases: String?

    public var relaxedForm: Bool?
    public var kneeTolerance: Double?
    public var shallowTolerance: Double?
    public var syncStatus: SyncStatus = .pending

    public init(
        id: String, setId: String, repNumber: Int, recordedAt: Int64, durationMs: Int64,
        depthScore: Double? = nil, formScore: Double? = nil,
        checkedCount: Int, warnedCount: Int, isValid: Bool = true,
        errorFlags: String, cameraAngle: String,
        depthLevel: String? = nil, depthBasis: String? = nil, depthRatio: Double? = nil,
        minKneeAngle: Double? = nil, maxTorsoLean: Double? = nil,
        validFrameRatio: Double, kneeToeSide: String? = nil, warningPhases: String? = nil,
        relaxedForm: Bool? = nil, kneeTolerance: Double? = nil, shallowTolerance: Double? = nil,
        syncStatus: SyncStatus = .pending
    ) {
        self.id = id; self.setId = setId; self.repNumber = repNumber
        self.recordedAt = recordedAt; self.durationMs = durationMs
        self.depthScore = depthScore; self.formScore = formScore
        self.checkedCount = checkedCount; self.warnedCount = warnedCount
        self.isValid = isValid; self.errorFlags = errorFlags; self.cameraAngle = cameraAngle
        self.depthLevel = depthLevel; self.depthBasis = depthBasis; self.depthRatio = depthRatio
        self.minKneeAngle = minKneeAngle; self.maxTorsoLean = maxTorsoLean
        self.validFrameRatio = validFrameRatio; self.kneeToeSide = kneeToeSide
        self.warningPhases = warningPhases; self.relaxedForm = relaxedForm
        self.kneeTolerance = kneeTolerance; self.shallowTolerance = shallowTolerance
        self.syncStatus = syncStatus
    }

    enum CodingKeys: String, CodingKey {
        case id
        case setId = "set_id"
        case repNumber = "rep_number"
        case recordedAt = "recorded_at"
        case durationMs = "duration_ms"
        case depthScore = "depth_score"
        case formScore = "form_score"
        case checkedCount = "checked_count"
        case warnedCount = "warned_count"
        case isValid = "is_valid"
        case errorFlags = "error_flags"
        case cameraAngle = "camera_angle"
        case depthLevel = "depth_level"
        case depthBasis = "depth_basis"
        case depthRatio = "depth_ratio"
        case minKneeAngle = "min_knee_angle"
        case maxTorsoLean = "max_torso_lean"
        case validFrameRatio = "valid_frame_ratio"
        case kneeToeSide = "knee_toe_side"
        case warningPhases = "warning_phases"
        case relaxedForm = "relaxed_form"
        case kneeTolerance = "knee_tolerance"
        case shallowTolerance = "shallow_tolerance"
        case syncStatus = "sync_status"
    }
}

/// 성능 리포트. 사용자 화면에서는 끄고 개발용 화면에서만 켠다.
public struct PerformanceMetrics: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "performance_metrics"

    public var id: String
    public var sessionId: String
    /// 엔진 초기화 구간이다. **앱 콜드스타트가 아니다.**
    public var modelLoadMs: Int64?
    public var avgInferenceMs: Double?
    public var p95InferenceMs: Double?
    public var droppedFrameRatio: Double?
    public var avgFps: Double?
    public var delegateType: String?
    public var analyzedFrameCount: Int
    public var createdAt: Int64
    public var syncStatus: SyncStatus = .pending

    public init(
        id: String, sessionId: String, modelLoadMs: Int64? = nil,
        avgInferenceMs: Double? = nil, p95InferenceMs: Double? = nil,
        droppedFrameRatio: Double? = nil, avgFps: Double? = nil, delegateType: String? = nil,
        analyzedFrameCount: Int, createdAt: Int64, syncStatus: SyncStatus = .pending
    ) {
        self.id = id; self.sessionId = sessionId; self.modelLoadMs = modelLoadMs
        self.avgInferenceMs = avgInferenceMs; self.p95InferenceMs = p95InferenceMs
        self.droppedFrameRatio = droppedFrameRatio; self.avgFps = avgFps
        self.delegateType = delegateType; self.analyzedFrameCount = analyzedFrameCount
        self.createdAt = createdAt; self.syncStatus = syncStatus
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case modelLoadMs = "model_load_ms"
        case avgInferenceMs = "avg_inference_ms"
        case p95InferenceMs = "p95_inference_ms"
        case droppedFrameRatio = "dropped_frame_ratio"
        case avgFps = "avg_fps"
        case delegateType = "delegate_type"
        case analyzedFrameCount = "analyzed_frame_count"
        case createdAt = "created_at"
        case syncStatus = "sync_status"
    }
}
