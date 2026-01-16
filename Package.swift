// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "aerospace-invader",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "aerospace-invader", targets: ["aerospace-invader"]),
        .library(name: "AerospaceInvaderCore", targets: ["AerospaceInvaderCore"])
    ],
    targets: [
        .target(
            name: "AerospaceInvaderCore",
            dependencies: []
        ),
        .executableTarget(
            name: "aerospace-invader",
            dependencies: ["AerospaceInvaderCore"]
        ),
        .testTarget(
            name: "AerospaceInvaderCoreTests",
            dependencies: ["AerospaceInvaderCore"]
        )
    ]
)
