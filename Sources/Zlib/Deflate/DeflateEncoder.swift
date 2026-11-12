enum DeflateEncoder: ~Sendable {
  static func stored(input: borrowing Span<UInt8>) throws(BitWriterError) -> UniqueArray<UInt8> {
    var writer = BitWriter(minimumCapacity: input.count)
    var offset = 0
    repeat {
      let blockLength = min(input.count - offset, Int(UInt16.max))
      let end = offset + blockLength
      writer.writeBits(end == input.count ? 0b001 : 0b000, count: 3)
      writer.alignToByte()
      let length = UInt16(blockLength)
      writer.writeUInt16LittleEndian(length)
      writer.writeUInt16LittleEndian(~length)
      let section = input.extracting(offset..<end)
      for byte in section {
        writer.writeBits(byte, count: 8)
      }
      offset = end
    } while offset < input.count
    return writer.finish()
  }

  static func fixed(input: borrowing Span<UInt8>) throws(BitWriterError) -> UniqueArray<UInt8> {
    var writer = BitWriter(minimumCapacity: min(input.count, 65_536))
    var finder = LZ77MatchFinder()
    var position = 0
    writer.writeBits(0b011, count: 3)
    while position < input.count {
      switch finder.next(input: input, position: &position, end: input.count) {
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
    try writer.writeFixedLiteralLengthSymbol(256)
    return writer.finish()
  }

  static func dynamic(input: borrowing Span<UInt8>) throws(BitWriterError) -> UniqueArray<UInt8> {
    var writer = BitWriter(minimumCapacity: min(input.count, 65_536))
    var finder = LZ77MatchFinder()
    var position = 0
    repeat {
      // Bound temporary token storage while preserving history across blocks.
      let end = position + min(65_535, input.count - position)
      var tokens: [DeflateToken] = []
      var literalFrequencies = [Int](repeating: 0, count: 286)
      var distanceFrequencies = [Int](repeating: 0, count: 30)
      literalFrequencies[256] = 1
      while position < end {
        let token = finder.next(input: input, position: &position, end: end)
        tokens.append(token)
        switch token {
        case .literal(let byte):
          literalFrequencies[Int(byte)] += 1
        case .match(let length, let distance):
          literalFrequencies[MatchCode.length(length).symbol] += 1
          distanceFrequencies[MatchCode.distance(distance).symbol] += 1
        }
      }
      if distanceFrequencies.allSatisfy({ $0 == 0 }) {
        distanceFrequencies[0] = 1
      }
      let literalCount = max(257, literalFrequencies.lastIndex(where: { $0 > 0 })! + 1)
      let distanceCount = distanceFrequencies.lastIndex(where: { $0 > 0 })! + 1
      let literalLengths = huffmanCodeLengths(frequencies: Array(literalFrequencies.prefix(literalCount)), maxBits: 15)
      let distanceLengths = huffmanCodeLengths(
        frequencies: Array(distanceFrequencies.prefix(distanceCount)), maxBits: 15)
      let literalCodes = canonicalHuffmanCodes(lengths: literalLengths)
      let distanceCodes = canonicalHuffmanCodes(lengths: distanceLengths)
      writer.writeBits(position == input.count ? 0b101 : 0b100, count: 3)
      writer.writeDynamicHuffmanHeader(literalLengths: literalLengths, distanceLengths: distanceLengths)
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
    } while position < input.count
    return writer.finish()
  }
}
