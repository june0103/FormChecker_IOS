// swift-tools-version: 6.0
import PackageDescription

// PoseEngine — 추론과 판정. 카메라·UI·DB에 의존하지 않는다.
//
// 이 경계가 있어야 (1) 기기 없이 단위 테스트가 돌고 (2) 녹화 영상을 같은 파이프라인에
// 주입해 재현 가능한 벤치마크를 돌릴 수 있다. Android `:pose-engine`과 같은 설계다.
// AVFoundation·SwiftUI·DB를 import하는 순간 이 설계가 무너진다.
//
// ThirdParty/ 는 tools/fetch_litert.sh 가 채운다 (저장소에 커밋하지 않는다).
let package = Package(
    name: "PoseEngine",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "PoseEngine", targets: ["PoseEngine"]),
    ],
    targets: [
        .binaryTarget(
            name: "TensorFlowLiteC",
            path: "ThirdParty/TensorFlowLiteC.xcframework"
        ),
        .target(
            name: "PoseEngine",
            dependencies: ["TensorFlowLiteC"],
            resources: [.copy("Resources/rtmpose_s_halpe26_256x192_f16.tflite")],
            linkerSettings: [
                // TensorFlowLiteC는 정적 라이브러리라 C++ 표준 라이브러리를 직접 링크해야 한다.
                // CocoaPods 쪽 podspec이 `libraries: "c++"` 로 해주던 일을 SwiftPM에서는
                // 우리가 적어야 한다 — 빠뜨리면 std::__1::* 미정의 심볼로 링크가 깨진다.
                .linkedLibrary("c++"),
            ]
        ),
        .testTarget(
            name: "PoseEngineTests",
            dependencies: ["PoseEngine"],
            resources: [
                .copy("Resources/images"),
                // Android 기준 키포인트. Phase 0 게이트가 이 파일과 대조한다.
                .copy("Resources/reference"),
            ]
        ),
    ]
)
