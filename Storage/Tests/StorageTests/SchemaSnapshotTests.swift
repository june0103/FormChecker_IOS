import Foundation
import GRDB
import XCTest
@testable import Storage

/// 스키마 스냅샷 (FR-DAT-10).
///
/// ## 왜 파일로 박아 두나
/// Android는 Room이 스키마 JSON을 저장소에 export한다. 목적은 백업이 아니라 **리뷰**다 —
/// 마이그레이션이 실제로 무엇을 바꾸는지 diff로 보이지 않으면, 컬럼 하나가 조용히
/// 사라지거나 타입이 바뀌어도 아무도 모른 채 머지된다.
///
/// GRDB에는 그런 export가 없어서 **테스트가 대신 붙든다.** 스키마를 바꾸면 이 테스트가
/// 깨지고, 고치려면 `Storage/schema.sql`을 함께 고쳐야 한다 — 그 diff가 리뷰 대상이다.
///
/// 🔴 **스냅샷을 기계적으로 갱신하지 말 것.** 깨졌다는 것은 "저장된 기록의 모양이
/// 바뀐다"는 뜻이다. 이미 기기에 쌓인 행을 어떻게 할지(마이그레이션) 먼저 정한다.
final class SchemaSnapshotTests: XCTestCase {

    /// 저장소에 박아 둔 스키마 파일.
    private static var snapshotURL: URL {
        // Tests/StorageTests/ → Storage/
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("schema.sql")
    }

    /// 지금 마이그레이션이 만드는 스키마.
    private func currentSchema() throws -> String {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let queue = try AppDatabase.makeQueue(at: folder.appendingPathComponent("snapshot.sqlite"))
        return try queue.read { db in
            // `sqlite_sequence` 같은 내부 테이블은 뺀다 — 우리가 정의한 것이 아니다.
            let rows = try Row.fetchAll(db, sql: """
                SELECT sql FROM sqlite_master
                 WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%'
                 ORDER BY type DESC, name
                """)
            return rows.compactMap { $0["sql"] as String? }.joined(separator: ";\n\n") + ";\n"
        }
    }

    func testSchemaMatchesCheckedInSnapshot() throws {
        let current = try currentSchema()
        let url = Self.snapshotURL

        guard let stored = try? String(contentsOf: url, encoding: .utf8) else {
            // 파일이 없으면 만들어 주고 실패시킨다 — 첫 실행에서 사람이 **보고** 커밋한다.
            try current.write(to: url, atomically: true, encoding: .utf8)
            XCTFail("""
                스키마 스냅샷이 없어서 새로 썼다: \(url.path)
                내용을 확인하고 커밋할 것.
                """)
            return
        }

        XCTAssertEqual(current, stored, """
            스키마가 `Storage/schema.sql`과 다르다.

            마이그레이션을 바꿨다면 **이미 기기에 쌓인 행을 어떻게 할지 먼저 정하고**,
            그 다음에 이 파일을 함께 고칠 것. 스냅샷만 맞추면 그 판단이 통째로 빠진다.
            """)
    }

    /// 🔴 외래키가 꺼지면 세션을 지워도 rep이 남는다 — 기록 화면의 수와 DB가 어긋난다.
    func testForeignKeysAreOn() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let queue = try AppDatabase.makeQueue(at: folder.appendingPathComponent("fk.sqlite"))
        let on = try queue.read { db in try Bool.fetchOne(db, sql: "PRAGMA foreign_keys") }
        XCTAssertEqual(on, true)
    }
}
