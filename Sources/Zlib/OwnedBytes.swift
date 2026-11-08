/// Owns a byte allocation with initialized bytes in `0..<count`.
public struct OwnedBytes: ~Copyable, ~Sendable {
  private var storage: UniqueArray<UInt8>

  var capacity: Int { storage.capacity }
  var count: Int { storage.count }

  public init(capacity: Int) {
    precondition(capacity >= 0)
    storage = UniqueArray(capacity: capacity)
  }

  /// Ensures room for at least `minimumCapacity` bytes, preserving the initialized prefix.
  public mutating func reserveCapacity(_ minimumCapacity: Int) {
    precondition(minimumCapacity >= 0)
    storage.reserveCapacity(minimumCapacity)
  }

  public mutating func append(_ byte: UInt8) throws(OwnedBytesError) {
    guard capacity - count > 0 else {
      throw OwnedBytesError.capacityExceeded
    }
    storage.append(byte)
  }

  /// Edits the initialized prefix and remaining capacity through one exclusive view.
  /// The final contents are retained whether the callback returns or throws.
  public mutating func withOutputSpan<E: Error>(
    _ body: (inout OutputSpan<UInt8>) throws(E) -> Void
  ) throws(E) {
    try storage.edit(body)
  }

  /// Expands a backward reference into the remaining capacity, including overlapping matches.
  /// Invalid distances, negative lengths, and insufficient capacity must leave the bytes unchanged.
  public mutating func appendMatch(distance: Int, length: Int) throws(OwnedBytesError) {
    guard length >= 0 else {
      throw OwnedBytesError.invalidLength
    }
    guard distance > 0 && count > 0 && (1...count).contains(distance) else {
      throw OwnedBytesError.invalidDistance
    }
    guard capacity - count >= length else {
      throw OwnedBytesError.capacityExceeded
    }
    withOutputSpan { output in
      for _ in 0..<length {
        let byte = output[output.count - distance]
        output.append(byte)
      }
    }
  }

  @_lifetime(borrow self)
  public borrowing func readSpan() -> Span<UInt8> {
    return storage.span
  }
}

public enum OwnedBytesError: Error {
  case capacityExceeded
  case invalidDistance
  case invalidLength
}
