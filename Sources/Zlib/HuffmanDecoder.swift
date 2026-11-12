/// A validated canonical Huffman alphabet, indexed by code length and symbol order.
struct HuffmanDecoder {
  enum Alphabet {
    case codeLength
    case literalLength
    case distance
  }

  private let counts: [Int]
  private let firstCodes: [Int]
  private let symbolOffsets: [Int]
  private let symbols: [UInt32]
  private let maxLength: Int

  init(lengths: [Int], alphabet: Alphabet) throws(BitReaderError) {
    let limit = alphabet == .codeLength ? 7 : 15
    guard lengths.allSatisfy({ (0...limit).contains($0) }) else {
      throw .invalid
    }
    let maxLength = lengths.max() ?? 0
    var counts = [Int](repeating: 0, count: maxLength + 1)
    for length in lengths where length > 0 {
      counts[length] += 1
    }

    if maxLength == 0 {
      // Literal-only blocks may omit every distance symbol.
      guard alphabet == .distance else {
        throw .invalid
      }
    } else {
      var available = 1
      for length in 1...maxLength {
        available = (available << 1) - counts[length]
        guard available >= 0 else {
          throw .invalid
        }
      }
      // Only the data alphabets permit a single symbol with a one-bit code.
      guard available == 0 || (alphabet != .codeLength && maxLength == 1) else {
        throw .invalid
      }
    }

    var firstCodes = [Int](repeating: 0, count: counts.count)
    var symbolOffsets = [Int](repeating: 0, count: counts.count)
    var code = 0
    var symbolCount = 0
    for length in 1..<counts.count {
      code = (code + counts[length - 1]) << 1
      firstCodes[length] = code
      symbolOffsets[length] = symbolCount
      symbolCount += counts[length]
    }

    var symbols = [UInt32](repeating: 0, count: symbolCount)
    var nextOffsets = symbolOffsets
    for (symbol, length) in lengths.enumerated() where length > 0 {
      symbols[nextOffsets[length]] = UInt32(symbol)
      nextOffsets[length] += 1
    }

    self.counts = counts
    self.firstCodes = firstCodes
    self.symbolOffsets = symbolOffsets
    self.symbols = symbols
    self.maxLength = maxLength
  }

  func readSymbol(from reader: inout BitReader) throws(BitReaderError) -> UInt32 {
    guard maxLength > 0 else {
      throw .invalid
    }
    var code = 0
    for length in 1...maxLength {
      code = (code << 1) | Int(try reader.readBits(1))
      let offset = code - firstCodes[length]
      if offset >= 0 && offset < counts[length] {
        return symbols[symbolOffsets[length] + offset]
      }
    }
    throw .invalid
  }
}
