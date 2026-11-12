enum InteropPayload: CaseIterable, Sendable {
  case empty
  case singleByte
  case allBytes
  case text
  case repeatedByte
  case multipleBlocks
  case pseudoRandom
  case skewedFrequencies

  var bytes: [UInt8] {
    switch self {
    case .empty:
      return []
    case .singleByte:
      return [0x41]
    case .allBytes:
      return Array(UInt8.min...UInt8.max)
    case .text:
      return Array(String(repeating: "Swift deflate / inflate.\n", count: 1_024).utf8)
    case .repeatedByte:
      return [UInt8](repeating: 0x5A, count: 65_537)
    case .multipleBlocks:
      return (0..<196_605).map { UInt8(truncatingIfNeeded: $0 * 37 + 11) }
    case .pseudoRandom:
      var state: UInt32 = 0xC0FFEE
      return (0..<65_537).map { _ in
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return UInt8(truncatingIfNeeded: state)
      }
    case .skewedFrequencies:
      var frequencies = [1, 1]
      for _ in 0..<18 {
        frequencies.append(frequencies[frequencies.count - 2] + frequencies[frequencies.count - 1])
      }
      return frequencies.enumerated().flatMap { symbol, count in
        [UInt8](repeating: UInt8(symbol), count: count)
      }
    }
  }
}
