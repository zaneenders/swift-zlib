/// Incrementally validates a gzip header while discarding optional metadata.
struct GzipHeaderReader {
  private enum Phase {
    case fixed
    case extraLength
    case extra
    case name
    case comment
    case checksum
    case complete
  }

  private var phase = Phase.fixed
  private var fixedIndex = 0
  private var pendingFlags: UInt8 = 0
  private var fieldValue: UInt16 = 0
  private var fieldByteCount = 0
  private var extraRemaining = 0
  private var checksum = CRC32()

  var isComplete: Bool { phase == .complete }

  /// Returns the number of header bytes consumed, leaving the compressed body unread.
  /// An incomplete header retains only parsing state and can resume with fresh input.
  mutating func read(input: borrowing Span<UInt8>) throws(InflateError) -> Int {
    var consumed = 0
    while consumed < input.count && !isComplete {
      let byte = input[consumed]
      consumed += 1
      if phase != .checksum {
        checksum.update(byte: byte)
      }

      switch phase {
      case .fixed:
        switch fixedIndex {
        case 0:
          guard byte == 0x1F else { throw .invalidGzipHeader }
        case 1:
          guard byte == 0x8B else { throw .invalidGzipHeader }
        case 2:
          guard byte == 8 else { throw .unsupportedCompressionMethod }
        case 3:
          guard byte & 0xE0 == 0 else { throw .invalidGzipHeader }
          pendingFlags = byte
        default:
          break
        }
        fixedIndex += 1
        if fixedIndex == 10 {
          advanceOptionalField()
        }
      case .extraLength:
        fieldValue |= UInt16(byte) << (8 * fieldByteCount)
        fieldByteCount += 1
        if fieldByteCount == 2 {
          extraRemaining = Int(fieldValue)
          if extraRemaining == 0 {
            advanceOptionalField()
          } else {
            phase = .extra
          }
        }
      case .extra:
        extraRemaining -= 1
        if extraRemaining == 0 {
          advanceOptionalField()
        }
      case .name, .comment:
        if byte == 0 {
          advanceOptionalField()
        }
      case .checksum:
        fieldValue |= UInt16(byte) << (8 * fieldByteCount)
        fieldByteCount += 1
        if fieldByteCount == 2 {
          guard fieldValue == UInt16(truncatingIfNeeded: checksum.value) else {
            throw .headerChecksumMismatch
          }
          phase = .complete
        }
      case .complete:
        break
      }
    }
    return consumed
  }

  private mutating func advanceOptionalField() {
    fieldValue = 0
    fieldByteCount = 0
    if pendingFlags & 0x04 != 0 {
      pendingFlags &= ~0x04
      phase = .extraLength
    } else if pendingFlags & 0x08 != 0 {
      pendingFlags &= ~0x08
      phase = .name
    } else if pendingFlags & 0x10 != 0 {
      pendingFlags &= ~0x10
      phase = .comment
    } else if pendingFlags & 0x02 != 0 {
      pendingFlags &= ~0x02
      phase = .checksum
    } else {
      phase = .complete
    }
  }
}
