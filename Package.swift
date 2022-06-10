// swift-tools-version:5.6

import PackageDescription

let package = Package(
    name: "xcdoctor",
    platforms: [
        .macOS(.v10_11)
    ],
    products: [
        .executable(name: "xcdoctor", targets: ["CLI"]),
        .library(name: "XCDoctor", targets: ["XCDoctor"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.1.2")
    ],
    targets: [
        .executableTarget(
            name: "CLI",
            dependencies: [
                "XCDoctor",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "XCDoctor"
        ),
        .testTarget(
            name: "XCDoctorTests",
            dependencies: ["XCDoctor"],
            path: "Tests",
            exclude: ["Subjects"]
        ),
    ]
)
