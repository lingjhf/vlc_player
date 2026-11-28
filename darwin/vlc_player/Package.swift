// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "vlc_player",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "vlc-player", targets: ["vlc_player"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "vlc_player",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .target(name: "MobileVLCKit", condition: .when(platforms: [.iOS])),
                .target(name: "VLCKit", condition: .when(platforms: [.macOS])),
            ],
            resources: [.process("PrivacyInfo.xcprivacy")],
            linkerSettings: [
                .linkedFramework("AudioToolbox", .when(platforms: [.iOS])),
                .linkedFramework("AVFoundation", .when(platforms: [.iOS])),
                .linkedFramework("CFNetwork", .when(platforms: [.iOS])),
                .linkedFramework("CoreGraphics", .when(platforms: [.iOS])),
                .linkedFramework("CoreMedia", .when(platforms: [.iOS])),
                .linkedFramework("CoreText", .when(platforms: [.iOS])),
                .linkedFramework("OpenGLES", .when(platforms: [.iOS])),
                .linkedFramework("QuartzCore", .when(platforms: [.iOS])),
                .linkedFramework("Security", .when(platforms: [.iOS])),
                .linkedFramework("VideoToolbox", .when(platforms: [.iOS])),
                .linkedLibrary("bz2", .when(platforms: [.iOS])),
                .linkedLibrary("c++", .when(platforms: [.iOS])),
                .linkedLibrary("iconv"),
                .linkedLibrary("xml2", .when(platforms: [.iOS])),
                .linkedLibrary("z", .when(platforms: [.iOS])),
            ]
        ),
        .binaryTarget(
            name: "MobileVLCKit",
            url: "https://github.com/lingjhf/vlc_player/releases/download/mobilevlckit-3.7.5-swiftpm/MobileVLCKit-3.7.5-swiftpm.xcframework.zip",
            checksum: "6460e7c6035329e536be4ec0faf174e5ffd69102a1298dad613a547b573f2b77"
        ),
        .binaryTarget(
            name: "VLCKit",
            url: "https://github.com/lingjhf/vlc_player/releases/download/vlckit-3.7.3-swiftpm/VLCKit-3.7.3-swiftpm.xcframework.zip",
            checksum: "1f1643098865a90113e1fcc92192f31ed73a08b4ba0d5615ccc22d28bb85b83a"
        ),
    ]
)
