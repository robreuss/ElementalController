// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ElementalController",
    products: [
        .library(
            name: "ElementalController",
            targets: ["ElementalController"]), 
        ],
    dependencies: [
        .package(url: "https://github.com/IBM-Swift/BlueSocket.git",.exact("2.0.1")),
        .package(url: "https://github.com/Bouke/NetService.git",.exact("0.7.0"))
        //.package(url: "https://github.com/robreuss/NetService.git",.upToNextMajor(from: "0.8.2")),
        
    ],
    targets: [
        .target(
            name: "ElementalController",
            dependencies: ["NetService", "Socket"],
            path: ".",
            sources: ["Sources/ElementalController"]),
        ]
)
