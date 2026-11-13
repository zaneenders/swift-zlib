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
    let count = try history.copyMatch(distance: distance, length: remaining, into: &output)
    remaining -= count
    return count
  }

  /// Uses output from this call before falling back to the saved history.
  @discardableResult
  mutating func emit(
    into output: inout OutputSpan<UInt8>, history: borrowing HistoryWindow, outputStart: Int
  ) throws(HistoryWindowError) -> Int {
    let count = try history.copyMatch(distance: distance, length: remaining, into: &output, outputStart: outputStart)
    remaining -= count
    return count
  }
}
