/// Incrementally compresses raw DEFLATE, zlib, or gzip with bounded storage.
///
/// Input is buffered in blocks of up to 65,535 bytes. Compression retains a
/// 32 KiB history window across blocks and sync flushes. At most one encoded
/// block awaits output capacity. No caller storage is borrowed between calls.
/// Use `reset()` to reuse the compressor for a new independent stream.
/// All working storage is allocated at initialization. In optimized builds,
/// successful `process` calls and `reset` do not allocate, including when output
/// capacity is exhausted. Debug builds can allocate runtime metadata on first use;
/// throwing an error can allocate Swift error storage in either configuration.
public struct Deflater: ~Copyable, ~Sendable {
  public enum Flush: Equatable, Sendable {
    /// Accept input, buffering a partial block until more input arrives.
    case none
    /// Make all supplied input decodable while keeping the stream open.
    case sync
    /// End the stream after all supplied input, including its checksum trailer.
    case finish
  }

  public enum Status: Equatable, Sendable {
    /// All supplied input was accepted; a partial block may still be buffered.
    case needsInput
    /// Supply output capacity and resubmit the unconsumed input.
    case needsOutput
    /// A sync flush completed; more input may be supplied.
    case flushed
    /// The complete compressed stream, including its trailer, was emitted.
    case finished
  }

  /// The bytes accepted and appended during one call to `process`.
  public struct Progress: Sendable {
    public let inputConsumed: Int
    public let outputProduced: Int
    public let status: Status
  }

  public let format: ZLib.Format
  public let strategy: ZLib.Strategy
  /// The match-search effort retained across stream resets.
  public let effort: ZLib.Effort
  /// Input bytes accepted so far, including buffered input.
  public private(set) var totalInputCount = 0
  /// Compressed bytes emitted, excluding preexisting bytes in output spans.
  public private(set) var totalOutputCount = 0
  public var isFinished: Bool { phase == .finished }

  private enum Phase: Equatable {
    case accepting, flushing, finishing, finished, failed
  }

  private static let blockSize = 65_535
  // A literal uses at most 15 bits. A match uses at most 48 bits and consumes
  // at least three bytes, so two bytes per input byte bound the payload. The
  // extra 1 KiB covers the dynamic header, partial byte, framing, and flush.
  private static let maximumBlockOutputSize = blockSize * 2 + 1_024
  private var phase = Phase.accepting
  private var requestedFlush = Flush.none
  private var requestRemaining = 0
  private var buffer = UniqueArray<UInt8>(minimumCapacity: 32_768 + 65_535)
  private var historyCount = 0
  private var writer = BitWriter(minimumCapacity: maximumBlockOutputSize)
  private var finder: LZ77MatchFinder? = nil
  private var workspace: DeflateWorkspace? = nil
  private var adler = Adler32()
  private var crc = CRC32()

  /// Creates a compressor. Gzip uses a reproducible header without metadata.
  /// The default `.automatic` strategy compares encoded bit costs per block.
  /// `effort` controls match searching and does not change the storage budget.
  public init(
    format: ZLib.Format = .rawDeflate, strategy: ZLib.Strategy = .automatic, effort: ZLib.Effort = .balanced
  ) {
    self.format = format
    self.strategy = strategy
    self.effort = effort
    switch strategy {
    case .stored: break
    case .fixed: finder = LZ77MatchFinder(effort: effort)
    case .automatic, .dynamic:
      finder = LZ77MatchFinder(effort: effort)
      workspace = DeflateWorkspace(maximumTokens: Self.blockSize)
    }
    writeHeader()
  }

  /// Starts a new independent stream with the same format, strategy, and effort.
  ///
  /// May be called at any time, including after completion or an error. Discards
  /// buffered input, match history, pending output, and any outstanding flush
  /// request. Resets checksums and byte counts; the new header is emitted by
  /// subsequent `process` calls. Bytes already written to caller storage are
  /// unchanged and belong to the previous stream.
  ///
  /// Retains all working storage without allocating.
  public mutating func reset() {
    phase = .accepting
    requestedFlush = .none
    requestRemaining = 0
    totalInputCount = 0
    totalOutputCount = 0
    buffer.removeAll()
    historyCount = 0
    writer.reset()
    adler = Adler32()
    crc = CRC32()
    writeHeader()
  }

  /// Appends compressed bytes to the available output capacity.
  ///
  /// Advance input by `inputConsumed` after every call. With `.none`, output may
  /// be delayed until a block fills. Use `.sync` to emit all input so far without
  /// ending the stream, or `.finish` to emit the final block and container trailer.
  /// If a flush returns `.needsOutput`, retry with the same `flush` and exactly
  /// the unconsumed suffix (including an empty suffix), until `.flushed` or
  /// `.finished`. A pending request cannot be changed or extended with new input.
  /// Empty calls after completion return `.finished`; further input is an error.
  /// After an error, reset or discard the compressor. Streaming block boundaries and
  /// compressed bytes may differ from the one-shot encoder's output.
  public mutating func process(
    input: borrowing Span<UInt8>, output: inout OutputSpan<UInt8>, flush: Flush = .none
  ) throws(DeflateError) -> Progress {
    do {
      return try processInput(input: input, output: &output, flush: flush)
    } catch {
      phase = .failed
      throw error
    }
  }

  private mutating func processInput(
    input: borrowing Span<UInt8>, output: inout OutputSpan<UInt8>, flush: Flush
  ) throws(DeflateError) -> Progress {
    guard phase != .failed else { throw .invalidState }
    if phase == .finished {
      guard input.isEmpty else { throw .invalidState }
      return Progress(inputConsumed: 0, outputProduced: 0, status: .finished)
    }
    if requestedFlush != .none {
      guard flush == requestedFlush, input.count == requestRemaining else { throw .invalidState }
    } else if flush != .none {
      requestedFlush = flush
      requestRemaining = input.count
    }

    var consumed = 0
    let initialOutputCount = output.count
    while true {
      let beforeDrain = output.count
      let drained = writer.drain(output: &output)
      let (newTotal, overflow) = totalOutputCount.addingReportingOverflow(output.count - beforeDrain)
      guard !overflow else { throw .sizeOverflow }
      totalOutputCount = newTotal
      if !drained {
        return Progress(
          inputConsumed: consumed, outputProduced: output.count - initialOutputCount, status: .needsOutput)
      }

      if phase == .finishing {
        phase = .finished
        return Progress(
          inputConsumed: consumed, outputProduced: output.count - initialOutputCount, status: .finished)
      }
      if phase == .flushing {
        phase = .accepting
        requestedFlush = .none
        return Progress(
          inputConsumed: consumed, outputProduced: output.count - initialOutputCount, status: .flushed)
      }

      let count = min(Self.blockSize - (buffer.count - historyCount), input.count - consumed)
      if count > 0 {
        let (newTotal, overflow) = totalInputCount.addingReportingOverflow(count)
        guard !overflow else { throw .sizeOverflow }
        let section = input.extracting(consumed..<(consumed + count))
        buffer.append(copying: section)
        switch format {
        case .rawDeflate: break
        case .zlib: adler.update(input: section)
        case .gzip: crc.update(input: section)
        }
        consumed += count
        totalInputCount = newTotal
        if requestedFlush != .none { requestRemaining -= count }
      }

      let allInputAccepted = consumed == input.count
      if allInputAccepted && requestedFlush == .finish {
        try writeBlock(isFinal: true)
        writeTrailer()
        phase = .finishing
      } else if allInputAccepted && requestedFlush == .sync {
        if buffer.count > historyCount { try writeBlock(isFinal: false, syncFlush: true) }
        // An empty stored block aligns the stream without resetting history.
        writer.writeBits(0, count: 3)
        writer.alignToByte()
        writer.writeUInt16LittleEndian(0)
        writer.writeUInt16LittleEndian(.max)
        phase = .flushing
      } else if buffer.count - historyCount == Self.blockSize {
        try writeBlock(isFinal: false)
      } else {
        return Progress(
          inputConsumed: consumed, outputProduced: output.count - initialOutputCount, status: .needsInput)
      }
    }
  }

  private mutating func writeBlock(isFinal: Bool, syncFlush: Bool = false) throws(DeflateError) {
    do {
      switch strategy {
      case .stored:
        DeflateEncoder.writeStoredBlock(
          input: buffer.span.extracting(droppingFirst: historyCount), isFinal: isFinal, writer: &writer)
      case .automatic, .fixed, .dynamic:
        // Rebase the bounded window each block, including hashes that cross
        // from the end of the retained history into the new input.
        finder!.reset()
        finder!.seed(input: buffer.span, end: historyCount)
        var position = historyCount
        switch strategy {
        case .automatic:
          try DeflateEncoder.writeAutomaticBlock(
            input: buffer.span, position: &position, end: buffer.count,
            isFinal: isFinal, syncFlush: syncFlush, finder: &finder!, workspace: &workspace!, writer: &writer)
        case .fixed:
          try DeflateEncoder.writeFixedBlock(
            input: buffer.span, position: &position, end: buffer.count,
            isFinal: isFinal, finder: &finder!, writer: &writer)
        case .dynamic:
          try DeflateEncoder.writeDynamicBlock(
            input: buffer.span, position: &position, end: buffer.count,
            isFinal: isFinal, finder: &finder!, workspace: &workspace!, writer: &writer)
        case .stored:
          break
        }
      }
    } catch {
      throw .encodingError(error)
    }

    let retained: Int
    switch strategy {
    case .stored: retained = 0
    case .automatic, .fixed, .dynamic: retained = min(buffer.count, 32_768)
    }
    let start = buffer.count - retained
    for index in 0..<retained { buffer[index] = buffer[start + index] }
    buffer.removeLast(buffer.count - retained)
    historyCount = retained
  }

  private mutating func writeHeader() {
    switch format {
    case .rawDeflate:
      break
    case .zlib:
      writer.writeBits(0x78, count: 8)
      writer.writeBits(0x01, count: 8)
    case .gzip:
      let header: InlineArray<10, UInt8> = [0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 255]
      for index in 0..<header.count { writer.writeBits(header[index], count: 8) }
    }
  }

  private mutating func writeTrailer() {
    writer.alignToByte()
    switch format {
    case .rawDeflate:
      break
    case .zlib:
      for index in 0..<4 {
        let shift = 24 - index * 8
        writer.writeBits(UInt8(truncatingIfNeeded: adler.value >> shift), count: 8)
      }
    case .gzip:
      let values: InlineArray<2, UInt32> = [crc.value, UInt32(truncatingIfNeeded: totalInputCount)]
      for index in 0..<values.count {
        let value = values[index]
        for byte in 0..<4 {
          let shift = byte * 8
          writer.writeBits(UInt8(truncatingIfNeeded: value >> shift), count: 8)
        }
      }
    }
  }
}
