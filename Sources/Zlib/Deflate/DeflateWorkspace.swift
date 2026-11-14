import struct BasicContainers.RigidArray

/// Reused token analysis and dynamic tables for blocks of at most 65,535 bytes.
/// No array is shared outside this owner, so preparing a block cannot trigger CoW.
struct DeflateWorkspace: ~Copyable {
  var tokens: RigidArray<DeflateToken>
  private var literalFrequencies = [Int](repeating: 0, count: 286)
  private var distanceFrequencies = [Int](repeating: 0, count: 30)
  private var literalLengths: [Int] = []
  private var distanceLengths: [Int] = []
  private var literalCodes: [UInt16?] = []
  private var distanceCodes: [UInt16?] = []
  private var huffman = HuffmanWorkspace(maximumSymbols: 286)
  private var header = DynamicHuffmanHeader()
  private(set) var fixedBitCount = 0
  private(set) var dynamicBitCount = 0

  init(maximumTokens: Int) {
    precondition((0...65_535).contains(maximumTokens))
    // Every token consumes at least one byte of the block's input.
    tokens = RigidArray(capacity: maximumTokens)
    literalLengths.reserveCapacity(286)
    distanceLengths.reserveCapacity(30)
    literalCodes.reserveCapacity(286)
    distanceCodes.reserveCapacity(30)
  }

  mutating func prepare(
    input: borrowing Span<UInt8>, position: inout Int, end: Int, finder: inout LZ77MatchFinder
  ) {
    precondition(position >= 0 && position <= end && end <= input.count)
    precondition(end - position <= tokens.capacity)
    tokens.removeAll()
    for index in literalFrequencies.indices { literalFrequencies[index] = 0 }
    for index in distanceFrequencies.indices { distanceFrequencies[index] = 0 }
    literalFrequencies[256] = 1
    fixedBitCount = 3 + 7
    var extraBitCount = 0
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

    var distanceCount = distanceFrequencies.count
    while distanceCount > 0 && distanceFrequencies[distanceCount - 1] == 0 { distanceCount -= 1 }
    let noDistances = distanceCount == 0
    // A legal distance table needs a symbol even in a literal-only block.
    if noDistances {
      distanceFrequencies[0] = 1
      distanceCount = 1
    }
    var literalCount = literalFrequencies.count
    while literalCount > 257 && literalFrequencies[literalCount - 1] == 0 { literalCount -= 1 }
    huffman.codeLengths(
      frequencies: literalFrequencies.span.extracting(first: literalCount), maxBits: 15, into: &literalLengths)
    huffman.codeLengths(
      frequencies: distanceFrequencies.span.extracting(first: distanceCount), maxBits: 15, into: &distanceLengths)
    // The dummy symbol must not contribute to the encoded payload's cost.
    if noDistances { distanceFrequencies[0] = 0 }
    canonicalHuffmanCodes(lengths: literalLengths, into: &literalCodes)
    canonicalHuffmanCodes(lengths: distanceLengths, into: &distanceCodes)
    header.prepare(literalLengths: literalLengths.span, distanceLengths: distanceLengths.span, workspace: &huffman)
    dynamicBitCount = 3 + header.bitCount + extraBitCount
    for symbol in literalLengths.indices {
      dynamicBitCount += literalFrequencies[symbol] * literalLengths[symbol]
    }
    for symbol in distanceLengths.indices {
      dynamicBitCount += distanceFrequencies[symbol] * distanceLengths[symbol]
    }
  }

  func writeDynamicBlock(isFinal: Bool, writer: inout BitWriter) {
    writer.writeBits(isFinal ? 0b101 : 0b100, count: 3)
    header.write(to: &writer)
    for index in 0..<tokens.count {
      let token = tokens[index]
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
