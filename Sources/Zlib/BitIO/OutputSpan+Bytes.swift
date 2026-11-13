extension OutputSpan where Element == UInt8 {
  /// Copies disjoint bytes into the uninitialized tail without per-byte appends.
  mutating func appendBytes(_ bytes: borrowing Span<UInt8>) {
    precondition(bytes.count <= freeCapacity)
    guard !bytes.isEmpty else { return }
    bytes.withUnsafeBufferPointer { source in
      // The span bounds check above guarantees space for all source bytes.
      // The source borrow and exclusive output access keep the regions disjoint.
      unsafe withUnsafeMutableBufferPointer { destination, initializedCount in
        unsafe destination.baseAddress!.advanced(by: initializedCount)
          .initialize(from: source.baseAddress!, count: source.count)
        initializedCount += source.count
      }
    }
  }

  /// Repeats an initialized suffix, doubling the available pattern each copy.
  mutating func repeatBytes(distance: Int, count: Int) {
    precondition(distance > 0 && distance <= self.count)
    precondition(count >= 0 && count <= freeCapacity)
    guard count > 0 else { return }
    unsafe withUnsafeMutableBufferPointer { buffer, initializedCount in
      let start = initializedCount - distance
      var available = distance
      var remaining = count
      while remaining > 0 {
        let length = min(available, remaining)
        // The source is initialized and ends at or before the destination.
        // Each batch initializes a disjoint region within the checked capacity.
        unsafe buffer.baseAddress!.advanced(by: initializedCount)
          .initialize(from: buffer.baseAddress!.advanced(by: start), count: length)
        initializedCount += length
        available += length
        remaining -= length
      }
    }
  }
}
