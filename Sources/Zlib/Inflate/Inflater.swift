/// Incrementally decompresses raw DEFLATE, zlib, or gzip using a 32 KiB history window.
///
/// Advance input by `Progress.inputConsumed`, and retain the appended output.
/// No input or output storage is borrowed between calls. Create a new instance
/// after completion or an error.
public struct Inflater: ~Copyable, ~Sendable {
  public enum Status: Equatable, Sendable {
    /// All supplied input was accepted; provide more bytes to continue.
    case needsInput
    /// Provide more writable output capacity and any unconsumed input.
    case needsOutput
    /// Decoding is complete, including checksum validation for zlib and gzip.
    case finished
  }

  /// The bytes accepted and appended during one call to `process`.
  public struct Progress: Sendable {
    public let inputConsumed: Int
    public let outputProduced: Int
    public let status: Status
  }

  public let format: ZLib.Format
  /// The maximum decoded size across the entire stream, including all gzip members.
  public let maximumOutputSize: Int
  /// Decoded bytes emitted so far, excluding preexisting bytes in output spans.
  public var totalOutputCount: Int {
    format == .gzip ? gzip.totalOutputCount : raw.totalOutputCount
  }
  public var isFinished: Bool {
    switch format {
    case .rawDeflate: return raw.isFinished
    case .zlib: return zlib.isFinished
    case .gzip: return gzip.isFinished
    }
  }

  private var raw: RawInflater
  private var zlib = ZlibDecoder()
  private var gzip = GzipDecoder()

  /// Creates a decoder, rejecting negative output limits.
  public init(
    format: ZLib.Format = .rawDeflate, maximumOutputSize: Int = .max
  ) throws(InflateError) {
    self.format = format
    self.maximumOutputSize = maximumOutputSize
    self.raw = try RawInflater(maximumOutputSize: maximumOutputSize)
  }

  /// Appends decoded bytes to the available output capacity.
  ///
  /// Set `isFinalInput` when no further input will arrive. An incomplete stream
  /// then throws `unexpectedEndOfInput`. A full output may still return
  /// `needsOutput`; pass any unconsumed input again with fresh output storage.
  /// Raw DEFLATE stops at its final block, leaving trailing input unconsumed.
  /// Zlib stops after one validated stream, also leaving trailing input unconsumed.
  /// Gzip decodes concatenated members, rejects trailing garbage, and waits for
  /// final input before reporting completion. Output is provisional until its
  /// member's checksum and size have been verified. On an error, output may
  /// contain a prefix and this instance cannot resume.
  public mutating func process(
    input: borrowing Span<UInt8>, output: inout OutputSpan<UInt8>, isFinalInput: Bool = false
  ) throws(InflateError) -> Progress {
    switch format {
    case .rawDeflate:
      return try raw.process(input: input, output: &output, isFinalInput: isFinalInput)
    case .zlib:
      return try zlib.process(input: input, output: &output, inflater: &raw, isFinalInput: isFinalInput)
    case .gzip:
      return try gzip.process(
        input: input, output: &output, inflater: &raw,
        maximumOutputSize: maximumOutputSize, isFinalInput: isFinalInput)
    }
  }
}
