// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Mneme",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MnemeCore", targets: ["MnemeCore"]),
        .executable(name: "Mneme", targets: ["Mneme"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.0.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.3")
    ],
    targets: [
        .target(
            name: "MnemeCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .executableTarget(
            name: "Mneme",
            dependencies: [
                "MnemeCore",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers")
            ],
            path: "App"
        ),
        .testTarget(
            name: "MnemeCoreTests",
            dependencies: ["MnemeCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
