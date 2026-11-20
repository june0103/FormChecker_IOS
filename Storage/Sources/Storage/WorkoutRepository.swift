import Foundation
import GRDB
import PoseEngine

/// 기록 목록 한 줄. 화면이 쓰는 모양으로 DB가 미리 집계한다.
///
/// 🔴 **rep 행을 화면으로 끌어오지 않는다** — 기록이 쌓이면 그대로 느려진다.
public struct SessionListItem: Identifiable, Sendable, FetchableRecord, Decodable {
    public var id: String
    public var startedAt: Int64
    public var endedAt: Int64?
    public var repCount: Int
    /// 경고가 하나라도 난 rep 수. **"피드백 횟수"**로 보여준다.
    public var warnedRepCount: Int
    public var pendingCount: Int

    public init(id: String, startedAt: Int64, endedAt: Int64? = nil,
                repCount: Int, warnedRepCount: Int = 0, pendingCount: Int = 0) {
        self.id = id; self.startedAt = startedAt; self.endedAt = endedAt
        self.repCount = repCount; self.warnedRepCount = warnedRepCount
        self.pendingCount = pendingCount
    }

    enum CodingKeys: String, CodingKey {
        case id
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case repCount = "rep_count"
        case warnedRepCount = "warned_rep_count"
        case pendingCount = "pending_count"
    }
}

/// 세션 하나의 횟수. 홈 그래프가 쓰는 **최소한의 모양**이다.
public struct SessionRepCount: Identifiable, Sendable, FetchableRecord, Decodable {
    public var id: String
    public var startedAt: Int64
    public var repCount: Int

    public init(id: String, startedAt: Int64, repCount: Int) {
        self.id = id; self.startedAt = startedAt; self.repCount = repCount
    }

    enum CodingKeys: String, CodingKey {
        case id
        case startedAt = "started_at"
        case repCount = "rep_count"
    }
}

/// 저장과 조회.
///
/// 🔴 **저장소는 "저장할지 말지"를 판단하지 않는다** — 부르면 그대로 저장한다.
/// 0회 세션을 거르는 것은 호출부(운동 화면)의 몫이다.
public struct WorkoutRepository: Sendable {

    public let queue: DatabaseQueue

    public init(queue: DatabaseQueue = AppDatabase.shared) {
        self.queue = queue
    }

    // ── 저장 ────────────────────────────────────────────────

    @discardableResult
    public func save(
        session: WorkoutSession,
        reps: [RepRecord],
        metrics: PerformanceMetrics?
    ) throws -> String {
        try queue.write { db in
            try session.insert(db)
            // 세트 개념이 아직 없다. 세션당 1행.
            let set = WorkoutSet(id: UUID().uuidString, sessionId: session.id,
                                 completedReps: reps.count)
            try set.insert(db)
            for var rep in reps {
                rep.setId = set.id
                try rep.insert(db)
            }
            if let metrics { try metrics.insert(db) }
        }
        return session.id
    }

    // ── 조회 ────────────────────────────────────────────────

    public func recentSessions(limit: Int = 50) throws -> [SessionListItem] {
        try queue.read { db in
            try SessionListItem.fetchAll(db, sql: """
                SELECT s.id,
                       s.started_at,
                       s.ended_at,
                       COUNT(r.id)                                      AS rep_count,
                       COALESCE(SUM(CASE WHEN r.warned_count > 0 THEN 1 ELSE 0 END), 0)
                                                                        AS warned_rep_count,
                       COALESCE(SUM(CASE WHEN r.sync_status = 'PENDING' THEN 1 ELSE 0 END), 0)
                                                                        AS pending_count
                  FROM workout_sessions s
                  LEFT JOIN workout_sets  t ON t.session_id = s.id
                  LEFT JOIN rep_records   r ON r.set_id     = t.id
                 GROUP BY s.id
                 ORDER BY s.started_at DESC
                 LIMIT ?
                """, arguments: [limit])
        }
    }

    /// 주 범위만 잘라 **세션별 횟수**를 낸다.
    ///
    /// 🔴 **rep 행을 홈으로 끌어오지 않는다** — 기록이 쌓이면 홈이 그대로 느려진다.
    /// 요일 칸으로 나누는 것은 `weeklyReps`가 한다. DB는 자르기만 한다.
    public func sessionRepCounts(from: Int64, to: Int64) throws -> [SessionRepCount] {
        try queue.read { db in
            try SessionRepCount.fetchAll(db, sql: """
                SELECT s.id,
                       s.started_at,
                       COUNT(r.id) AS rep_count
                  FROM workout_sessions s
                  LEFT JOIN workout_sets  t ON t.session_id = s.id
                  LEFT JOIN rep_records   r ON r.set_id     = t.id
                 WHERE s.started_at >= ? AND s.started_at < ?
                 GROUP BY s.id
                 ORDER BY s.started_at
                """, arguments: [from, to])
        }
    }

    /// 기록이 하나라도 있나를 가리는 데 쓴다 — **"아직 아무것도 안 했다"와
    /// "이번 주만 비었다"는 다른 화면이다.**
    public func sessionCount() throws -> Int {
        try queue.read { db in try WorkoutSession.fetchCount(db) }
    }

    public func session(id: String) throws -> WorkoutSession? {
        try queue.read { db in try WorkoutSession.fetchOne(db, key: id) }
    }

    public func reps(sessionId: String) throws -> [RepRecord] {
        try queue.read { db in
            try RepRecord.fetchAll(db, sql: """
                SELECT r.* FROM rep_records r
                  JOIN workout_sets t ON t.id = r.set_id
                 WHERE t.session_id = ?
                 ORDER BY r.rep_number
                """, arguments: [sessionId])
        }
    }

    public func metrics(sessionId: String) throws -> PerformanceMetrics? {
        try queue.read { db in
            try PerformanceMetrics.filter(Column("session_id") == sessionId).fetchOne(db)
        }
    }

    @discardableResult
    public func delete(sessionId: String) throws -> Bool {
        try queue.write { db in
            try WorkoutSession.deleteOne(db, key: sessionId)
        }
    }

    /// 업로드 대기 수. 기록 화면이 **정직하게 배지로** 보여준다.
    public func pendingCount() throws -> Int {
        try queue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT (SELECT COUNT(*) FROM workout_sessions WHERE sync_status = 'PENDING')
                     + (SELECT COUNT(*) FROM rep_records      WHERE sync_status = 'PENDING')
                """) ?? 0
        }
    }
}

// ─────────────────────────────────────────────────────────────

/// 저장된 rep 행 ↔ 리포트 입력.
///
/// 🔴 **같은 매핑을 두 곳에 적지 않는다** — 저장과 화면이 다른 답을 쓰면 안 된다.
public enum RepRecordMapping {

    public static func errorFlags(_ warnings: Set<FormWarning>, checks: Set<FormWarning>) -> String {
        var flags: [String: Bool] = [:]
        for check in checks { flags[check.rawValue] = warnings.contains(check) }
        return json(flags)
    }

    public static func warnings(fromFlags text: String) -> Set<FormWarning> {
        guard let data = text.data(using: .utf8),
              let flags = try? JSONDecoder().decode([String: Bool].self, from: data)
        else { return [] }
        return Set(flags.compactMap { key, on in on ? FormWarning(rawValue: key) : nil })
    }

    public static func phases(_ map: [FormWarning: Set<RepPhase>]) -> String? {
        if map.isEmpty { return nil }
        let plain = map.reduce(into: [String: [String]]()) { result, entry in
            result[entry.key.rawValue] = entry.value.map(\.rawValue).sorted()
        }
        return json(plain)
    }

    public static func phases(fromJSON text: String?) -> [FormWarning: Set<RepPhase>] {
        guard let text, let data = text.data(using: .utf8),
              let plain = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return plain.reduce(into: [FormWarning: Set<RepPhase>]()) { result, entry in
            guard let warning = FormWarning(rawValue: entry.key) else { return }
            result[warning] = Set(entry.value.compactMap(RepPhase.init(rawValue:)))
        }
    }

    /// 저장된 행에서 리포트 입력을 되살린다.
    ///
    /// **구간을 기록하지 않은 과거 기록은 아무것도 말하지 않는다** — 모를 때 지어내지 않는다.
    public static func reported(_ record: RepRecord) -> ReportedRep {
        ReportedRep(
            cameraAngle: CameraAngle(rawValue: record.cameraAngle) ?? .side,
            checkedCount: record.checkedCount,
            warnings: warnings(fromFlags: record.errorFlags),
            depthLevel: record.depthLevel.flatMap(DepthLevel.init(rawValue:)),
            depthScore: record.depthScore.map(Float.init),
            kneeToeSide: record.kneeToeSide.flatMap(Side.init(rawValue:)),
            warningPhases: phases(fromJSON: record.warningPhases)
        )
    }

    private static func json<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}
