/// Compression and decompression operations for raw DEFLATE streams.
public enum ZLib: ~Sendable {
  /// Decompresses stored, fixed, and dynamic blocks into storage owned by the caller.
  ///
  /// Throws `InflateError.outputLimitExceeded` before a literal, match, or stored
  /// block would exceed `maximumOutputSize`. Trailing bytes after the final block
  /// are ignored. Use `Inflater` to inspect input consumption or process chunks.
  public static func inflate(
    input: borrowing Span<UInt8>, maximumOutputSize: Int = .max
  ) throws(InflateError) -> UniqueArray<UInt8> {
    var inflater = try Inflater(maximumOutputSize: maximumOutputSize)
    var output = UniqueArray<UInt8>(minimumCapacity: min(input.count, maximumOutputSize, 65_536))
    var consumed = 0
    while true {
      let progress = try output.edit { (span: inout OutputSpan<UInt8>) throws(InflateError) in
        try inflater.process(input: input.extracting(consumed...), output: &span, isFinalInput: true)
      }
      consumed += progress.inputConsumed
      if progress.status == .finished {
        return output
      }
      let remaining = maximumOutputSize - output.count
      // Grow geometrically while respecting the caller's output limit.
      let increment = min(max(1, output.capacity), remaining)
      guard increment > 0 else {
        throw .outputLimitExceeded
      }
      let (capacity, overflow) = output.count.addingReportingOverflow(increment)
      guard !overflow else {
        throw .outputLimitExceeded
      }
      output.reserveCapacity(capacity)
    }
  }

  public enum Strategy: Sendable {
    /// Stored blocks without compression.
    case stored
    /// LZ77 matches encoded with the fixed Huffman alphabet.
    case fixed
    /// LZ77 matches encoded with Huffman alphabets chosen for each block.
    case dynamic
  }

  /// Compresses a raw DEFLATE stream using the requested block strategy.
  public static func deflate(
    input: borrowing Span<UInt8>, strategy: Strategy
  ) throws(BitWriterError) -> UniqueArray<UInt8> {
    switch strategy {
    case .stored: return try DeflateEncoder.stored(input: input)
    case .fixed: return try DeflateEncoder.fixed(input: input)
    case .dynamic: return try DeflateEncoder.dynamic(input: input)
    }
  }
}
