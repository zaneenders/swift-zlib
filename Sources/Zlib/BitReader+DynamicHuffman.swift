extension BitReader {
  mutating func readDynamicHuffmanTables() throws(BitReaderError) -> (
    literalLength: HuffmanDecoder, distance: HuffmanDecoder
  ) {
    let literalCount = Int(try readBits(5)) + 257
    let distanceCount = Int(try readBits(5)) + 1
    let codeLengthCount = Int(try readBits(4)) + 4
    guard literalCount <= 286 && distanceCount <= 30 else {
      throw .invalid
    }

    var codeLengths = [Int](repeating: 0, count: 19)
    for symbol in huffmanCodeLengthOrder.prefix(codeLengthCount) {
      codeLengths[symbol] = Int(try readBits(3))
    }
    let codeLengthDecoder = try HuffmanDecoder(lengths: codeLengths, alphabet: .codeLength)

    let total = literalCount + distanceCount
    var lengths: [Int] = []
    lengths.reserveCapacity(total)
    while lengths.count < total {
      let symbol = try codeLengthDecoder.readSymbol(from: &self)
      let length: Int
      let count: Int
      switch symbol {
      case 0...15:
        lengths.append(Int(symbol))
        continue
      case 16:
        guard let previous = lengths.last else {
          throw .invalid
        }
        length = previous
        count = Int(try readBits(2)) + 3
      case 17:
        length = 0
        count = Int(try readBits(3)) + 3
      case 18:
        length = 0
        count = Int(try readBits(7)) + 11
      default:
        throw .invalid
      }
      guard count <= total - lengths.count else {
        throw .invalid
      }
      for _ in 0..<count {
        lengths.append(length)
      }
    }

    guard lengths[256] > 0 else {
      throw .invalid
    }
    let literalLength = try HuffmanDecoder(
      lengths: Array(lengths.prefix(literalCount)), alphabet: .literalLength)
    let distance = try HuffmanDecoder(
      lengths: Array(lengths.suffix(distanceCount)), alphabet: .distance)
    return (literalLength, distance)
  }
}
