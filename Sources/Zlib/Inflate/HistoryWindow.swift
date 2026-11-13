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
    writeIndex += 1
    if writeIndex == capacity { writeIndex = 0 }
  }

  /// Records contiguous runs, splitting only where the circular buffer wraps.
  mutating func append(contentsOf bytes: borrowing Span<UInt8>) {
    var offset = 0
    while offset < bytes.count {
      let length = min(bytes.count - offset, capacity - writeIndex)
      let source = bytes.extracting(offset..<(offset + length))
      if storage.count < capacity {
        storage.append(copying: source)
      } else {
        storage.replaceSubrange(writeIndex..<(writeIndex + length), copying: source)
      }
      offset += length
      writeIndex += length
      if writeIndex == capacity { writeIndex = 0 }
    }
  }

  /// Expands a match into output before recording it in the history window.
  /// Overlapping matches repeat bytes already produced by this same match.
  mutating func copyMatch(
    distance: Int, length: Int, into output: inout OutputSpan<UInt8>
  ) throws(HistoryWindowError) -> Int {
    let start = output.count
    let produced = try copyMatch(distance: distance, length: length, into: &output, outputStart: start)
    append(contentsOf: output.span.extracting(start...))
    return produced
  }

  /// Reads from this window and bytes produced since `outputStart`, without
  /// updating the window. The caller records output before returning a chunk.
  borrowing func copyMatch(
    distance: Int, length: Int, into output: inout OutputSpan<UInt8>, outputStart: Int
  ) throws(HistoryWindowError) -> Int {
    precondition(outputStart >= 0 && outputStart <= output.count)
    guard length >= 0 else { throw .invalidLength }
    let recentCount = output.count - outputStart
    let available = min(capacity, count + min(recentCount, capacity))
    guard distance > 0 && distance <= available else { throw .invalidDistance }
    let produced = min(length, output.freeCapacity)
    guard produced > 0 else { return 0 }
    if distance == 1 {
      let byte = recentCount > 0 ? output[output.count - 1] : try byte(distance: 1)
      output.append(repeating: byte, count: produced)
    } else if distance <= recentCount {
      output.repeatBytes(distance: distance, count: produced)
    } else {
      let historyDistance = distance - recentCount
      var offset = writeIndex - historyDistance
      if offset < 0 { offset += capacity }
      let prefix = min(historyDistance, produced)
      let first = min(prefix, capacity - offset)
      output.appendBytes(storage.span.extracting(offset..<(offset + first)))
      output.appendBytes(storage.span.extracting(0..<(prefix - first)))
      if produced > prefix {
        output.repeatBytes(distance: distance, count: produced - prefix)
      }
    }
    return produced
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
