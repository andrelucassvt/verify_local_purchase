// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "verify_local_purchase",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "verify-local-purchase", targets: ["verify_local_purchase"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "verify_local_purchase",
            dependencies: [],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
