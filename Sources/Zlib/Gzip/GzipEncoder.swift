enum GzipEncoder: ~Sendable {
  static func encode(
    input: borrowing Span<UInt8>, strategy: ZLib.Strategy
  ) throws(BitWriterError) -> UniqueArray<UInt8> {
    let compressed = try ZLib.deflate(input: input, strategy: strategy)
    let (capacity, overflow) = compressed.count.addingReportingOverflow(18)
    guard !overflow else { throw .inputToLong }
    var output = UniqueArray<UInt8>(minimumCapacity: capacity)
    // DEFLATE, no optional metadata, MTIME=0, XFL=0, OS=255 (unknown).
    let header: InlineArray<10, UInt8> = [0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 255]
    for byte in header { output.append(byte) }
    let payload = compressed.span
    for byte in payload { output.append(byte) }
    appendLittleEndian(CRC32.checksum(input: input), to: &output)
    appendLittleEndian(UInt32(truncatingIfNeeded: input.count), to: &output)
    return output
  }

  private static func appendLittleEndian(_ value: UInt32, to output: inout UniqueArray<UInt8>) {
    for shift in stride(from: 0, to: 32, by: 8) {
      output.append(UInt8(truncatingIfNeeded: value >> shift))
    }
  }
}
