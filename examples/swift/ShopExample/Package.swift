// swift-tools-version: 6.0
// gentizer Swift 예시 (specs/swift.md '예시 앱'). 저장소의 swift/ 패키지를 path 로 의존
import PackageDescription

let package = Package(
    name: "ShopExample",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../../swift"),
    ],
    targets: [
        .executableTarget(name: "ShopExample", dependencies: [
            .product(name: "Gentizer", package: "swift"),
            .product(name: "GentizerSwiftUI", package: "swift"),
            .product(name: "GentizerAGUI", package: "swift"),
            .product(name: "GentizerA2UISwiftUI", package: "swift"),
        ]),
    ]
)
