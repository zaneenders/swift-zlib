/// Reads a dynamic header incrementally, retaining only its bounded alphabets.
struct DynamicHuffmanHeaderReader {
  private var literalCount = 0
  private var distanceCount = 0
  private var codeLengthCount = 0
  private var codeLengthIndex = 0
  private var codeLengths = [Int](repeating: 0, count: 19)
  private var codeLengthDecoder: HuffmanDecoder?
  private var lengths: [Int] = []

  mutating func read(from reader: inout BitReader) throws(InflateError) -> (
    literalLength: HuffmanDecoder, distance: HuffmanDecoder
  ) {
    if literalCount == 0 {
      let counts = try reader.readBits(14)
      literalCount = Int(counts & 31) + 257
      distanceCount = Int((counts >> 5) & 31) + 1
      codeLengthCount = Int(counts >> 10) + 4
      guard literalCount <= 286 && distanceCount <= 30 else {
        throw .invalidHuffmanTable
      }
      lengths.reserveCapacity(literalCount + distanceCount)
    }
    while codeLengthIndex < codeLengthCount {
      codeLengths[huffmanCodeLengthOrder[codeLengthIndex]] = Int(try reader.readBits(3))
      codeLengthIndex += 1
    }
    if codeLengthDecoder == nil {
      codeLengthDecoder = try HuffmanDecoder(lengths: codeLengths, alphabet: .codeLength)
    }
    let total = literalCount + distanceCount
    while lengths.count < total {
      let checkpoint = reader.checkpoint()
      let length: Int
      let count: Int
      do throws(InflateError) {
        let symbol = try codeLengthDecoder!.readSymbol(from: &reader)
        switch symbol {
        case 0...15:
          length = Int(symbol)
          count = 1
        case 16:
          guard let previous = lengths.last else {
            throw InflateError.invalidHuffmanTable
          }
          length = previous
          count = Int(try reader.readBits(2)) + 3
        case 17:
          length = 0
          count = Int(try reader.readBits(3)) + 3
        case 18:
          length = 0
          count = Int(try reader.readBits(7)) + 11
        default:
          throw InflateError.invalidHuffmanTable
        }
      } catch {
        reader.restore(checkpoint)
        throw error
      }
      guard count <= total - lengths.count else {
        throw .invalidHuffmanTable
      }
      for _ in 0..<count {
        lengths.append(length)
      }
    }
    guard lengths[256] > 0 else {
      throw .invalidHuffmanTable
    }
    return (
      try HuffmanDecoder(lengths: Array(lengths.prefix(literalCount)), alphabet: .literalLength),
      try HuffmanDecoder(lengths: Array(lengths.suffix(distanceCount)), alphabet: .distance)
    )
  }
}
