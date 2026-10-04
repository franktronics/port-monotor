// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PortMonitor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PortMonitor", targets: ["PortMonitor"])
    ],
    targets: [
        .executableTarget(name: "PortMonitor"),
        .testTarget(name: "PortMonitorTests", dependencies: ["PortMonitor"])
    ],
    swiftLanguageModes: [.v5]
)
