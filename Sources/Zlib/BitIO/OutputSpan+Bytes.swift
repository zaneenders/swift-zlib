import ContainersPreview

extension OutputSpan where Element == UInt8 {
  /// Copies disjoint bytes into the tail using a safe bulk update.
  mutating func appendBytes(_ bytes: borrowing Span<UInt8>) {
    precondition(bytes.count <= freeCapacity)
    guard !bytes.isEmpty else { return }
    let start = count
    // OutputSpan has no safe bulk append yet. Initialize the tail before using
    // MutableContainer's bulk update, which only accepts initialized elements.
    append(repeating: 0, count: bytes.count)
    updateSubrange(start..<count, copying: bytes)
  }

  /// Repeats a suffix, including bytes produced by this same match.
  mutating func repeatBytes(distance: Int, count: Int) {
    precondition(distance > 0 && distance <= self.count)
    precondition(count >= 0 && count <= freeCapacity)
    for _ in 0..<count {
      let byte = self[self.count - distance]
      append(byte)
    }
  }
}
