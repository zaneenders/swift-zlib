/// Errors reported while reading and decompressing raw DEFLATE, zlib, or gzip streams.
public enum InflateError: Error, Equatable {
  case unexpectedEndOfInput
  case unsupportedBlockType
  case invalidStoredLength
  case invalidHuffmanTable
  case invalidDistance
  case forbiddenSymbol
  case outputLimitExceeded
  case invalidOutputLimit
  case invalidState
  case invalidBitCount
  case invalidGzipHeader
  case invalidZlibHeader
  case unsupportedCompressionMethod
  case unsupportedDictionary
  case headerChecksumMismatch
  case checksumMismatch
  case sizeMismatch
  case trailingData
  /// Retained for compatibility with earlier versions.
  case invalid
}

/// The original name of the errors returned by `ZLib.inflate`.
public typealias BitReaderError = InflateError
