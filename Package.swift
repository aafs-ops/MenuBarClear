// swift-tools-version:5.9
//
// Swift Package manifest so the sources open nicely in Xcode / SourceKit-LSP.
// To build the actual .app bundle, use `make app` (see README).

import PackageDescription

let package = Package(
    name: "MenuBarClear",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MenuBarClear",
            path: "Sources/MenuBarClear",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
