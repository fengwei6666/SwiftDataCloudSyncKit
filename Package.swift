// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftDataCloudSyncKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SwiftDataCloudSyncKit",
            targets: ["SwiftDataCloudSyncKit"]
        )
    ],
    targets: [
        .target(
            name: "SwiftDataCloudSyncKit"
        )
    ]
)
