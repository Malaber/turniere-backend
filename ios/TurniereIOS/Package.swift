// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "TurniereCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "TurniereCore", targets: ["TurniereCore"])],
    targets: [
        .target(name: "TurniereCore"),
        .testTarget(name: "TurniereCoreTests", dependencies: ["TurniereCore"], resources: [.copy("Fixtures")])
    ]
)
