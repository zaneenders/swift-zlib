enum DeflateEncoder: ~Sendable {
  static func automatic(input: borrowing Span<UInt8>) throws(BitWriterError) -> UniqueArray<UInt8> {
    var writer = BitWriter(minimumCapacity: min(input.count, 65_536))
    var finder = LZ77MatchFinder()
    var position = 0
    repeat {
      let end = position + min(65_535, input.count - position)
      try writeAutomaticBlock(
        input: input, position: &position, end: end, isFinal: end == input.count,
        finder: &finder, writer: &writer)
    } while position < input.count
    return writer.finish()
  }

  static func stored(input: borrowing Span<UInt8>) throws(BitWriterError) -> UniqueArray<UInt8> {
    var writer = BitWriter(minimumCapacity: input.count)
    var offset = 0
    repeat {
      let blockLength = min(input.count - offset, Int(UInt16.max))
      let end = offset + blockLength
      writeStoredBlock(input: input.extracting(offset..<end), isFinal: end == input.count, writer: &writer)
      offset = end
    } while offset < input.count
    return writer.finish()
  }

  static func fixed(input: borrowing Span<UInt8>) throws(BitWriterError) -> UniqueArray<UInt8> {
    var writer = BitWriter(minimumCapacity: min(input.count, 65_536))
    var finder = LZ77MatchFinder()
    var position = 0
    try writeFixedBlock(
      input: input, position: &position, end: input.count, isFinal: true, finder: &finder, writer: &writer)
    return writer.finish()
  }

  static func dynamic(input: borrowing Span<UInt8>) throws(BitWriterError) -> UniqueArray<UInt8> {
    var writer = BitWriter(minimumCapacity: min(input.count, 65_536))
    var finder = LZ77MatchFinder()
    var position = 0
    repeat {
      // Bound temporary token storage while preserving history across blocks.
      let end = position + min(65_535, input.count - position)
      try writeDynamicBlock(
        input: input, position: &position, end: end, isFinal: end == input.count,
        finder: &finder, writer: &writer)
    } while position < input.count
    return writer.finish()
  }

  /// Appends a stored block, including its alignment and length fields.
  static func writeStoredBlock(input: borrowing Span<UInt8>, isFinal: Bool, writer: inout BitWriter) {
    precondition(input.count <= Int(UInt16.max))
    writer.writeBits(isFinal ? 0b001 : 0b000, count: 3)
    writer.alignToByte()
    let length = UInt16(input.count)
    writer.writeUInt16LittleEndian(length)
    writer.writeUInt16LittleEndian(~length)
    writer.alignToByte()
    writer.writeBytes(input)
  }

  /// Appends a fixed-Huffman block using the supplied match history.
  static func writeFixedBlock(
    input: borrowing Span<UInt8>, position: inout Int, end: Int, isFinal: Bool,
    finder: inout LZ77MatchFinder, writer: inout BitWriter
  ) throws(BitWriterError) {
    precondition(position >= 0 && position <= end && end <= input.count)
    writer.writeBits(isFinal ? 0b011 : 0b010, count: 3)
    while position < end {
      let token = finder.next(input: input, position: &position, end: end)
      try writeFixedToken(token, writer: &writer)
    }
    try writer.writeFixedLiteralLengthSymbol(256)
  }

  /// Appends a dynamic-Huffman block using the supplied match history.
  static func writeDynamicBlock(
    input: borrowing Span<UInt8>, position: inout Int, end: Int, isFinal: Bool,
    finder: inout LZ77MatchFinder, writer: inout BitWriter
  ) throws(BitWriterError) {
    let analysis = DeflateBlockAnalysis(input: input, position: &position, end: end, finder: &finder)
    let plan = DynamicDeflateBlock(analysis: analysis)
    plan.write(tokens: analysis.tokens.span, isFinal: isFinal, writer: &writer)
  }

  /// Tokenizes once and emits the least expensive representation of this block.
  /// Final padding and a following sync marker affect selection but are left
  /// to the caller to emit.
  static func writeAutomaticBlock(
    input: borrowing Span<UInt8>, position: inout Int, end: Int, isFinal: Bool, syncFlush: Bool = false,
    finder: inout LZ77MatchFinder, writer: inout BitWriter
  ) throws(BitWriterError) {
    let start = position
    precondition(start >= 0 && start <= end && end <= input.count && end - start <= 65_535)
    let analysis = DeflateBlockAnalysis(input: input, position: &position, end: end, finder: &finder)
    let plan = DynamicDeflateBlock(analysis: analysis)
    let costs = DeflateBlockCosts(
      inputCount: end - start, fixedBitCount: analysis.fixedBitCount, dynamicBitCount: plan.bitCount,
      bitPosition: writer.bitPosition, isFinal: isFinal, syncFlush: syncFlush)
    switch costs.choice {
    case .stored:
      // Tokenization has already advanced the finder, preserving match history
      // even when this block is emitted without compression.
      writeStoredBlock(input: input.extracting(start..<end), isFinal: isFinal, writer: &writer)
    case .fixed:
      writer.writeBits(isFinal ? 0b011 : 0b010, count: 3)
      for token in analysis.tokens { try writeFixedToken(token, writer: &writer) }
      try writer.writeFixedLiteralLengthSymbol(256)
    case .dynamic:
      plan.write(tokens: analysis.tokens.span, isFinal: isFinal, writer: &writer)
    }
  }

  private static func writeFixedToken(_ token: DeflateToken, writer: inout BitWriter) throws(BitWriterError) {
    switch token {
    case .literal(let byte):
      try writer.writeFixedLiteralLengthSymbol(UInt32(byte))
    case .match(let length, let distance):
      let lengthCode = MatchCode.length(length)
      let distanceCode = MatchCode.distance(distance)
      try writer.writeFixedLiteralLengthSymbol(UInt32(lengthCode.symbol))
      writer.writeExtraBits(lengthCode.extraBits, count: lengthCode.extraBitCount)
      writer.writeHuffmanCode(UInt16(distanceCode.symbol), bitCount: 5)
      writer.writeExtraBits(distanceCode.extraBits, count: distanceCode.extraBitCount)
    }
  }
}

/// The common token parse and actual symbol frequencies for fixed and dynamic encoding.
private struct DeflateBlockAnalysis: ~Copyable {
  let tokens: [DeflateToken]
  let literalFrequencies: [Int]
  let distanceFrequencies: [Int]
  let extraBitCount: Int
  let fixedBitCount: Int

  init(input: borrowing Span<UInt8>, position: inout Int, end: Int, finder: inout LZ77MatchFinder) {
    precondition(position >= 0 && position <= end && end <= input.count)
    var tokens: [DeflateToken] = []
    var literalFrequencies = [Int](repeating: 0, count: 286)
    var distanceFrequencies = [Int](repeating: 0, count: 30)
    var extraBitCount = 0
    var fixedBitCount = 3 + 7  // Block header and fixed end-of-block symbol.
    literalFrequencies[256] = 1
    while position < end {
      let token = finder.next(input: input, position: &position, end: end)
      tokens.append(token)
      switch token {
      case .literal(let byte):
        literalFrequencies[Int(byte)] += 1
        fixedBitCount += byte <= 143 ? 8 : 9
      case .match(let length, let distance):
        let lengthCode = MatchCode.length(length)
        let distanceCode = MatchCode.distance(distance)
        literalFrequencies[lengthCode.symbol] += 1
        distanceFrequencies[distanceCode.symbol] += 1
        let extra = lengthCode.extraBitCount + distanceCode.extraBitCount
        extraBitCount += extra
        fixedBitCount += (lengthCode.symbol <= 279 ? 7 : 8) + 5 + extra
      }
    }

    self.tokens = tokens
    self.literalFrequencies = literalFrequencies
    self.distanceFrequencies = distanceFrequencies
    self.extraBitCount = extraBitCount
    self.fixedBitCount = fixedBitCount
  }
}

/// Prepared tables shared by dynamic cost calculation and emission.
private struct DynamicDeflateBlock: ~Copyable {
  let literalLengths: [Int]
  let distanceLengths: [Int]
  let literalCodes: [UInt16?]
  let distanceCodes: [UInt16?]
  let header: DynamicHuffmanHeader
  let bitCount: Int

  init(analysis: borrowing DeflateBlockAnalysis) {
    let literalFrequencies = analysis.literalFrequencies
    var distanceFrequencies = analysis.distanceFrequencies
    if distanceFrequencies.allSatisfy({ $0 == 0 }) {
      // A legal distance table needs a symbol, but the dummy frequency must not
      // contribute to the payload cost when there are no actual matches.
      distanceFrequencies[0] = 1
    }
    let literalCount = max(257, literalFrequencies.lastIndex(where: { $0 > 0 })! + 1)
    let distanceCount = distanceFrequencies.lastIndex(where: { $0 > 0 })! + 1
    var literalLengths: [Int] = []
    huffmanCodeLengths(
      frequencies: Array(literalFrequencies.prefix(literalCount)), maxBits: 15, into: &literalLengths)
    var distanceLengths: [Int] = []
    huffmanCodeLengths(
      frequencies: Array(distanceFrequencies.prefix(distanceCount)), maxBits: 15, into: &distanceLengths)
    var literalCodes: [UInt16?] = []
    canonicalHuffmanCodes(lengths: literalLengths, into: &literalCodes)
    var distanceCodes: [UInt16?] = []
    canonicalHuffmanCodes(lengths: distanceLengths, into: &distanceCodes)
    let header = DynamicHuffmanHeader(literalLengths: literalLengths, distanceLengths: distanceLengths)
    var bitCount = 3 + header.bitCount + analysis.extraBitCount
    for symbol in literalLengths.indices {
      bitCount += analysis.literalFrequencies[symbol] * literalLengths[symbol]
    }
    for symbol in distanceLengths.indices {
      bitCount += analysis.distanceFrequencies[symbol] * distanceLengths[symbol]
    }

    self.literalLengths = literalLengths
    self.distanceLengths = distanceLengths
    self.literalCodes = literalCodes
    self.distanceCodes = distanceCodes
    self.header = header
    self.bitCount = bitCount
  }

  func write(tokens: borrowing Span<DeflateToken>, isFinal: Bool, writer: inout BitWriter) {
    writer.writeBits(isFinal ? 0b101 : 0b100, count: 3)
    header.write(to: &writer)
    for token in tokens {
      switch token {
      case .literal(let byte):
        let symbol = Int(byte)
        writer.writeHuffmanCode(literalCodes[symbol]!, bitCount: literalLengths[symbol])
      case .match(let length, let distance):
        let lengthCode = MatchCode.length(length)
        let distanceCode = MatchCode.distance(distance)
        writer.writeHuffmanCode(literalCodes[lengthCode.symbol]!, bitCount: literalLengths[lengthCode.symbol])
        writer.writeExtraBits(lengthCode.extraBits, count: lengthCode.extraBitCount)
        writer.writeHuffmanCode(distanceCodes[distanceCode.symbol]!, bitCount: distanceLengths[distanceCode.symbol])
        writer.writeExtraBits(distanceCode.extraBits, count: distanceCode.extraBitCount)
      }
    }
    writer.writeHuffmanCode(literalCodes[256]!, bitCount: literalLengths[256])
  }
}
