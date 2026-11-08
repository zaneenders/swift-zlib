/// The bytes produced by literals and backward references during decompression.
struct LZ77Output {
  private(set) var bytes: [UInt8] = []
  let maximumOutputSize: Int

  init(maximumOutputSize: Int = .max) {
    precondition(maximumOutputSize >= 0)
    self.maximumOutputSize = maximumOutputSize
  }

  mutating func appendLiteral(_ byte: UInt8) throws(LZ77Error) {
    guard maximumOutputSize - bytes.count > 0 else {
      throw LZ77Error.outputLimitExceeded
    }
    bytes.append(byte)
  }

  /// Appends `length` bytes, each read `distance` bytes behind the growing end.
  ///
  /// Requires a positive distance within the existing history and a nonnegative length.
  mutating func appendMatch(distance: Int, length: Int) throws(LZ77Error) {
    guard length >= 0 else {
      throw LZ77Error.invalidLength
    }
    guard distance > 0 && bytes.count > 0 && (1...bytes.count).contains(distance) else {
      throw LZ77Error.invalidDistance
    }
    guard maximumOutputSize - bytes.count >= length else {
      throw LZ77Error.outputLimitExceeded
    }
    for _ in 0..<length {
      let byte = bytes[bytes.count - distance]
      bytes.append(byte)
    }
  }
}

enum LZ77Error: Error {
  case invalidDistance
  case invalidLength
  case outputLimitExceeded
}
