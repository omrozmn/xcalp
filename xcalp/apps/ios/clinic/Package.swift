// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "XcalpClinic",
    platforms: [
        .iOS(.v17),  // Updated to iOS 17 for latest ARKit features
        .macOS(.v14)  // Added macOS support for development
    ],
    products: [
        .library(
            name: "XcalpClinic",
            targets: ["XcalpClinic"]
        ),
        .executable(
            name: "XcalpClinicApp",
            targets: ["XcalpClinicApp"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-composable-architecture",
            exact: "1.17.1"
        ),
        .package(
            url: "https://github.com/pointfreeco/swift-case-paths",
            exact: "1.6.1"
        ),
        .package(
            url: "https://github.com/pointfreeco/swift-dependencies",
            exact: "1.7.0"
        ),
        .package(
            url: "https://github.com/pointfreeco/swift-perception",
            exact: "1.5.0"
        ),
        .package(
            url: "https://github.com/apple/swift-syntax",
            from: "509.0.0"
        ),
        .package(
            url: "https://github.com/firebase/firebase-ios-sdk",
            exact: "10.29.0"
        ),
        .package(
            url: "https://github.com/kishikawakatsumi/KeychainAccess",
            exact: "4.2.2"
        )
    ],
    targets: [
        .target(
            name: "Core",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "KeychainAccess", package: "KeychainAccess")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
                .enableUpcomingFeature("BareSlashRegexLiterals"),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "XcalpClinic",
            dependencies: [
                "Core",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "ComposableArchitectureMacros", package: "swift-composable-architecture"),
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "CasePathsMacros", package: "swift-case-paths"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "Perception", package: "swift-perception"),
                .product(name: "PerceptionMacros", package: "swift-perception"),
                .product(name: "FirebaseAnalytics", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "KeychainAccess", package: "KeychainAccess")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "XcalpClinicApp",
            dependencies: [
                "XcalpClinic",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ]
        ),
        .testTarget(
            name: "XcalpClinicTests",
            dependencies: [
                "XcalpClinic"
            ]
        )
    ]
)
