// swift-tools-version: 6.4
import PackageDescription

let swiftSettings: [SwiftSetting] = [
  .strictMemorySafety(),
  .treatAllWarnings(as: .error),
  .enableExperimentalFeature("Lifetimes"),
  .enableUpcomingFeature("MemberImportVisibility"),
  .enableUpcomingFeature("InternalImportsByDefault"),
  .enableUpcomingFeature("ExistentialAny"),
  .enableUpcomingFeature("ApproachableConcurrency"),
  .treatWarning("EmbeddedRestrictions", as: .error),
  .treatWarning("ExplicitSendable", as: .error),
  .treatWarning("PerformanceHints", as: .warning),
  .treatWarning("UntypedThrows", as: .error)  // Must succeed PerformanceHints
]

let package = Package(
  name: "swift-zlib",
  platforms: [.macOS(.v27)],
  products: [
    .library(name: "Zlib", targets: ["Zlib"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-collections.git", from: "1.7.6")
  ],
  targets: [
    .target(
      name: "Zlib",
      dependencies: [
        .product(name: "BasicContainers", package: "swift-collections"),
        .product(name: "HeapModule", package: "swift-collections")
      ],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "ZlibTests",
      dependencies: ["Zlib"]
    )
  ]
)
