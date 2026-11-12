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
