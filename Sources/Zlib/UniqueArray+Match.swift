extension UniqueArray where Element == UInt8 {
  /// Expands a backward reference into the remaining capacity, including overlapping matches.
  /// Invalid distances, negative lengths, and insufficient capacity leave the bytes unchanged.
  mutating func appendMatch(distance: Int, length: Int) throws(MatchOutputError) {
    guard length >= 0 else {
      throw .invalidLength
    }
    guard distance > 0 && distance <= count else {
      throw .invalidDistance
    }
    guard freeCapacity >= length else {
      throw .capacityExceeded
    }
    edit { output in
      for _ in 0..<length {
        let byte = output[output.count - distance]
        output.append(byte)
      }
    }
  }
}

enum MatchOutputError: Error {
  case capacityExceeded
  case invalidDistance
  case invalidLength
}
