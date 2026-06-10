// swift-tools-version:5.9
//
// SPM manifest for cross-platform MeshKit compilation and testing.
// The full Herald library (which requires CoreBluetooth) builds via the .xcodeproj on macOS/iOS.
// This Package.swift enables: swift build && swift test on Linux + macOS.

import PackageDescription

let package = Package(
    name: "Herald",
    products: [
        .library(name: "MeshKit", targets: ["MeshKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
    ],
    targets: [
        .target(
            name: "MeshKit",
            dependencies: [
                // Linux: AES-128-CTR via _CryptoExtras; LinuxStubs.swift provides Herald type stubs
                .product(name: "Crypto", package: "swift-crypto",
                         condition: .when(platforms: [.linux])),
                .product(name: "_CryptoExtras", package: "swift-crypto",
                         condition: .when(platforms: [.linux]))
            ],
            path: "Herald/Herald/MeshKit"
        ),
        .testTarget(
            name: "MeshKitTests",
            dependencies: ["MeshKit"],
            path: "Herald/HeraldTests/MeshKit"
        )
    ],
    swiftLanguageVersions: [.v5]
)
