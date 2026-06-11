// swift-tools-version: 5.9
// Dev-only manifest: compiles the platform-independent game engines on macOS
// for fast iteration and unit tests. The app itself is built from Parlor.xcodeproj.
import PackageDescription

let package = Package(
    name: "EngineCheck",
    targets: [
        .target(
            name: "EngineCheck",
            path: "Parlor",
            sources: ["Model", "Engine"]
        ),
        .testTarget(
            name: "EngineCheckTests",
            dependencies: ["EngineCheck"],
            path: "EngineCheck/Tests"
        ),
    ]
)
