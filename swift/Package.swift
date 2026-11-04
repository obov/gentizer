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
        .library(name: "GentizerA2UISwiftUI", targets: ["GentizerA2UISwiftUI"]),
    ],
    dependencies: [
        // fork 태그 (specs/a2ui.md 'Swift 의존성')
        .package(url: "https://github.com/obov/a2ui.git", exact: "0.1.0"),
    ],
    targets: [
        .target(name: "Gentizer"),
        .target(name: "GentizerSwiftUI", dependencies: ["Gentizer"]),
        .target(name: "GentizerAGUI", dependencies: ["Gentizer"]),
        .target(name: "GentizerA2UI", dependencies: ["Gentizer"]),
        .target(name: "GentizerA2UISwiftUI", dependencies: [
            "GentizerA2UI",
            .product(name: "A2UISwiftCore", package: "a2ui"),
            .product(name: "BasicCatalog", package: "a2ui"),
            .product(name: "A2UISwiftUI", package: "a2ui"),
            .product(name: "BasicCatalogSwiftUI", package: "a2ui"),
        ]),
        .testTarget(name: "GentizerTests", dependencies: ["Gentizer"]),
        .testTarget(name: "GentizerConformanceTests", dependencies: ["Gentizer", "GentizerAGUI", "GentizerA2UI"]),
        .testTarget(name: "GentizerAGUITests", dependencies: ["GentizerAGUI"]),
        .testTarget(name: "GentizerA2UITests", dependencies: ["GentizerA2UI"]),
        .testTarget(name: "GentizerA2UISwiftUITests", dependencies: ["GentizerA2UISwiftUI"]),
        .testTarget(name: "GentizerSwiftUITests", dependencies: ["GentizerSwiftUI"]),
    ]
)
