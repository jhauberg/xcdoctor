// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "xcdoctor",
    platforms: [
        .macOS(.v10_11),
    ],
    products: [
        .executable(name: "xcdoctor", targets: ["CLI"]),
        .library(name: "XCDoctor", targets: ["XCDoctor"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.3.1"),
    ],
    targets: [
        .target(
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
