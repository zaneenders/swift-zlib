import BasicContainers

/// Retains the newest bytes needed by DEFLATE backward references.
struct HistoryWindow: ~Copyable, ~Sendable {
  private var storage: RigidArray<UInt8>
  private(set) var writeIndex = 0

  var capacity: Int { storage.capacity }
  var count: Int { storage.count }

  init(capacity: Int = 32 * 1024) {
    precondition(capacity > 0 && capacity <= 32 * 1024)
    storage = RigidArray(capacity: capacity)
  }

  /// Records a byte, replacing the oldest byte when the window is full.
  mutating func appendLiteral(_ byte: UInt8) {
    if count < capacity {
      storage.append(byte)
    } else {
      // Wrap around
      storage[writeIndex] = byte
    }
    writeIndex = (writeIndex + 1) % capacity
  }

  /// Reads backward from the next write position; distance 1 is the newest byte.
  borrowing func byte(distance: Int) throws(HistoryWindowError) -> UInt8 {
    guard distance > 0 && distance <= count else {
      throw .invalidDistance
    }
    var offset = writeIndex - distance
    if offset < 0 {
      offset = capacity + offset
    }
    return storage[offset]
  }
}

enum HistoryWindowError: Error {
  case invalidDistance
  case invalidLength
}
