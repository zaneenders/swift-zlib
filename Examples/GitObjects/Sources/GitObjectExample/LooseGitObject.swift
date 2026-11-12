import Foundation
import Zlib

enum GitObjectType: String, Sendable {
  case blob, tree, commit, tag
}

struct LooseGitObject: Sendable {
  let type: GitObjectType
  let payload: Data
}

enum LooseGitObjectError: Error, Equatable, LocalizedError {
  case invalidHeader
  case sizeMismatch

  var errorDescription: String? {
    switch self {
    case .invalidHeader: "Invalid Git loose-object header."
    case .sizeMismatch: "Git object size does not match its payload."
    }
  }
}

/// Reads a loose object, validating its zlib framing and Git header.
///
/// The decoded size limit includes both the header and payload. This helper
/// reads the entire compressed file and returns an owned copy of its payload.
/// It does not verify the object ID or parse the contents of tree/commit/tag objects.
func readLooseGitObject(
  at url: URL,
  maximumDecodedSize: Int = 64 * 1024 * 1024
) throws -> LooseGitObject {
  let compressed = Array(try Data(contentsOf: url))
  let decoded = try ZLib.inflate(
    input: compressed.span,
    format: .zlib,
    maximumOutputSize: maximumDecodedSize
  )

  // Longest type, space, largest representable size, and terminating NUL.
  let maximumHeaderSize = 6 + 1 + String(Int.max).utf8.count + 1
  guard
    let terminator = (0..<min(decoded.count, maximumHeaderSize))
      .first(where: { decoded[$0] == 0 })
  else {
    throw LooseGitObjectError.invalidHeader
  }

  let header = String(
    decoding: (0..<terminator).map { decoded[$0] },
    as: UTF8.self
  )
  let fields = header.split(separator: " ", omittingEmptySubsequences: false)
  guard fields.count == 2,
    let type = GitObjectType(rawValue: String(fields[0])),
    !fields[1].isEmpty,
    fields[1].utf8.allSatisfy({ (48...57).contains($0) }),
    fields[1].count == 1 || fields[1].first != "0",
    let declaredSize = Int(fields[1])
  else {
    throw LooseGitObjectError.invalidHeader
  }

  let payloadStart = terminator + 1
  guard declaredSize == decoded.count - payloadStart else {
    throw LooseGitObjectError.sizeMismatch
  }

  return LooseGitObject(
    type: type,
    payload: Data((payloadStart..<decoded.count).map { decoded[$0] })
  )
}
