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
  var corpusDirectory = benchmarkDirectory.appendingPathComponent(".build/silesia")
  var downloadCorpus = true
  var strategies: [BenchmarkStrategy] = [.automatic]

  func iterations(for inputBytes: Int) -> Int {
    max(1, iterations / max(1, inputBytes / 65_536))
  }

  init(arguments: [String]) {
    let usage = """
      Usage: swift run --package-path Benchmarks -c release ZlibBenchmarks [options]
      Inputs: all 12 Silesia files at their original sizes. Defaults: automatic strategy, 3 samples, CSV on stdout.
      The corpus is downloaded once to Benchmarks/.build/silesia and verified with SHA-256 before timing.
      --iterations sets calls per 64 KiB sample (default 1,000), scaled down for larger inputs (minimum 1).
      --samples COUNT sets the number of samples (default 3).
      --strategy automatic|stored|fixed|dynamic|all selects strategies (default automatic).
      --corpus PATH uses existing, uncompressed Silesia files instead of downloading to the cache.
      --markdown prints a Markdown report; --update-readme writes it to Benchmarks/README.md.
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
      } else if argument == "--corpus", index + 1 < arguments.count {
        corpusDirectory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        downloadCorpus = false
        index += 2
      } else if argument == "--strategy", index + 1 < arguments.count,
        arguments[index + 1] == "all" || BenchmarkStrategy(rawValue: arguments[index + 1]) != nil
      {
        strategies =
          arguments[index + 1] == "all"
          ? BenchmarkStrategy.allCases : [BenchmarkStrategy(rawValue: arguments[index + 1])!]
        index += 2
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
    if markdown && updateReadme {
      FileHandle.standardError.write(Data("Choose either --markdown or --update-readme.\n".utf8))
      exit(64)
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
  let swiftCompressedBytes: Int
  let cCompressedBytes: Int
  let swiftEncode: Double
  let cEncode: Double
  let swiftDecode: Double
  let cDecode: Double

  static let csvHeader =
    "payload,strategy,c_level,c_strategy,input_bytes,iterations,swift_compressed_bytes,c_compressed_bytes,swift_encode_mib_s,c_encode_mib_s,encode_swift_over_c,swift_decode_mib_s,c_decode_mib_s,decode_swift_over_c"

  var csv: String {
    "\(payload),\(strategy),\(cLevel),\(cStrategy),\(inputBytes),\(iterations),"
      + "\(swiftCompressedBytes),\(cCompressedBytes),"
      + String(
        format: "%.2f,%.2f,%.3f,%.2f,%.2f,%.3f",
        swiftEncode, cEncode, swiftEncode / cEncode, swiftDecode, cDecode, swiftDecode / cDecode)
  }

  var markdownSizes: String {
    "\(Self.compressedSize(swiftCompressedBytes, inputBytes: inputBytes)) | \(Self.compressedSize(cCompressedBytes, inputBytes: inputBytes))"
  }

  var markdownMetrics: String {
    String(
      format: "%.2f | %.2f | %@ | %.2f | %.2f | %@",
      swiftEncode, cEncode, comparison(c: cEncode, swift: swiftEncode),
      swiftDecode, cDecode, comparison(c: cDecode, swift: swiftDecode))
  }

  static func compressedSize(_ compressedBytes: Int, inputBytes: Int) -> String {
    let percentage = String(format: "%.1f%%", 100 * Double(compressedBytes) / Double(inputBytes))
    return "\(compressedBytes) (\(percentage))"
  }

  private func comparison(c: Double, swift: Double) -> String {
    let ratio = c / swift
    if abs(ratio - 1) < 0.005 { return "~equal" }
    return String(format: "%@ %.2f× faster", ratio > 1 ? "C" : "Swift", max(ratio, 1 / ratio))
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
  var regenerate = "swift run --package-path Benchmarks -c release ZlibBenchmarks"
  if options.strategies != [.automatic] {
    regenerate += " --strategy \(options.strategies.count == 1 ? options.strategies[0].rawValue : "all")"
  }
  if options.iterations != 1_000 { regenerate += " --iterations \(options.iterations)" }
  if options.samples != 3 { regenerate += " --samples \(options.samples)" }
  regenerate += " --update-readme"
  var sections = [
    """
    # Swift vs C zlib — Silesia

    All 12 original files from the [Silesia compression corpus](https://sun.aei.polsl.pl/~sdeor/index.php?page=silesia),
    totaling 211,938,580 bytes. Each file is a separate raw DEFLATE stream, without repetition or padding.
    System C zlib \(String(cString: zlibVersion())).
    Both encoders receive identical input; decoded output is verified byte-for-byte against it.
    Both decoders read the same C-generated DEFLATE bytes. Compressed encoder output may differ.
    """
  ]
  for strategy in options.strategies {
    let group = results.filter { $0.strategy == strategy.rawValue }
    sections.append(
      """

      ## Swift `.\(strategy.rawValue)` vs C level \(strategy.cLevel), \(strategy.cStrategyName)

      Compressed sizes are bytes, with percentage of input in parentheses (smaller is better).

      | File | Input bytes | Calls/sample | Swift compressed | C compressed |
      | --- | ---: | ---: | ---: | ---: |
      """)
    for result in group {
      sections.append(
        "| \(result.payload) | \(result.inputBytes) | \(result.iterations) | \(result.markdownSizes) |")
    }
    let totals = group.reduce(into: (input: 0, swift: 0, c: 0)) { totals, result in
      totals.input += result.inputBytes
      totals.swift += result.swiftCompressedBytes
      totals.c += result.cCompressedBytes
    }
    let swiftSize = BenchmarkResult.compressedSize(totals.swift, inputBytes: totals.input)
    let cSize = BenchmarkResult.compressedSize(totals.c, inputBytes: totals.input)
    sections.append("| **Total** | **\(totals.input)** | — | **\(swiftSize)** | **\(cSize)** |")
    sections.append(
      """

      Throughput is MiB/s of uncompressed input (higher is better).
      Comparison columns name the faster implementation and its speedup.

      | File | Swift encode | C encode | Faster encoder | Swift decode | C decode | Faster decoder |
      | --- | ---: | ---: | ---: | ---: | ---: | ---: |
      """)
    for result in group {
      sections.append("| \(result.payload) | \(result.markdownMetrics) |")
    }
  }
  sections.append(
    """

    Release build; median of \(options.samples) samples.
    Calls per sample scale down from \(options.iterations) per 64 KiB, with a minimum of one call per file.
    Codec setup, allocations, and teardown are timed. Downloading, file I/O, SHA-256 verification,
    and correctness checks are outside the timed regions. Swift and C alternate which runs first.

    \(cpu) · macOS \(os) · Swift \(swiftVersion).
    Library: [`\(revision.prefix(7))`](https://github.com/zaneenders/swift-zlib/commit/\(revision))\(sourceState).
    Measured \(ISO8601DateFormatter().string(from: Date())).

    Regenerate from the repository root (first run downloads about 65 MiB and caches the corpus in `Benchmarks/.build/silesia`):

    ```sh
    \(regenerate)
    ```

    Use `--corpus /path/to/silesia` for an existing uncompressed corpus; the same size and SHA-256 checks apply.
    The default strategy is `automatic`; `--strategy all` also measures `stored`, `fixed`, and `dynamic`.
    Omit `--update-readme` for CSV including exact compressed sizes, throughput, and comparison ratios.
    For a quick correctness and timing pass, use `--iterations 1 --samples 1`.
    """)
  return sections.joined(separator: "\n") + "\n"
}
