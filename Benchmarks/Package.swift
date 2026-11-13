// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "ZlibBenchmarks",
  platforms: [.macOS(.v27)],
  products: [
    .executable(name: "ZlibBenchmarks", targets: ["ZlibBenchmarks"])
  ],
  dependencies: [
    .package(path: "..")
  ],
  targets: [
    .executableTarget(
      name: "ZlibBenchmarks",
      dependencies: [.product(name: "Zlib", package: "swift-zlib")],
      path: "ZlibBenchmarks"
    )
  ]
)
