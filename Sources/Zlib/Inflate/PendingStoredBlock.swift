struct PendingStoredBlock: ~Copyable, ~Sendable {
  private(set) var remaining: UInt16

  var isComplete: Bool { remaining == 0 }

  init(length: UInt16) {
    remaining = length
  }

  /// Copies bytes from the reader into output and history until output is full.
  @discardableResult
  mutating func emit(
    from reader: inout BitReader,
    into output: inout OutputSpan<UInt8>,
    history: inout HistoryWindow
  ) throws(BitReaderError) -> Int {
    let initialCount = output.count
    defer {
      let bytes = output.span.extracting(initialCount...)
      history.append(contentsOf: bytes)
    }
    return try emit(from: &reader, into: &output)
  }

  /// Copies into output; the caller records history before returning a chunk.
  @discardableResult
  mutating func emit(
    from reader: inout BitReader, into output: inout OutputSpan<UInt8>
  ) throws(BitReaderError) -> Int {
    let initialCount = output.count
    defer { remaining -= UInt16(output.count - initialCount) }
    try reader.copyBytes(count: min(Int(remaining), output.freeCapacity), into: &output)
    return output.count - initialCount
  }
}
