/// Errors from an incremental compressor. Discard the compressor after an error.
public enum DeflateError: Error {
  /// Input was supplied after completion, or a flush request changed during a retry.
  case invalidState
  /// A cumulative byte count would exceed `Int.max`.
  case sizeOverflow
  /// The underlying block encoder could not represent a symbol.
  case encodingError(BitWriterError)
}
