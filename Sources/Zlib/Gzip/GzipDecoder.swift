/// Incremental gzip framing around the shared DEFLATE engine.
struct GzipDecoder: ~Copyable, ~Sendable {
  private enum Phase {
    case header
    case body
    case trailer
    case betweenMembers
    case finished
    case failed
  }

  private var phase = Phase.header
  private var header = GzipHeaderReader()
  private var checksum = CRC32()
  private var trailer: UInt64 = 0
  private var trailerCount = 0
  private(set) var totalOutputCount = 0
  var isFinished: Bool { phase == .finished }

  mutating func process(
    input: borrowing Span<UInt8>, output: inout OutputSpan<UInt8>, inflater: inout RawInflater,
    maximumOutputSize: Int, isFinalInput: Bool
  ) throws(InflateError) -> Inflater.Progress {
    guard phase != .failed else { throw .invalidState }
    let initialOutputCount = output.count
    var offset = 0
    do throws(InflateError) {
      while true {
        switch phase {
        case .header:
          offset += try header.read(input: input.extracting(offset...))
          guard header.isComplete else {
            if isFinalInput { throw .unexpectedEndOfInput }
            return Inflater.Progress(
              inputConsumed: offset, outputProduced: output.count - initialOutputCount, status: .needsInput)
          }
          phase = .body
        case .body:
          let step = try processBody(
            input: input.extracting(offset...), output: &output,
            inflater: &inflater, isFinalInput: isFinalInput)
          offset += step.inputConsumed
          guard step.status == .finished else {
            return Inflater.Progress(
              inputConsumed: offset, outputProduced: output.count - initialOutputCount, status: step.status)
          }
          phase = .trailer
        case .trailer:
          while trailerCount < 8 && offset < input.count {
            trailer |= UInt64(input[offset]) << (trailerCount * 8)
            trailerCount += 1
            offset += 1
          }
          guard trailerCount == 8 else {
            if isFinalInput { throw .unexpectedEndOfInput }
            return Inflater.Progress(
              inputConsumed: offset, outputProduced: output.count - initialOutputCount, status: .needsInput)
          }
          guard UInt32(truncatingIfNeeded: trailer) == checksum.value else {
            throw .checksumMismatch
          }
          guard UInt32(trailer >> 32) == UInt32(truncatingIfNeeded: inflater.totalOutputCount) else {
            throw .sizeMismatch
          }
          phase = .betweenMembers
        case .betweenMembers:
          if offset == input.count {
            if isFinalInput { phase = .finished }
            return Inflater.Progress(
              inputConsumed: offset, outputProduced: output.count - initialOutputCount,
              status: isFinalInput ? .finished : .needsInput)
          }
          // A member starts a new DEFLATE history and checksum, but shares the
          // stream's remaining output budget with every preceding member.
          inflater = try RawInflater(maximumOutputSize: maximumOutputSize - totalOutputCount)
          header = GzipHeaderReader()
          checksum = CRC32()
          trailer = 0
          trailerCount = 0
          phase = .header
        case .finished:
          return Inflater.Progress(
            inputConsumed: offset, outputProduced: output.count - initialOutputCount, status: .finished)
        case .failed:
          throw .invalidState
        }
      }
    } catch {
      phase = .failed
      throw error
    }
  }

  private mutating func processBody(
    input: borrowing Span<UInt8>, output: inout OutputSpan<UInt8>,
    inflater: inout RawInflater, isFinalInput: Bool
  ) throws(InflateError) -> Inflater.Progress {
    let initialCount = output.count
    defer {
      totalOutputCount += output.count - initialCount
      checksum.update(input: output.span.extracting(initialCount...))
    }
    return try inflater.process(input: input, output: &output, isFinalInput: isFinalInput)
  }
}
