/// An incremental Adler-32 checksum as defined by RFC 1950.
///
/// Each update includes the supplied bytes in order without retaining their storage.
public struct Adler32: Sendable {
  private var sum: UInt32 = 1
  private var weightedSum: UInt32 = 0

  /// Creates a checksum for an empty byte sequence.
  public init() {}

  /// The checksum of all bytes supplied so far, or 1 for an empty sequence.
  ///
  /// Reading this value does not reset the checksum. Zlib trailers store it in
  /// big-endian byte order.
  public var value: UInt32 { (weightedSum << 16) | sum }

  /// Includes the supplied bytes in the checksum. An empty input has no effect.
  public mutating func update(input: borrowing Span<UInt8>) {
    var offset = 0
    while offset < input.count {
      // Starting with reduced sums, 5,552 bytes of even 0xFF cannot overflow
      // either UInt32 accumulator. Reduce once per batch instead of per byte.
      let end = offset + min(5_552, input.count - offset)
      let batch = input.extracting(offset..<end)
      for byte in batch {
        sum += UInt32(byte)
        weightedSum += sum
      }
      sum %= 65_521
      weightedSum %= 65_521
      offset = end
    }
  }

  /// Computes the checksum of the supplied bytes in one operation.
  public static func checksum(input: borrowing Span<UInt8>) -> UInt32 {
    var checksum = Adler32()
    checksum.update(input: input)
    return checksum.value
  }
}
