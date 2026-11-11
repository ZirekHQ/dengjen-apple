// swift-tools-version:5.9
import PackageDescription

// Pure Swift logic shared by the host app and the speech extension. It never touches the C API or
// AVFoundation, so `swift test` covers it on any Mac (and on Linux).
let package = Package(
    name: "DengjenCore",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "DengjenCore", targets: ["DengjenCore"]),
    ],
    targets: [
        .target(name: "DengjenCore"),
        .testTarget(name: "DengjenCoreTests", dependencies: ["DengjenCore"]),
    ]
)
