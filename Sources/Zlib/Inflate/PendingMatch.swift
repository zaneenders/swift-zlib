/// A backward reference that can be emitted over several output chunks.
struct PendingMatch: ~Copyable, ~Sendable {
  let distance: Int
  private(set) var remaining: Int

  var isComplete: Bool { remaining == 0 }

  init(distance: Int, length: Int) {
    self.distance = distance
    self.remaining = length
  }

  /// Emits as many bytes as will fit, returning the number added during this call.
  /// Invalid requests leave the match, history, and output unchanged.
  @discardableResult
  mutating func emit(
    into output: inout OutputSpan<UInt8>,
    history: inout HistoryWindow
  ) throws(HistoryWindowError) -> Int {
    guard remaining >= 0 else {
      throw .invalidLength
    }
    guard distance > 0 && distance <= history.count else {
      throw .invalidDistance
    }
    var count = 0
    while remaining > 0 && output.count < output.capacity {
      let byte = try history.byte(distance: distance)
      output.append(byte)
      history.appendLiteral(byte)
      count += 1
      remaining -= 1
    }
    return count
  }
}
