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
    var produced = 0
    while remaining > 0 && output.count < output.capacity {
      let byte = UInt8(try reader.readBits(8))
      output.append(byte)
      history.appendLiteral(byte)
      remaining -= 1
      produced += 1
    }
    return produced
  }
}
