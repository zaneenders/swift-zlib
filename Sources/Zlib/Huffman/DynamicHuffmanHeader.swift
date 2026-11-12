let huffmanCodeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

struct HuffmanCodeLengthRun: Equatable {
  let symbol: Int
  let extraBits: UInt8
  let extraBitCount: Int
}

/// Encodes code lengths using DEFLATE's repeat symbols 16, 17, and 18.
func huffmanCodeLengthRuns(lengths: [Int]) -> [HuffmanCodeLengthRun] {
  precondition(lengths.allSatisfy { (0...15).contains($0) }, "Invalid Huffman code length")
  var runs: [HuffmanCodeLengthRun] = []
  var index = 0

  while index < lengths.count {
    let length = lengths[index]
    var count = 1
    while index + count < lengths.count && lengths[index + count] == length {
      count += 1
    }
    index += count

    if length == 0 {
      while count >= 11 {
        let repeated = min(count, 138)
        runs.append(.init(symbol: 18, extraBits: UInt8(repeated - 11), extraBitCount: 7))
        count -= repeated
      }
      if count >= 3 {
        runs.append(.init(symbol: 17, extraBits: UInt8(count - 3), extraBitCount: 3))
        count = 0
      }
    } else {
      // Symbol 16 must follow a length that has already been emitted.
      runs.append(.init(symbol: length, extraBits: 0, extraBitCount: 0))
      count -= 1
      while count >= 3 {
        let repeated = min(count, 6)
        runs.append(.init(symbol: 16, extraBits: UInt8(repeated - 3), extraBitCount: 2))
        count -= repeated
      }
    }

    for _ in 0..<count {
      runs.append(.init(symbol: length, extraBits: 0, extraBitCount: 0))
    }
  }

  return runs
}

/// Prepared dynamic tables shared by block cost estimation and emission.
struct DynamicHuffmanHeader {
  private let literalCount: Int
  private let distanceCount: Int
  private let codeLengthCount: Int
  private let lengths: [Int]
  private let codes: [UInt16?]
  private let runs: [HuffmanCodeLengthRun]

  /// The exact encoded size after the block's BFINAL and BTYPE bits.
  let bitCount: Int

  init(literalLengths: [Int], distanceLengths: [Int]) {
    precondition((257...286).contains(literalLengths.count), "Invalid literal/length table size")
    precondition((1...30).contains(distanceLengths.count), "Invalid distance table size")

    let runs = huffmanCodeLengthRuns(lengths: literalLengths + distanceLengths)
    var frequencies = [Int](repeating: 0, count: 19)
    for run in runs {
      frequencies[run.symbol] += 1
    }
    // Unlike the data alphabets, the code-length alphabet needs a complete tree.
    if frequencies.filter({ $0 > 0 }).count == 1 {
      frequencies[frequencies[0] == 0 ? 0 : 1] = 1
    }
    let lengths = huffmanCodeLengths(frequencies: frequencies, maxBits: 7)
    let codes = canonicalHuffmanCodes(lengths: lengths)

    let order = huffmanCodeLengthOrder
    var codeLengthCount = order.count
    while codeLengthCount > 4 && lengths[order[codeLengthCount - 1]] == 0 {
      codeLengthCount -= 1
    }

    self.literalCount = literalLengths.count
    self.distanceCount = distanceLengths.count
    self.codeLengthCount = codeLengthCount
    self.lengths = lengths
    self.codes = codes
    self.runs = runs
    var bitCount = 14 + 3 * codeLengthCount
    for run in runs {
      bitCount += lengths[run.symbol] + run.extraBitCount
    }
    self.bitCount = bitCount
  }

  func write(to writer: inout BitWriter) {
    writer.writeBits(UInt8(literalCount - 257), count: 5)
    writer.writeBits(UInt8(distanceCount - 1), count: 5)
    writer.writeBits(UInt8(codeLengthCount - 4), count: 4)
    for symbol in huffmanCodeLengthOrder.prefix(codeLengthCount) {
      writer.writeBits(UInt8(lengths[symbol]), count: 3)
    }
    for run in runs {
      writer.writeHuffmanCode(codes[run.symbol]!, bitCount: lengths[run.symbol])
      writer.writeBits(run.extraBits, count: run.extraBitCount)
    }
  }
}

extension BitWriter {
  /// Writes the dynamic tables after the block's BFINAL and BTYPE bits.
  mutating func writeDynamicHuffmanHeader(literalLengths: [Int], distanceLengths: [Int]) {
    let header = DynamicHuffmanHeader(literalLengths: literalLengths, distanceLengths: distanceLengths)
    header.write(to: &self)
  }
}
