enum ZlibEncoder: ~Sendable {
  static func encode(
    input: borrowing Span<UInt8>, strategy: ZLib.Strategy, effort: ZLib.Effort
  ) throws(BitWriterError) -> UniqueArray<UInt8> {
    let compressed = try ZLib.deflate(input: input, format: .rawDeflate, strategy: strategy, effort: effort)
    let (capacity, overflow) = compressed.count.addingReportingOverflow(6)
    guard !overflow else { throw .inputToLong }
    var output = UniqueArray<UInt8>(minimumCapacity: capacity)
    // DEFLATE, 32 KiB window, no preset dictionary, FLEVEL=0, valid FCHECK.
    output.append(0x78)
    output.append(0x01)
    let payload = compressed.span
    for byte in payload { output.append(byte) }
    let checksum = Adler32.checksum(input: input)
    for shift in stride(from: 24, through: 0, by: -8) {
      output.append(UInt8(truncatingIfNeeded: checksum >> shift))
    }
    return output
  }
}
