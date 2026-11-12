/// Incremental zlib framing around the shared DEFLATE engine.
struct ZlibDecoder: ~Copyable, ~Sendable {
  private enum Phase {
    case header
    case body
    case trailer
    case finished
    case failed
  }

  private var phase = Phase.header
  private var header: UInt16 = 0
  private var headerCount = 0
  private var checksum = Adler32()
  private var trailer: UInt32 = 0
  private var trailerCount = 0
  var isFinished: Bool { phase == .finished }

  mutating func process(
    input: borrowing Span<UInt8>, output: inout OutputSpan<UInt8>, inflater: inout RawInflater,
    isFinalInput: Bool
  ) throws(InflateError) -> Inflater.Progress {
    guard phase != .failed else { throw .invalidState }
    let initialOutputCount = output.count
    var offset = 0
    do throws(InflateError) {
      while true {
        switch phase {
        case .header:
          while headerCount < 2 && offset < input.count {
            header = (header << 8) | UInt16(input[offset])
            headerCount += 1
            offset += 1
          }
          guard headerCount == 2 else {
            if isFinalInput { throw .unexpectedEndOfInput }
            return Inflater.Progress(
              inputConsumed: offset, outputProduced: output.count - initialOutputCount, status: .needsInput)
          }
          guard (header >> 8) & 0x0F == 8 else {
            throw .unsupportedCompressionMethod
          }
          let windowBits = Int(header >> 12) + 8
          guard windowBits <= 15 && header % 31 == 0 else {
            throw .invalidZlibHeader
          }
          guard header & 0x20 == 0 else {
            throw .unsupportedDictionary
          }
          inflater.maximumDistance = 1 << windowBits
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
          while trailerCount < 4 && offset < input.count {
            trailer = (trailer << 8) | UInt32(input[offset])
            trailerCount += 1
            offset += 1
          }
          guard trailerCount == 4 else {
            if isFinalInput { throw .unexpectedEndOfInput }
            return Inflater.Progress(
              inputConsumed: offset, outputProduced: output.count - initialOutputCount, status: .needsInput)
          }
          guard trailer == checksum.value else {
            throw .checksumMismatch
          }
          phase = .finished
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
      checksum.update(input: output.span.extracting(initialCount...))
    }
    return try inflater.process(input: input, output: &output, isFinalInput: isFinalInput)
  }
}
