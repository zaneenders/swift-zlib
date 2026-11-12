/// An incremental IEEE CRC-32 checksum, as used by the gzip format.
///
/// Each update includes the supplied bytes in order without retaining their storage.
public struct CRC32: Sendable {
  private var remainder: UInt32 = .max

  private static let table: [UInt32] = (0..<256).map { index in
    var entry = UInt32(index)
    for _ in 0..<8 {
      entry = (entry >> 1) ^ (entry & 1 == 0 ? 0 : 0xEDB8_8320)
    }
    return entry
  }

  /// Creates a checksum for an empty byte sequence.
  public init() {}

  /// The checksum of all bytes supplied so far, or zero for an empty sequence.
  ///
  /// Reading this value does not reset the checksum. Gzip trailers store it in
  /// little-endian byte order.
  public var value: UInt32 { ~remainder }

  /// Includes the supplied bytes in the checksum. An empty input has no effect.
  public mutating func update(input: borrowing Span<UInt8>) {
    for byte in input {
      update(byte: byte)
    }
  }

  /// Includes a single byte, for incremental gzip header validation.
  mutating func update(byte: UInt8) {
    let index = Int((remainder ^ UInt32(byte)) & 0xFF)
    remainder = (remainder >> 8) ^ Self.table[index]
  }

  /// Computes the checksum of the supplied bytes in one operation.
  public static func checksum(input: borrowing Span<UInt8>) -> UInt32 {
    var checksum = CRC32()
    checksum.update(input: input)
    return checksum.value
  }
}
