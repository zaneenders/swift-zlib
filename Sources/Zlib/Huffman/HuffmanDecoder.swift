/// A validated canonical alphabet decoded with a root table and bounded subtables.
struct HuffmanDecoder: Sendable {
  enum Alphabet {
    case codeLength
    case literalLength
    case distance
  }

  private struct Entry: Sendable {
    // A leaf stores a symbol; a root with subtable bits stores an array offset.
    let value: UInt32
    let bitCount: UInt8
    let subtableBitCount: UInt8

    static let invalid = Entry(value: 0, bitCount: 0, subtableBitCount: 0)
  }

  private let table: [Entry]
  private let rootBitCount: Int
  private let maxLength: Int

  static let fixedLiteralLength = try! HuffmanDecoder(
    lengths: [Int](repeating: 8, count: 144) + [Int](repeating: 9, count: 112)
      + [Int](repeating: 7, count: 24) + [Int](repeating: 8, count: 8),
    alphabet: .literalLength)

  init(lengths: [Int], alphabet: Alphabet) throws(BitReaderError) {
    let limit = alphabet == .codeLength ? 7 : 15
    guard lengths.allSatisfy({ (0...limit).contains($0) }) else {
      throw .invalidHuffmanTable
    }
    let maxLength = lengths.max() ?? 0
    var counts = [Int](repeating: 0, count: maxLength + 1)
    for length in lengths where length > 0 {
      counts[length] += 1
    }

    if maxLength == 0 {
      // Literal-only blocks may omit every distance symbol.
      guard alphabet == .distance else {
        throw .invalidHuffmanTable
      }
      self.table = []
      self.rootBitCount = 0
      self.maxLength = 0
      return
    } else {
      var available = 1
      for length in 1...maxLength {
        available = (available << 1) - counts[length]
        guard available >= 0 else {
          throw .invalidHuffmanTable
        }
      }
      // Only the data alphabets permit a single symbol with a one-bit code.
      guard available == 0 || (alphabet != .codeLength && maxLength == 1) else {
        throw .invalidHuffmanTable
      }
    }

    var nextCodes = [Int](repeating: 0, count: counts.count)
    var code = 0
    for length in 1..<counts.count {
      code = (code + counts[length - 1]) << 1
      nextCodes[length] = code
    }

    let rootBitCount = min(maxLength, alphabet == .distance ? 6 : 9)
    let rootSize = 1 << rootBitCount
    var reversedCodes = [Int](repeating: 0, count: lengths.count)
    var subtableWidths = [Int](repeating: 0, count: rootSize)
    for (symbol, length) in lengths.enumerated() where length > 0 {
      var code = nextCodes[length]
      nextCodes[length] += 1
      var reversed = 0
      for _ in 0..<length {
        reversed = (reversed << 1) | (code & 1)
        code >>= 1
      }
      reversedCodes[symbol] = reversed
      if length > rootBitCount {
        let prefix = reversed & (rootSize - 1)
        subtableWidths[prefix] = max(subtableWidths[prefix], length - rootBitCount)
      }
    }

    var table = [Entry](repeating: .invalid, count: rootSize)
    for prefix in 0..<rootSize where subtableWidths[prefix] > 0 {
      let width = subtableWidths[prefix]
      table[prefix] = Entry(
        value: UInt32(table.count), bitCount: UInt8(rootBitCount), subtableBitCount: UInt8(width))
      table.append(contentsOf: repeatElement(.invalid, count: 1 << width))
    }
    for (symbol, length) in lengths.enumerated() where length > 0 {
      let entry = Entry(value: UInt32(symbol), bitCount: UInt8(length), subtableBitCount: 0)
      let reversed = reversedCodes[symbol]
      if length <= rootBitCount {
        for index in stride(from: reversed, to: rootSize, by: 1 << length) {
          table[index] = entry
        }
      } else {
        let root = table[reversed & (rootSize - 1)]
        let base = Int(root.value)
        for index in stride(
          from: reversed >> rootBitCount, to: 1 << Int(root.subtableBitCount), by: 1 << (length - rootBitCount)
        ) {
          table[base + index] = entry
        }
      }
    }
    self.table = table
    self.rootBitCount = rootBitCount
    self.maxLength = maxLength
  }

  func readSymbol(from reader: inout BitReader) throws(BitReaderError) -> UInt32 {
    guard maxLength > 0 else {
      throw .invalidHuffmanTable
    }
    let bits = reader.peekBits(upTo: maxLength)
    var entry = table[Int(bits.value) & ((1 << rootBitCount) - 1)]
    if entry.subtableBitCount > 0 {
      let suffix = (Int(bits.value) >> rootBitCount) & ((1 << Int(entry.subtableBitCount)) - 1)
      entry = table[Int(entry.value) + suffix]
    }
    guard entry.bitCount > 0 else {
      if bits.count < maxLength { throw .unexpectedEndOfInput }
      throw .invalidHuffmanTable
    }
    guard entry.bitCount <= bits.count else { throw .unexpectedEndOfInput }
    reader.dropBits(Int(entry.bitCount))
    return entry.value
  }
}
