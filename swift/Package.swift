// swift-tools-version: 6.0
// 개발 위치: gentizer 저장소 swift/. 배포: gentizer-swift (gnam export, specs/swift.md)
import PackageDescription

let package = Package(
    name: "Gentizer",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Gentizer", targets: ["Gentizer"]),
        .library(name: "GentizerSwiftUI", targets: ["GentizerSwiftUI"]),
        .library(name: "GentizerAGUI", targets: ["GentizerAGUI"]),
        .library(name: "GentizerA2UI", targets: ["GentizerA2UI"]),
    ],
    targets: [
        .target(name: "Gentizer"),
        .target(name: "GentizerSwiftUI", dependencies: ["Gentizer"]),
        .target(name: "GentizerAGUI", dependencies: ["Gentizer"]),
        .target(name: "GentizerA2UI", dependencies: ["Gentizer"]),
        .testTarget(name: "GentizerTests", dependencies: ["Gentizer"]),
        .testTarget(name: "GentizerConformanceTests", dependencies: ["Gentizer", "GentizerAGUI", "GentizerA2UI"]),
        .testTarget(name: "GentizerAGUITests", dependencies: ["GentizerAGUI"]),
        .testTarget(name: "GentizerA2UITests", dependencies: ["GentizerA2UI"]),
        .testTarget(name: "GentizerSwiftUITests", dependencies: ["GentizerSwiftUI"]),
    ]
)
