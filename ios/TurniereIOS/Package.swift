// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "TurniereCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "TurniereCore", targets: ["TurniereCore"])],
    targets: [
        .target(name: "TurniereCore", resources: [.process("Resources")]),
        .testTarget(name: "TurniereCoreTests", dependencies: ["TurniereCore"], resources: [.copy("Fixtures")])
    ]
)
