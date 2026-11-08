extension UniqueArray where Element == UInt8 {
  /// Expands a backward reference, growing storage as needed and allowing overlapping matches.
  /// Invalid distances and negative lengths leave the bytes unchanged.
  mutating func appendMatch(distance: Int, length: Int) throws(MatchOutputError) {
    guard length >= 0 else {
      throw .invalidLength
    }
    guard distance > 0 && distance <= count else {
      throw .invalidDistance
    }
    for _ in 0..<length {
      let byte = self[count - distance]
      append(byte)
    }
  }
}

enum MatchOutputError: Error {
  case invalidDistance
  case invalidLength
}
