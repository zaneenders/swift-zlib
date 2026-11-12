/// Errors reported while reading and decompressing a raw DEFLATE stream.
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
  /// Retained for compatibility with earlier versions.
  case invalid
}

/// The original name of the errors returned by `ZLib.inflate`.
public typealias BitReaderError = InflateError
