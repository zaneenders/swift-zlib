import Foundation
import Testing
import Zlib

@testable import GitObjectExample

private func compressedObject(_ decoded: [UInt8]) throws -> [UInt8] {
  let compressed = try ZLib.deflate(input: decoded.span, format: .zlib, strategy: .dynamic)
  return (0..<compressed.count).map { compressed[$0] }
}

private func withObjectFile(
  contents: [UInt8],
  _ body: (URL) throws -> Void
) throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let url = directory.appendingPathComponent("object")
  try Data(contents).write(to: url)
  try body(url)
}

@Test(arguments: ["blob", "tree", "commit", "tag"])
func looseObjectReadsTypeAndBinaryPayload(type: String) throws {
  let payload: [UInt8] = [0, 0xFF, 0xFE, 0x80, 10, 13, 65]
  let decoded = Array("\(type) \(payload.count)\0".utf8) + payload
  try withObjectFile(contents: compressedObject(decoded)) { url in
    let object = try readLooseGitObject(at: url)
    #expect(object.type.rawValue == type)
    #expect(object.payload == Data(payload))
  }
}

@Test func looseObjectAcceptsAnEmptyPayload() throws {
  try withObjectFile(contents: compressedObject(Array("blob 0\0".utf8))) { url in
    let object = try readLooseGitObject(at: url)
    #expect(object.type == .blob)
    #expect(object.payload.isEmpty)
  }
}

@Test(
  arguments: [
    "", "blob 1", "blob 01\0x", "blob +1\0x", "blob -1\0", "blob  1\0x",
    "blob 1 \0x", "blob \0", "blob 184467440737095516160\0", "unknown 0\0",
    "Blob 0\0", "blob ١\0"
  ])
func looseObjectRejectsMalformedHeaders(decoded: String) throws {
  try withObjectFile(contents: compressedObject(Array(decoded.utf8))) { url in
    #expect(throws: LooseGitObjectError.invalidHeader) {
      try readLooseGitObject(at: url)
    }
  }
}

@Test(arguments: ["blob 2\0x", "blob 0\0x", "blob 1\0"])
func looseObjectRejectsIncorrectPayloadSizes(decoded: String) throws {
  try withObjectFile(contents: compressedObject(Array(decoded.utf8))) { url in
    #expect(throws: LooseGitObjectError.sizeMismatch) {
      try readLooseGitObject(at: url)
    }
  }
}

@Test func looseObjectRejectsTrailingCompressedBytes() throws {
  let compressed = try compressedObject(Array("blob 1\0x".utf8))
  try withObjectFile(contents: compressed + [0]) { url in
    #expect(throws: InflateError.trailingData) {
      try readLooseGitObject(at: url)
    }
  }
}

@Test func looseObjectEnforcesTheDecodedSizeLimit() throws {
  let decoded = Array("blob 5\0hello".utf8)
  try withObjectFile(contents: compressedObject(decoded)) { url in
    let object = try readLooseGitObject(at: url, maximumDecodedSize: decoded.count)
    #expect(object.payload == Data("hello".utf8))
    #expect(throws: InflateError.outputLimitExceeded) {
      try readLooseGitObject(at: url, maximumDecodedSize: decoded.count - 1)
    }
    #expect(throws: InflateError.invalidOutputLimit) {
      try readLooseGitObject(at: url, maximumDecodedSize: -1)
    }
  }
}

@Test func looseObjectRejectsACorruptedChecksum() throws {
  var compressed = try compressedObject(Array("blob 1\0x".utf8))
  compressed[compressed.count - 1] ^= 1
  try withObjectFile(contents: compressed) { url in
    #expect(throws: InflateError.checksumMismatch) {
      try readLooseGitObject(at: url)
    }
  }
}
