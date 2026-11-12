import Testing

@testable import Zlib

@Test(
  arguments: [
    ([], []),
    ([0, 0, 0], [nil, nil, nil]),
    ([1], [0]),
    ([0, 1, 0], [nil, 0, nil]),
    ([1, 1], [0, 1]),
    ([1, 2, 2], [0, 0b10, 0b11]),
    ([2, 2, 1], [0b10, 0b11, 0]),
    ([0, 2, 1, 0, 2], [nil, 0b10, 0, nil, 0b11]),
    ([2, 1, 3, 3], [0b10, 0, 0b110, 0b111]),
    ([3, 3, 3, 3, 3, 2, 4, 4], [0b010, 0b011, 0b100, 0b101, 0b110, 0b00, 0b1110, 0b1111]),
    ([15], [0]),
    (
      Array(1...14) + [15, 15],
      [0, 2, 6, 14, 30, 62, 126, 254, 510, 1022, 2046, 4094, 8190, 16382, 32766, 32767]
    )
  ] as [(lengths: [Int], expected: [UInt16?])])
func canonicalHuffmanCodesMatchKnownAssignments(
  testCase: (lengths: [Int], expected: [UInt16?])
) {
  let codes = canonicalHuffmanCodes(lengths: testCase.lengths)

  #expect(codes == testCase.expected)
}

@Test func canonicalHuffmanCodesForAABIncludeTheEndMarker() {
  var frequencies = [Int](repeating: 0, count: 286)
  frequencies[65] = 2
  frequencies[66] = 1
  frequencies[256] = 1

  let lengths = huffmanCodeLengths(frequencies: frequencies)
  let codes = canonicalHuffmanCodes(lengths: lengths)

  var expected = [UInt16?](repeating: nil, count: 286)
  expected[65] = 0
  expected[66] = 0b10
  expected[256] = 0b11
  #expect(codes == expected)
}

@Test func canonicalHuffmanCodesGiveALoneEndMarkerCodeZero() {
  var frequencies = [Int](repeating: 0, count: 286)
  frequencies[256] = 1

  let lengths = huffmanCodeLengths(frequencies: frequencies)
  let codes = canonicalHuffmanCodes(lengths: lengths)

  var expected = [UInt16?](repeating: nil, count: 286)
  expected[256] = 0
  #expect(codes == expected)
}
