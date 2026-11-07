// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "maplibre_flutter_gpu",
    platforms: [
        .iOS("15.5"),
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
            ]
        )
    ]
)
