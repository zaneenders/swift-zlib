/// Compression and decompression operations for raw DEFLATE, zlib, and gzip streams.
public enum ZLib: ~Sendable {
  /// The container around the compressed DEFLATE data.
  public enum Format: Equatable, Sendable {
    /// Bare DEFLATE blocks without a header or checksum trailer.
    case rawDeflate
    /// Zlib framing with an Adler-32 checksum trailer.
    case zlib
    /// Gzip framing with CRC32 and uncompressed size validation.
    case gzip
  }

  /// Decompresses stored, fixed, and dynamic blocks into storage owned by the caller.
  ///
  /// Throws `InflateError.outputLimitExceeded` before a literal, match, or stored
  /// block would exceed `maximumOutputSize`. Raw DEFLATE ignores trailing bytes.
  /// Zlib validates one stream and rejects trailing bytes. Gzip validates all
  /// concatenated members and rejects trailing garbage; its
  /// output limit applies to their combined decoded size. Use `Inflater` to
  /// inspect input consumption or process chunks.
  public static func inflate(
    input: borrowing Span<UInt8>, format: Format = .rawDeflate, maximumOutputSize: Int = .max
  ) throws(InflateError) -> UniqueArray<UInt8> {
    var inflater = try Inflater(format: format, maximumOutputSize: maximumOutputSize)
    var output = UniqueArray<UInt8>(minimumCapacity: min(input.count, maximumOutputSize, 65_536))
    var consumed = 0
    while true {
      let progress = try output.edit { (span: inout OutputSpan<UInt8>) throws(InflateError) in
        try inflater.process(input: input.extracting(consumed...), output: &span, isFinalInput: true)
      }
      consumed += progress.inputConsumed
      if progress.status == .finished {
        guard format != .zlib || consumed == input.count else {
          throw .trailingData
        }
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
    /// Chooses the smallest stored, fixed, or dynamic encoding for each block.
    /// Uses one LZ77 parse per block of up to 65,535 bytes, including headers
    /// and any final or sync-flush padding in the cost. Equal costs prefer
    /// stored, then fixed, then dynamic. This favors size for the chosen blocks
    /// and matches, and builds dynamic tables even when another encoding wins.
    case automatic
    /// Stored blocks without compression.
    case stored
    /// LZ77 matches encoded with the fixed Huffman alphabet.
    case fixed
    /// LZ77 matches encoded with Huffman alphabets chosen for each block.
    case dynamic
  }

  /// How much work to spend searching for LZ77 matches, independently of block strategy.
  ///
  /// Higher effort searches more candidates but does not guarantee smaller output.
  /// These settings do not correspond to C zlib's numeric compression levels.
  /// Stored blocks ignore effort. All settings use the same working storage.
  public enum Effort: CaseIterable, Equatable, Sendable {
    /// Searches up to 8 candidates and stops after finding a match of at least 32 bytes.
    case fast
    /// Searches up to 128 candidates, stopping at the maximum possible match length.
    /// This is the default and preserves the original encoder's search behavior.
    case balanced
    /// Searches up to 1,024 candidates, stopping at the maximum possible match length.
    case thorough
  }

  /// Compresses using the requested format and block strategy.
  ///
  /// Gzip output contains one member with no timestamp, filename, or comment.
  /// The default `.automatic` strategy compares encoded bit costs per block.
  /// Explicit strategies preserve their existing block layouts.
  /// `effort` controls match searching; `.balanced` preserves the default output.
  /// Use `Deflater` for bounded-memory compression, chunks, and sync flushes.
  public static func deflate(
    input: borrowing Span<UInt8>, format: Format = .rawDeflate, strategy: Strategy = .automatic,
    effort: Effort = .balanced
  ) throws(BitWriterError) -> UniqueArray<UInt8> {
    switch format {
    case .gzip:
      return try GzipEncoder.encode(input: input, strategy: strategy, effort: effort)
    case .zlib:
      return try ZlibEncoder.encode(input: input, strategy: strategy, effort: effort)
    case .rawDeflate:
      break
    }
    switch strategy {
    case .automatic: return try DeflateEncoder.automatic(input: input, effort: effort)
    case .stored: return try DeflateEncoder.stored(input: input)
    case .fixed: return try DeflateEncoder.fixed(input: input, effort: effort)
    case .dynamic: return try DeflateEncoder.dynamic(input: input, effort: effort)
    }
  }
}
