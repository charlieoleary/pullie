// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Pullie",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Pullie",
            path: "Sources/Pullie",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
