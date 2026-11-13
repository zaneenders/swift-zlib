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

  init(arguments: [String]) {
    let usage = """
      Usage: swift run --package-path Benchmarks -c release ZlibBenchmarks [--iterations COUNT] [--samples COUNT] [--markdown | --update-readme]
      Defaults: 1,000 iterations per sample, 3 samples; CSV on stdout.
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
  let cLevel: Int32
  let cStrategy: String
  let swiftEncode: Double
  let cEncode: Double
  let swiftDecode: Double
  let cDecode: Double

  var csv: String {
    "\(payload),\(strategy),\(cLevel),\(cStrategy),\(inputBytes),"
      + String(
        format: "%.2f,%.2f,%.3f,%.2f,%.2f,%.3f",
        swiftEncode, cEncode, swiftEncode / cEncode, swiftDecode, cDecode, swiftDecode / cDecode)
  }

  var markdownMetrics: String {
    String(
      format: "%.2f× | %.2f×", cEncode / swiftEncode, cDecode / swiftDecode)
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
  var sections = [
    """
    # Swift vs C zlib

    Swift `.automatic` vs system C zlib \(String(cString: zlibVersion())), level 6 (default strategy).
    Speedup = C throughput / Swift throughput; above 1× favors C.

    | Payload | C encode speedup | C decode speedup |
    | --- | ---: | ---: |
    """
  ]
  for result in results where result.strategy == "automatic" {
    sections.append("| \(result.payload) | \(result.markdownMetrics) |")
  }
  sections.append(
    """

    Release build; median of \(options.samples) samples × \(options.iterations) calls.
    Setup and allocations are timed; both decoders read identical raw DEFLATE bytes.

    \(cpu) · macOS \(os) · Swift \(swiftVersion).
    Library: [`\(revision.prefix(7))`](https://github.com/zaneenders/swift-zlib/commit/\(revision))\(sourceState).
    Measured \(ISO8601DateFormatter().string(from: Date())).

    Rerun from the repository root:

    ```sh
    swift run --package-path Benchmarks -c release ZlibBenchmarks --update-readme
    ```
    """)
  return sections.joined(separator: "\n") + "\n"
}
