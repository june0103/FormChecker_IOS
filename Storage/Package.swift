// swift-tools-version: 6.0
import PackageDescription

// Storage — 로컬 저장소. 화면·카메라에 의존하지 않는다.
//
// 🔴 **로컬이 1차 저장소다.** 네트워크 실패가 운동 흐름을 막지 않아야 한다.
// PoseEngine과 같은 이유로 패키지로 떼어 둔다 — 기기 없이 테스트가 돈다.
let package = Package(
    name: "Storage",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Storage", targets: ["Storage"]),
    ],
    dependencies: [
        // 버전은 검색 요약이 아니라 GitHub 릴리스를 직접 조회해 고정했다 (7.12.0, 2026-11-01).
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.12.0"),
        .package(path: "../PoseEngine"),
    ],
    targets: [
        .target(
            name: "Storage",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "PoseEngine", package: "PoseEngine"),
            ]
        ),
        .testTarget(name: "StorageTests", dependencies: ["Storage"]),
    ]
)
