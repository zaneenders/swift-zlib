import Testing

@testable import Zlib

private func codeLengthRun(
  _ symbol: Int, _ extraBits: UInt8 = 0, _ extraBitCount: Int = 0
) -> HuffmanCodeLengthRun {
  .init(symbol: symbol, extraBits: extraBits, extraBitCount: extraBitCount)
}

@Test(
  arguments: [
    (0, []),
    (1, [codeLengthRun(0)]),
    (2, [codeLengthRun(0), codeLengthRun(0)]),
    (3, [codeLengthRun(17, 0, 3)]),
    (10, [codeLengthRun(17, 7, 3)]),
    (11, [codeLengthRun(18, 0, 7)]),
    (138, [codeLengthRun(18, 127, 7)]),
    (139, [codeLengthRun(18, 127, 7), codeLengthRun(0)]),
    (140, [codeLengthRun(18, 127, 7), codeLengthRun(0), codeLengthRun(0)]),
    (141, [codeLengthRun(18, 127, 7), codeLengthRun(17, 0, 3)]),
    (276, [codeLengthRun(18, 127, 7), codeLengthRun(18, 127, 7)])
  ] as [(count: Int, expected: [HuffmanCodeLengthRun])])
func dynamicHuffmanHeaderEncodesZeroRunBoundaries(
  testCase: (count: Int, expected: [HuffmanCodeLengthRun])
) {
  let lengths = [Int](repeating: 0, count: testCase.count)

  #expect(huffmanCodeLengthRuns(lengths: lengths) == testCase.expected)
}

@Test(
  arguments: [
    (1, [codeLengthRun(5)]),
    (3, [codeLengthRun(5), codeLengthRun(5), codeLengthRun(5)]),
    (4, [codeLengthRun(5), codeLengthRun(16, 0, 2)]),
    (6, [codeLengthRun(5), codeLengthRun(16, 2, 2)]),
    (7, [codeLengthRun(5), codeLengthRun(16, 3, 2)]),
    (8, [codeLengthRun(5), codeLengthRun(16, 3, 2), codeLengthRun(5)]),
    (9, [codeLengthRun(5), codeLengthRun(16, 3, 2), codeLengthRun(5), codeLengthRun(5)]),
    (10, [codeLengthRun(5), codeLengthRun(16, 3, 2), codeLengthRun(16, 0, 2)])
  ] as [(count: Int, expected: [HuffmanCodeLengthRun])])
func dynamicHuffmanHeaderEncodesNonzeroRunBoundaries(
  testCase: (count: Int, expected: [HuffmanCodeLengthRun])
) {
  let lengths = [Int](repeating: 5, count: testCase.count)

  #expect(huffmanCodeLengthRuns(lengths: lengths) == testCase.expected)
}

@Test func dynamicHuffmanHeaderKeepsDifferentLengthRunsSeparate() {
  let lengths = [2, 2, 2, 2, 0, 0, 0, 3, 3, 3, 3]
  let expected = [
    codeLengthRun(2), codeLengthRun(16, 0, 2), codeLengthRun(17, 0, 3),
    codeLengthRun(3), codeLengthRun(16, 0, 2)
  ]

  #expect(huffmanCodeLengthRuns(lengths: lengths) == expected)
}

@Test func dynamicHuffmanHeaderCountsTheEmptyStreamAlphabet() {
  var literalLengths = [Int](repeating: 0, count: 257)
  literalLengths[256] = 1
  let header = DynamicHuffmanHeader(literalLengths: literalLengths, distanceLengths: [1])

  // Four runs: two long zero repeats, followed by two literal code lengths.
  // The code-length tree has two one-bit symbols and needs 18 transmitted entries.
  #expect(header.bitCount == 14 + 18 * 3 + 4 + 2 * 7)
}

@Test(arguments: 0..<4, 0...7)
func dynamicHuffmanHeaderCostMatchesUnpaddedEmission(testCase: Int, initialBitPosition: Int) {
  let literalLengths: [Int]
  let distanceLengths: [Int]
  switch testCase {
  case 0:
    literalLengths = [Int](repeating: 0, count: 256) + [1]
    distanceLengths = [1]
  case 1:
    // Dense alphabets include runs encoded with repeat symbol 16.
    literalLengths = huffmanCodeLengths(frequencies: [Int](repeating: 1, count: 286), maxBits: 15)
    distanceLengths = huffmanCodeLengths(frequencies: [Int](repeating: 1, count: 30), maxBits: 15)
  case 2:
    // Sparse alphabets exercise both short and long zero repeats.
    var literals = [Int](repeating: 0, count: 286)
    for (index, frequency) in [(0, 100), (4, 50), (15, 20), (153, 10), (256, 1), (285, 3)] {
      literals[index] = frequency
    }
    var distances = [Int](repeating: 0, count: 30)
    for index in [0, 4, 29] { distances[index] = 1 }
    literalLengths = huffmanCodeLengths(frequencies: literals, maxBits: 15)
    distanceLengths = huffmanCodeLengths(frequencies: distances, maxBits: 15)
  default:
    // A single run symbol requires a second symbol to complete the header tree.
    // This tests header encoding alone, not a valid literal/length data alphabet.
    literalLengths = [Int](repeating: 0, count: 257)
    distanceLengths = [0]
  }
  let header = DynamicHuffmanHeader(literalLengths: literalLengths, distanceLengths: distanceLengths)
  var writer = BitWriter(minimumCapacity: 0)
  writer.writeBits(0xFF, count: initialBitPosition)
  var output = UniqueArray<UInt8>(capacity: 1_024)

  for emission in 1...2 {
    header.write(to: &writer)
    let drained = output.edit { span in writer.drain(output: &span) }
    #expect(drained)
    let emittedBitCount = output.count * 8 + writer.bitPosition - initialBitPosition
    #expect(emittedBitCount == emission * header.bitCount)
  }
}
