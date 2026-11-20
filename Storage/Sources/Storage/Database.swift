import Foundation
import GRDB

/// 로컬 데이터베이스.
///
/// 🔴 **로컬이 1차 저장소다.** 네트워크 실패가 운동 흐름을 막지 않아야 한다. 서버는
/// 아직 없지만 모든 행이 `sync_status = PENDING`으로 쌓인다.
///
/// ## 왜 SwiftData가 아닌가
/// Supabase DDL이 정본이고 **양 플랫폼이 같은 모양을 유지해야 한다.** SwiftData는 SQL을
/// 감추고, Android가 저장소에 커밋해 둔 스키마 JSON에 해당하는 것도 없다. 기록이 쌓였을
/// 때의 쿼리를 Android에서 이미 한 번 고쳤는데(`DbQueryBenchmark`), 같은 인덱스를 쓰려면
/// SQL이 보여야 한다.
public enum AppDatabase {

    /// 앱 전역 하나. 같은 파일에 두 개를 열면 조용히 갈린다.
    public static let shared: DatabaseQueue = {
        do {
            return try makeQueue(at: defaultURL())
        } catch {
            // 저장소를 못 열면 기록만 못 남긴다 — 운동은 그대로 돼야 한다.
            // 메모리 DB로 떨어뜨려 앱이 죽지 않게 한다.
            return try! DatabaseQueue()
        }
    }()

    public static func defaultURL() throws -> URL {
        let folder = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        return folder.appendingPathComponent("formchecker.sqlite")
    }

    public static func makeQueue(at url: URL) throws -> DatabaseQueue {
        var config = Configuration()
        // 외래키를 켜지 않으면 `ON DELETE CASCADE`가 **동작하지 않는다.**
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(path: url.path, configuration: config)
        try migrator.migrate(queue)
        return queue
    }

    /// 마이그레이션. **스키마 변경은 여기에만 쌓는다** — 지난 버전을 고치지 않는다.
    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_workout") { db in
            try db.create(table: "workout_sessions") { t in
                t.column("id", .text).primaryKey()
                t.column("user_id", .text)
                t.column("exercise_type", .text).notNull().defaults(to: "squat")
                t.column("device_model", .text)
                t.column("os_version", .text)
                t.column("pose_model", .text)
                t.column("started_at", .integer).notNull()
                t.column("ended_at", .integer)
                t.column("form_thresholds", .text)
                t.column("sync_status", .text).notNull().defaults(to: "PENDING")
            }
            // 기록 목록·홈 집계가 전부 시작 시각 범위로 자른다.
            try db.create(index: "idx_sessions_started_at",
                          on: "workout_sessions", columns: ["started_at"])

            try db.create(table: "workout_sets") { t in
                t.column("id", .text).primaryKey()
                t.column("session_id", .text).notNull()
                    .references("workout_sessions", onDelete: .cascade)
                t.column("set_number", .integer).notNull().defaults(to: 1)
                t.column("target_reps", .integer)
                t.column("completed_reps", .integer).notNull().defaults(to: 0)
                t.column("sync_status", .text).notNull().defaults(to: "PENDING")
            }
            try db.create(index: "idx_sets_session_id", on: "workout_sets", columns: ["session_id"])

            try db.create(table: "rep_records") { t in
                t.column("id", .text).primaryKey()
                t.column("set_id", .text).notNull()
                    .references("workout_sets", onDelete: .cascade)
                t.column("rep_number", .integer).notNull()
                t.column("recorded_at", .integer).notNull()
                t.column("duration_ms", .integer).notNull()
                t.column("depth_score", .double)
                t.column("form_score", .double)          // ⚠ 항상 null
                t.column("checked_count", .integer).notNull()
                t.column("warned_count", .integer).notNull()
                t.column("is_valid", .boolean).notNull().defaults(to: true)
                t.column("error_flags", .text).notNull()
                t.column("camera_angle", .text).notNull()
                t.column("depth_level", .text)
                t.column("depth_basis", .text)
                t.column("depth_ratio", .double)
                t.column("min_knee_angle", .double)
                t.column("max_torso_lean", .double)
                t.column("valid_frame_ratio", .double).notNull()
                t.column("knee_toe_side", .text)
                t.column("warning_phases", .text)
                t.column("relaxed_form", .boolean)
                t.column("knee_tolerance", .double)
                t.column("shallow_tolerance", .double)
                t.column("sync_status", .text).notNull().defaults(to: "PENDING")
            }
            try db.create(index: "idx_reps_set_id", on: "rep_records", columns: ["set_id"])

            try db.create(table: "performance_metrics") { t in
                t.column("id", .text).primaryKey()
                t.column("session_id", .text).notNull()
                    .references("workout_sessions", onDelete: .cascade)
                t.column("model_load_ms", .integer)
                t.column("avg_inference_ms", .double)
                t.column("p95_inference_ms", .double)
                t.column("dropped_frame_ratio", .double)
                t.column("avg_fps", .double)
                t.column("delegate_type", .text)
                t.column("analyzed_frame_count", .integer).notNull()
                t.column("created_at", .integer).notNull()
                t.column("sync_status", .text).notNull().defaults(to: "PENDING")
            }
            try db.create(index: "idx_metrics_session_id",
                          on: "performance_metrics", columns: ["session_id"])
        }

        return migrator
    }
}
