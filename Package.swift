// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SketchyControls",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SketchyControlsCore", targets: ["SketchyControlsCore"]),
        .library(name: "HerdrCore", targets: ["HerdrCore"]),
        .executable(name: "SketchyControls", targets: ["SketchyControls"]),
        .executable(name: "SketchyControlsCLI", targets: ["SketchyControlsCLI"]),
        .executable(name: "HerdrControlsHelper", targets: ["HerdrControlsHelper"]),
        .executable(name: "SketchyControlsCoreChecks", targets: ["SketchyControlsCoreChecks"]),
    ],
    targets: [
        .target(name: "SketchyControlsCore"),
        .target(name: "HerdrCore"),
        .executableTarget(
            name: "SketchyControls",
            dependencies: ["SketchyControlsCore", "HerdrCore"],
            exclude: ["Resources"]
        ),
        .executableTarget(name: "SketchyControlsCLI", dependencies: ["SketchyControlsCore"]),
        .executableTarget(name: "HerdrControlsHelper", dependencies: ["SketchyControlsCore"]),
        .executableTarget(
            name: "SketchyControlsCoreChecks",
            dependencies: ["SketchyControlsCore", "HerdrCore"]
        ),
    ]
)
