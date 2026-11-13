import Foundation
import zlib

// Anchor report writes and Git metadata to this checkout, whether invoked
// from the repository root, the benchmark package, or via the built executable.
let benchmarkDirectory = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent()

struct BenchmarkOptions {
  var iterations = 1_000
  var samples = 3
  var markdown = false
  var updateReadme = false

  func iterations(for inputBytes: Int) -> Int {
    max(1, iterations / max(1, inputBytes / 65_536))
  }

  init(arguments: [String]) {
    let usage = """
      Usage: swift run --package-path Benchmarks -c release ZlibBenchmarks [--iterations COUNT] [--samples COUNT] [--markdown | --update-readme]
      Inputs: 64 KiB, 64 MiB, and 128 MiB. Defaults: 3 samples; CSV on stdout.
      --iterations sets calls per 64 KiB sample (default 1,000), scaled down for larger inputs (minimum 1).
      Add --update-readme to refresh Benchmarks/README.md from the repository root.
      """
    if arguments.contains("--help") || arguments.contains("-h") {
      print(usage)
      exit(0)
    }
    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      if argument == "--markdown" {
        markdown = true
        index += 1
      } else if argument == "--update-readme" {
        updateReadme = true
        index += 1
      } else if argument == "--iterations" || argument == "--samples",
        index + 1 < arguments.count, let count = Int(arguments[index + 1]), count > 0
      {
        if argument == "--iterations" { iterations = count } else { samples = count }
        index += 2
      } else {
        FileHandle.standardError.write(Data("Invalid argument: \(argument)\n\(usage)\n".utf8))
        exit(64)
      }
    }
  }
}

struct BenchmarkResult {
  let payload: String
  let strategy: String
  let inputBytes: Int
  let iterations: Int
  let cLevel: Int32
  let cStrategy: String
  let swiftEncode: Double
  let cEncode: Double
  let swiftDecode: Double
  let cDecode: Double

  var csv: String {
    "\(payload),\(strategy),\(cLevel),\(cStrategy),\(inputBytes),\(iterations),"
      + String(
        format: "%.2f,%.2f,%.3f,%.2f,%.2f,%.3f",
        swiftEncode, cEncode, swiftEncode / cEncode, swiftDecode, cDecode, swiftDecode / cDecode)
  }

  var inputSize: String {
    let unit = inputBytes >= 1_048_576 ? 1_048_576 : 1_024
    return String(format: "%g %@", Double(inputBytes) / Double(unit), unit == 1_024 ? "KiB" : "MiB")
  }

  var markdownMetrics: String {
    "\(comparison(c: cEncode, swift: swiftEncode)) | \(comparison(c: cDecode, swift: swiftDecode))"
  }

  private func comparison(c: Double, swift: Double) -> String {
    let ratio = c / swift
    if abs(ratio - 1) < 0.005 { return "~equal" }
    return String(format: "%.2f× %@", max(ratio, 1 / ratio), ratio > 1 ? "faster" : "slower")
  }
}

private func command(_ executable: String, _ arguments: [String]) -> String {
  let process = Process()
  let output = Pipe()
  process.executableURL = URL(fileURLWithPath: executable)
  process.currentDirectoryURL = benchmarkDirectory.deletingLastPathComponent()
  process.arguments = arguments
  process.standardOutput = output
  process.standardError = FileHandle.nullDevice
  do {
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return "unavailable" }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
  } catch {
    return "unavailable"
  }
}

func markdownReport(_ results: [BenchmarkResult], options: BenchmarkOptions) -> String {
  let revision = command("/usr/bin/git", ["rev-parse", "HEAD"])
  let sourceChanges = command(
    "/usr/bin/git",
    [
      "status", "--porcelain", "--", "Sources"
    ])
  let sourceState = sourceChanges.isEmpty ? "" : " (modified sources)"
  let cpu = command("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"])
  let os = command("/usr/bin/sw_vers", ["-productVersion"])
  let toolchain = command("/usr/bin/env", ["swift", "--version"]).split(separator: "\n").first ?? "unavailable"
  let swiftVersion = toolchain.split(separator: " ").drop(while: { $0 != "version" }).dropFirst().first ?? "unavailable"
  let payloadDescriptions = [
    "repeated": "Repeated `Z`",
    "text": "Repeated text line",
    "all-bytes": "Cycling bytes 0–255",
    "random": "Pseudorandom bytes"
  ]
  let resultsBySize = Dictionary(grouping: results.filter { $0.strategy == "automatic" }, by: \.inputBytes)
  var sections = [
    """
    # Swift vs C zlib

    Swift `.automatic` vs system C zlib \(String(cString: zlibVersion())), level 6 (default strategy).
    Both encoders receive identical input; decoded output is verified byte-for-byte against it.
    Both decoders read the same C-generated DEFLATE bytes. Compressed encoder output may differ.
    """
  ]
  for size in resultsBySize.keys.sorted() {
    let group = resultsBySize[size]!
    let first = group[0]
    let unit = first.iterations == 1 ? "call" : "calls"
    sections.append(
      """

      ## \(first.inputSize)

      \(first.iterations) \(unit) per sample.

      | Payload | Input | C encode vs Swift | C decode vs Swift |
      | --- | --- | ---: | ---: |
      """)
    for result in group {
      sections.append(
        "| \(result.payload) | \(payloadDescriptions[result.payload] ?? result.payload) | \(result.markdownMetrics) |")
    }
  }
  sections.append(
    """

    Release build; median of \(options.samples) samples.
    Setup and allocations are timed.

    \(cpu) · macOS \(os) · Swift \(swiftVersion).
    Library: [`\(revision.prefix(7))`](https://github.com/zaneenders/swift-zlib/commit/\(revision))\(sourceState).
    Measured \(ISO8601DateFormatter().string(from: Date())).

    Regenerate from the repository root:

    ```sh
    swift run --package-path Benchmarks -c release ZlibBenchmarks --update-readme
    ```
    """)
  return sections.joined(separator: "\n") + "\n"
}
