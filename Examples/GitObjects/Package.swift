// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "GitObjects",
  platforms: [.macOS(.v27)],
  products: [
    .executable(name: "git-object", targets: ["GitObjectExample"])
  ],
  dependencies: [
    .package(path: "../..")
  ],
  targets: [
    .executableTarget(
      name: "GitObjectExample",
      dependencies: [.product(name: "Zlib", package: "swift-zlib")]
    ),
    .testTarget(
      name: "GitObjectExampleTests",
      dependencies: ["GitObjectExample", .product(name: "Zlib", package: "swift-zlib")]
    )
  ]
)
