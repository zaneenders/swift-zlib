enum BenchmarkPayload: String, CaseIterable {
  case repeated
  case text
  case allBytes = "all-bytes"
  case random

  func input(count: Int) -> [UInt8] {
    switch self {
    case .repeated:
      return [UInt8](repeating: 90, count: count)
    case .text:
      let line = Array("Swift deflate / inflate.\n".utf8)
      return (0..<count).map { line[$0 % line.count] }
    case .allBytes:
      return (0..<count).map { UInt8(truncatingIfNeeded: $0) }
    case .random:
      // Generate the entire input rather than repeating a small random buffer,
      // which would introduce compressible patterns at the larger sizes.
      var state: UInt32 = 0xC0FFEE
      return (0..<count).map { _ in
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return UInt8(truncatingIfNeeded: state)
      }
    }
  }
}
