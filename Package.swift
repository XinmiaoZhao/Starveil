// swift-tools-version: 6.0

import Foundation
import PackageDescription

let packageRoot = FileManager.default.currentDirectoryPath
let condaInclude = "\(packageRoot)/.conda/include"
let condaLib = "\(packageRoot)/.conda/lib"

let package = Package(
    name: "MySequator",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MySequatorCore", targets: ["MySequatorCore"]),
        .executable(name: "mysequator-swift", targets: ["mysequator-swift"]),
        .executable(name: "MySequatorApp", targets: ["MySequatorApp"]),
        .executable(name: "MySequatorCoreTestRunner", targets: ["MySequatorCoreTestRunner"]),
    ],
    targets: [
        .target(
            name: "CMySequatorSupport",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-O3", "-iquote", condaInclude])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L", condaLib,
                    "-lraw",
                    "-ltiff",
                    "-Xlinker", "-rpath",
                    "-Xlinker", condaLib,
                ]),
                .linkedFramework("Accelerate"),
            ]
        ),
        .target(
            name: "MySequatorCore",
            dependencies: ["CMySequatorSupport"],
            swiftSettings: [
                .unsafeFlags(["-O"], .when(configuration: .debug))
            ],
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .executableTarget(
            name: "mysequator-swift",
            dependencies: ["MySequatorCore"]
        ),
        .executableTarget(
            name: "MySequatorApp",
            dependencies: ["MySequatorCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .executableTarget(
            name: "MySequatorCoreTestRunner",
            dependencies: ["MySequatorCore"]
        ),
        .testTarget(
            name: "MySequatorCoreTests",
            dependencies: ["MySequatorCore"],
            path: "tests/MySequatorCoreTests"
        ),
    ]
)
