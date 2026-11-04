// swift-tools-version: 6.0
// 개발 위치: gentizer 저장소 swift/. 배포: gentizer-swift (gnam export, specs/swift.md)
import PackageDescription

let package = Package(
    name: "Gentizer",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "Gentizer", targets: ["Gentizer"]),
        .library(name: "GentizerSwiftUI", targets: ["GentizerSwiftUI"]),
    ],
    targets: [
        .target(name: "Gentizer"),
        .target(name: "GentizerSwiftUI", dependencies: ["Gentizer"]),
        .testTarget(name: "GentizerTests", dependencies: ["Gentizer"]),
        .testTarget(name: "GentizerConformanceTests", dependencies: ["Gentizer"]),
        .testTarget(name: "GentizerSwiftUITests", dependencies: ["GentizerSwiftUI"]),
    ]
)
