let huffmanCodeLengthOrder: InlineArray<19, Int> = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

struct HuffmanCodeLengthRun: Equatable {
  let symbol: Int
  let extraBits: UInt8
  let extraBitCount: Int
}

/// Encodes code lengths using DEFLATE's repeat symbols 16, 17, and 18.
/// Replaces `runs`, reusing its capacity when possible.
func huffmanCodeLengthRuns(lengths: [Int], into runs: inout [HuffmanCodeLengthRun]) {
  huffmanCodeLengthRuns(lengths: lengths.span, into: &runs)
}

private func huffmanCodeLengthRuns(lengths: borrowing Span<Int>, into runs: inout [HuffmanCodeLengthRun]) {
  runs.removeAll(keepingCapacity: true)
  var index = 0

  while index < lengths.count {
    let length = lengths[index]
    precondition((0...15).contains(length), "Invalid Huffman code length")
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
}

/// Prepared dynamic tables shared by block cost estimation and emission.
struct DynamicHuffmanHeader: ~Copyable {
  private var literalCount = 0
  private var distanceCount = 0
  private var codeLengthCount = 0
  private var lengths: [Int] = []
  private var codes: [UInt16?] = []
  private var runs: [HuffmanCodeLengthRun] = []
  private var combined: [Int] = []
  private var frequencies = [Int](repeating: 0, count: 19)

  /// The exact encoded size after the block's BFINAL and BTYPE bits.
  private(set) var bitCount = 0

  init() {
    lengths.reserveCapacity(19)
    codes.reserveCapacity(19)
    // A run represents at least one entry in the combined alphabets.
    runs.reserveCapacity(286 + 30)
    combined.reserveCapacity(286 + 30)
  }

  init(literalLengths: [Int], distanceLengths: [Int]) {
    self.init()
    var workspace = HuffmanWorkspace(maximumSymbols: 19)
    prepare(literalLengths: literalLengths.span, distanceLengths: distanceLengths.span, workspace: &workspace)
  }

  mutating func prepare(
    literalLengths: borrowing Span<Int>, distanceLengths: borrowing Span<Int>, workspace: inout HuffmanWorkspace
  ) {
    precondition((257...286).contains(literalLengths.count), "Invalid literal/length table size")
    precondition((1...30).contains(distanceLengths.count), "Invalid distance table size")

    combined.removeAll(keepingCapacity: true)
    for index in 0..<literalLengths.count { combined.append(literalLengths[index]) }
    for index in 0..<distanceLengths.count { combined.append(distanceLengths[index]) }
    huffmanCodeLengthRuns(lengths: combined.span, into: &runs)
    for index in frequencies.indices { frequencies[index] = 0 }
    for index in runs.indices {
      let run = runs[index]
      frequencies[run.symbol] += 1
    }
    // Unlike the data alphabets, the code-length alphabet needs a complete tree.
    var used = 0
    for index in frequencies.indices where frequencies[index] > 0 { used += 1 }
    if used == 1 {
      frequencies[frequencies[0] == 0 ? 0 : 1] = 1
    }
    workspace.codeLengths(frequencies: frequencies.span, maxBits: 7, into: &lengths)
    canonicalHuffmanCodes(lengths: lengths, into: &codes)

    let order = huffmanCodeLengthOrder
    var codeLengthCount = order.count
    while codeLengthCount > 4 && lengths[order[codeLengthCount - 1]] == 0 {
      codeLengthCount -= 1
    }

    self.literalCount = literalLengths.count
    self.distanceCount = distanceLengths.count
    self.codeLengthCount = codeLengthCount
    var bitCount = 14 + 3 * codeLengthCount
    for index in runs.indices {
      let run = runs[index]
      bitCount += lengths[run.symbol] + run.extraBitCount
    }
    self.bitCount = bitCount
  }

  func write(to writer: inout BitWriter) {
    writer.writeBits(UInt8(literalCount - 257), count: 5)
    writer.writeBits(UInt8(distanceCount - 1), count: 5)
    writer.writeBits(UInt8(codeLengthCount - 4), count: 4)
    for index in 0..<codeLengthCount {
      let symbol = huffmanCodeLengthOrder[index]
      writer.writeBits(UInt8(lengths[symbol]), count: 3)
    }
    for index in runs.indices {
      let run = runs[index]
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
