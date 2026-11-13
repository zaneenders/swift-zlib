import CryptoKit
import Foundation

struct BenchmarkPayload {
  let name: String
  let byteCount: Int
  let sha256: String

  // Original, uncompressed files from the author's Silesia corpus. These also
  // match the MD5 digests published at https://sun.aei.polsl.pl/~sdeor/index.php?page=silesia.
  static let silesia: [Self] = [
    .init(
      name: "dickens", byteCount: 10_192_446,
      sha256: "b24c37886142e11d0ee687db6ab06f936207aa7f2ea1fd1d9a36763c7a507e6a"),
    .init(
      name: "mozilla", byteCount: 51_220_480,
      sha256: "657fc3764b0c75ac9de9623125705831ebbfbe08fed248df73bc2dc66e2a963b"),
    .init(
      name: "mr", byteCount: 9_970_564,
      sha256: "68637ed52e3e4860174ed2dc0840ac77d5f1a60abbcb13770d5754e3774d53e6"),
    .init(
      name: "nci", byteCount: 33_553_445,
      sha256: "fc63a31770947b8c2062d3b19ca94c00485a232bb91b502021948fee983e1635"),
    .init(
      name: "ooffice", byteCount: 6_152_192,
      sha256: "e7ee013880d34dd5208283d0d3d91b07f442e067454276095ded14f322a656eb"),
    .init(
      name: "osdb", byteCount: 10_085_684,
      sha256: "60f027179302ca3ad87c58ac90b6be72ec23588aaa7a3b7fe8ecc0f11def3fa3"),
    .init(
      name: "reymont", byteCount: 6_627_202,
      sha256: "0eac0114a3dfe6e2ee1f345a0f79d653cb26c3bc9f0ed79238af4933422b7578"),
    .init(
      name: "samba", byteCount: 21_606_400,
      sha256: "93ba07bc44d8267789c1d911992f40b089ffa2140b4a160fac11ccae9a40e7b2"),
    .init(
      name: "sao", byteCount: 7_251_944,
      sha256: "c2d0ea2cc59d4c21b7fe43a71499342a00cbe530a1d5548770e91ecd6214adcc"),
    .init(
      name: "webster", byteCount: 41_458_703,
      sha256: "6a68f69b26daf09f9dd84f7470368553194a0b294fcfa80f1604efb11143a383"),
    .init(
      name: "xml", byteCount: 5_345_280,
      sha256: "0e82e54e695c1938e4193448022543845b33020c8be6bf3bf3ead2224903e08c"),
    .init(
      name: "x-ray", byteCount: 8_474_240,
      sha256: "7de9fce1405dc44ae5e6813ed21cd5751e761bd4265655a005d39b9685d1c9ad")
  ]

  func input(from directory: URL) throws -> [UInt8] {
    let file = directory.appendingPathComponent(name)
    let data = try Data(contentsOf: file, options: .mappedIfSafe)
    guard data.count == byteCount, Self.digest(data) == sha256 else {
      throw CorpusError(
        "Silesia size or SHA-256 mismatch: \(file.path). Expected the original, uncompressed corpus file.")
    }
    return Array(data)
  }

  static func prepareCorpus(at directory: URL, downloadIfMissing: Bool) throws {
    let manager = FileManager.default
    let missing = silesia.filter { !manager.fileExists(atPath: directory.appendingPathComponent($0.name).path) }
    guard !missing.isEmpty else { return }
    guard downloadIfMissing else {
      throw CorpusError("Missing Silesia files in \(directory.path): \(missing.map(\.name).joined(separator: ", ")).")
    }
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    let archive = directory.appendingPathComponent("silesia.zip")
    let archiveDigest = "0626e25f45c0ffb5dc801f13b7c82a3b75743ba07e3a71835a41e3d9f63c77af"
    if !manager.fileExists(atPath: archive.path) {
      FileHandle.standardError.write(Data("Downloading Silesia corpus (about 65 MiB)…\n".utf8))
      let temporary = directory.appendingPathComponent("silesia-\(UUID().uuidString).zip")
      defer { try? manager.removeItem(at: temporary) }
      try run(
        "/usr/bin/curl",
        [
          "--fail", "--location", "--retry", "3", "--connect-timeout", "15", "--max-time", "300",
          "--silent", "--show-error", "--output", temporary.path,
          "https://sun.aei.polsl.pl/~sdeor/corpus/silesia.zip"
        ])
      guard digest(try Data(contentsOf: temporary, options: .mappedIfSafe)) == archiveDigest else {
        throw CorpusError("Downloaded Silesia archive failed SHA-256 verification.")
      }
      try manager.moveItem(at: temporary, to: archive)
    } else if digest(try Data(contentsOf: archive, options: .mappedIfSafe)) != archiveDigest {
      throw CorpusError("Silesia archive checksum mismatch. Remove \(archive.path) and rerun.")
    }
    // Extract only missing, known filenames; preserve any existing local files.
    try run("/usr/bin/unzip", ["-q", archive.path] + missing.map(\.name) + ["-d", directory.path])
  }

  private static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = FileHandle.standardError
    process.standardError = FileHandle.standardError
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw CorpusError("\(executable) failed with exit status \(process.terminationStatus).")
    }
  }
}

struct CorpusError: Error, CustomStringConvertible {
  let description: String

  init(_ description: String) {
    self.description = description
  }
}
