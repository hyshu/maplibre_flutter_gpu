// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "maplibre_flutter_gpu",
    platforms: [
        .iOS("14.3"),
        .macOS("14.3")
    ],
    products: [
        .library(
            name: "maplibre-flutter-gpu",
            targets: ["maplibre_flutter_gpu"]
        )
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .binaryTarget(
            name: "MapLibreBridge",
            path: "Frameworks/MapLibreBridge.xcframework"
        ),
        .target(
            name: "maplibre_flutter_gpu",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                "MapLibreBridge"
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedLibrary("sqlite3"),
                .linkedLibrary("z"),
                .linkedFramework("CFNetwork"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("CoreText"),
                .linkedFramework("Foundation"),
                .linkedFramework("Security"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("Metal", .when(platforms: [.iOS])),
                .linkedFramework("MetalKit", .when(platforms: [.iOS])),
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("CoreImage", .when(platforms: [.macOS])),
                // MapLibre contains Objective-C classes with runtime-only references.
                .unsafeFlags(["-Xlinker", "-ObjC"])
            ]
        )
    ]
)
