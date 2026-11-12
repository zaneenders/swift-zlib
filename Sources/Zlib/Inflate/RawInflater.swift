/// The raw DEFLATE engine shared by bare streams and container formats.
struct RawInflater: ~Copyable, ~Sendable {
  typealias Status = Inflater.Status
  typealias Progress = Inflater.Progress

  private enum Phase {
    case header
    case storedLength
    case stored
    case dynamicHeader
    case compressed
    case literal
    case match
    case finished
    case failed
  }

  /// The maximum number of decoded bytes permitted over the entire stream.
  let maximumOutputSize: Int
  /// Container formats may declare a smaller window than DEFLATE's 32 KiB maximum.
  var maximumDistance = 32_768
  /// Decoded bytes emitted so far, excluding preexisting bytes in output spans.
  private(set) var totalOutputCount = 0
  var isFinished: Bool { phase == .finished }

  private var phase = Phase.header
  private var bufferedBits = BufferedBits()
  private var history = HistoryWindow()
  private var storedBlock = PendingStoredBlock(length: 0)
  private var match = PendingMatch(distance: 1, length: 0)
  private var dynamicHeader = DynamicHuffmanHeaderReader()
  private var literalLengthDecoder: HuffmanDecoder?
  private var distanceDecoder: HuffmanDecoder?
  private var isFinalBlock = false
  private var usesFixedHuffman = false
  private var literal: UInt8 = 0

  /// Creates a decoder, rejecting negative output limits.
  init(maximumOutputSize: Int = .max) throws(InflateError) {
    guard maximumOutputSize >= 0 else {
      throw .invalidOutputLimit
    }
    self.maximumOutputSize = maximumOutputSize
  }

  /// Appends decoded bytes to the available output capacity.
  ///
  /// Set `isFinalInput` when no further input will arrive. An incomplete stream
  /// then throws `unexpectedEndOfInput`. A full output may still return
  /// `needsOutput`; pass any unconsumed input again with fresh output storage.
  /// On an error, output may contain a valid prefix and this instance cannot resume.
  mutating func process(
    input: borrowing Span<UInt8>, output: inout OutputSpan<UInt8>, isFinalInput: Bool = false
  ) throws(InflateError) -> Progress {
    guard phase != .failed else {
      throw .invalidState
    }
    let initialOutputCount = output.count
    var reader = BitReader(input.bytes, bufferedBits: bufferedBits)
    do throws(InflateError) {
      while true {
        do throws(InflateError) {
          switch phase {
          case .header:
            let header = try reader.readBlockHeader()
            isFinalBlock = header.isFinal
            switch header.blockType {
            case .stored: phase = .storedLength
            case .fixedHuffman:
              usesFixedHuffman = true
              phase = .compressed
            case .dynamicHuffman:
              usesFixedHuffman = false
              dynamicHeader = DynamicHuffmanHeaderReader()
              phase = .dynamicHeader
            }
          case .storedLength:
            let (length, _) = try reader.readStoredLength()
            try requireOutputSpace(Int(length))
            storedBlock = PendingStoredBlock(length: length)
            phase = .stored
          case .stored:
            try emitStored(from: &reader, into: &output)
            if storedBlock.isComplete {
              finishBlock()
            } else {
              return progress(from: &reader, produced: output.count - initialOutputCount, status: .needsOutput)
            }
          case .dynamicHeader:
            let tables = try dynamicHeader.read(from: &reader)
            literalLengthDecoder = tables.literalLength
            distanceDecoder = tables.distance
            phase = .compressed
          case .compressed:
            try readToken(from: &reader)
          case .literal:
            guard output.count < output.capacity else {
              return progress(from: &reader, produced: output.count - initialOutputCount, status: .needsOutput)
            }
            output.append(literal)
            history.appendLiteral(literal)
            totalOutputCount += 1
            phase = .compressed
          case .match:
            do throws(HistoryWindowError) {
              let produced = try match.emit(into: &output, history: &history)
              totalOutputCount += produced
            } catch {
              throw InflateError.invalidDistance
            }
            if match.isComplete {
              phase = .compressed
            } else {
              return progress(from: &reader, produced: output.count - initialOutputCount, status: .needsOutput)
            }
          case .finished:
            return progress(from: &reader, produced: output.count - initialOutputCount, status: .finished)
          case .failed:
            throw InflateError.invalidState
          }
        } catch {
          guard error == .unexpectedEndOfInput && !isFinalInput else {
            throw error
          }
          return progress(from: &reader, produced: output.count - initialOutputCount, status: .needsInput)
        }
      }
    } catch {
      phase = .failed
      throw error
    }
  }

  private mutating func readToken(from reader: inout BitReader) throws(InflateError) {
    let checkpoint = reader.checkpoint()
    do throws(InflateError) {
      let symbol =
        if usesFixedHuffman {
          try reader.readFixedLiteralLengthSymbol()
        } else {
          try literalLengthDecoder!.readSymbol(from: &reader)
        }
      switch symbol {
      case 0...255:
        try requireOutputSpace(1)
        literal = UInt8(symbol)
        phase = .literal
      case 256:
        finishBlock()
      case 257...285:
        let length = Int(try reader.readMatchLength(symbol: symbol))
        let distance: Int
        if usesFixedHuffman {
          distance = Int(try reader.readFixedMatchDistance())
        } else {
          let distanceSymbol = try distanceDecoder!.readSymbol(from: &reader)
          distance = Int(try reader.readMatchDistance(symbol: distanceSymbol))
        }
        guard distance > 0 && distance <= history.count && distance <= maximumDistance else {
          throw InflateError.invalidDistance
        }
        try requireOutputSpace(length)
        match = PendingMatch(distance: distance, length: length)
        phase = .match
      default:
        throw InflateError.forbiddenSymbol
      }
    } catch {
      reader.restore(checkpoint)
      throw error
    }
  }

  private func requireOutputSpace(_ count: Int) throws(InflateError) {
    guard count <= maximumOutputSize - totalOutputCount else {
      throw .outputLimitExceeded
    }
  }

  private mutating func emitStored(
    from reader: inout BitReader, into output: inout OutputSpan<UInt8>
  ) throws(InflateError) {
    let initialCount = output.count
    defer { totalOutputCount += output.count - initialCount }
    try storedBlock.emit(from: &reader, into: &output, history: &history)
  }

  private mutating func finishBlock() {
    phase = isFinalBlock ? .finished : .header
  }

  private mutating func progress(
    from reader: inout BitReader, produced: Int, status: Status
  ) -> Progress {
    let remainder = reader.remainder(includingUnreadBytes: status == .needsInput)
    bufferedBits = remainder.bits
    return Progress(inputConsumed: remainder.consumed, outputProduced: produced, status: status)
  }
}
