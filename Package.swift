// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WireMenu",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "WireMenu",
            exclude: ["Resources"],
            linkerSettings: [
                .linkedFramework("CoreWLAN"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("SystemConfiguration")
            ]
        ),
        .testTarget(
            name: "WireMenuTests",
            dependencies: ["WireMenu"]
        )
    ],
    swiftLanguageModes: [.v5]
)
