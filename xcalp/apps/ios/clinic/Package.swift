// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "XcalpClinic",
    platforms: [.iOS(.v16)],
    products: [
        .library(
            name: "XcalpClinic",
            targets: ["XcalpClinic"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-composable-architecture",
            from: "1.0.0"
        ),
        .package(
            url: "https://github.com/pointfreeco/swift-case-paths",
            from: "1.0.0"
        ),
        .package(
            url: "https://github.com/pointfreeco/swift-dependencies",
            from: "1.0.0"
        ),
        .package(
            url: "https://github.com/pointfreeco/swift-perception",
            from: "1.0.0"
        ),
        .package(
            url: "https://github.com/firebase/firebase-ios-sdk",
            from: "10.0.0"
        ),
        .package(
            url: "https://github.com/kishikawakatsumi/KeychainAccess",
            from: "4.0.0"
        )
    ],
    targets: [
        .target(
            name: "XcalpClinic",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Perception", package: "swift-perception"),
                .product(name: "FirebaseAnalytics", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "KeychainAccess", package: "KeychainAccess"),
                .product(name: "ComposableArchitectureMacros", package: "swift-composable-architecture"),
                .product(name: "CasePathsMacros", package: "swift-case-paths"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "PerceptionMacros", package: "swift-perception")
            ]
        ),
        .testTarget(
            name: "XcalpClinicTests",
            dependencies: ["XcalpClinic"]
        ),
    ]
)
