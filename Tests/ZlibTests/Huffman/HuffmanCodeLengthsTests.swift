import Testing

@testable import Zlib

@Test(
  arguments: [
    ([], []),
    ([0, 0, 0], [0, 0, 0]),
    ([7], [1]),
    ([0, 7, 0], [0, 1, 0]),
    ([2, 1], [1, 1]),
    ([2, 1, 1], [1, 2, 2]),
    ([1, 1, 1], [2, 2, 1]),
    ([0, 2, 1, 0, 1], [0, 1, 2, 0, 2]),
    ([5, 9, 12, 13, 16, 45], [4, 4, 3, 3, 3, 1])
  ] as [(frequencies: [Int], expected: [Int])])
func huffmanCodeLengthsMatchKnownTrees(
  testCase: (frequencies: [Int], expected: [Int])
) {
  var lengths: [Int] = []
  huffmanCodeLengths(frequencies: testCase.frequencies, into: &lengths)

  #expect(lengths == testCase.expected)
}

@Test func huffmanCodeLengthsForAABIncludeTheEndMarker() {
  var frequencies = [Int](repeating: 0, count: 286)
  frequencies[65] = 2
  frequencies[66] = 1
  frequencies[256] = 1

  var lengths: [Int] = []
  huffmanCodeLengths(frequencies: frequencies, into: &lengths)

  var expected = [Int](repeating: 0, count: 286)
  expected[65] = 1
  expected[66] = 2
  expected[256] = 2
  #expect(lengths == expected)
}

@Test func huffmanCodeLengthsGiveALoneEndMarkerOneBit() {
  var frequencies = [Int](repeating: 0, count: 286)
  frequencies[256] = 1

  var lengths: [Int] = []
  huffmanCodeLengths(frequencies: frequencies, into: &lengths)

  var expected = [Int](repeating: 0, count: 286)
  expected[256] = 1
  #expect(lengths == expected)
}

@Test func huffmanCodeLengthsCoverEveryLiteralAndTheEndMarker() {
  var frequencies = [Int](repeating: 0, count: 286)
  for symbol in 0...256 {
    frequencies[symbol] = 1
  }

  var lengths: [Int] = []
  huffmanCodeLengths(frequencies: frequencies, into: &lengths)

  #expect(lengths.count == 286)
  #expect(lengths.prefix(257).filter { $0 == 8 }.count == 255)
  #expect(lengths.prefix(257).filter { $0 == 9 }.count == 2)
  #expect(lengths.dropFirst(257).allSatisfy { $0 == 0 })
}

@Test(
  arguments: [
    ([], 15, []),
    ([0, 0, 0], 7, [0, 0, 0]),
    ([0, 7, 0], 1, [0, 1, 0]),
    ([1, 1, 2, 3], 2, [2, 2, 2, 2]),
    ([1, 1, 2, 3, 5, 8], 3, [3, 3, 3, 3, 2, 2]),
    ([0, 1, 1, 2, 3, 0], 2, [0, 2, 2, 2, 2, 0]),
    ([5, 9, 12, 13, 16, 45], 15, [4, 4, 3, 3, 3, 1])
  ] as [(frequencies: [Int], maxBits: Int, expected: [Int])])
func huffmanCodeLengthsRespectBitLengthLimits(
  testCase: (frequencies: [Int], maxBits: Int, expected: [Int])
) {
  var lengths: [Int] = []
  huffmanCodeLengths(frequencies: testCase.frequencies, maxBits: testCase.maxBits, into: &lengths)

  #expect(lengths == testCase.expected)
}

@Test(arguments: [false, true])
func huffmanCodeLengthsReplaceReusedOutput(limited: Bool) {
  var lengths = [99, 99, 99, 99]
  for (frequencies, expected) in [
    ([5, 9, 12, 13, 16, 45], [4, 4, 3, 3, 3, 1]),
    ([0, 7, 0], [0, 1, 0]),
    ([0, 0], [0, 0]),
    ([], [])
  ] {
    if limited {
      huffmanCodeLengths(frequencies: frequencies, maxBits: 7, into: &lengths)
    } else {
      huffmanCodeLengths(frequencies: frequencies, into: &lengths)
    }
    #expect(lengths == expected)
  }
}

@Test(arguments: [7, 15])
func huffmanCodeLengthLimitsPreserveACompleteTreeForSkewedFrequencies(maxBits: Int) throws {
  var frequencies = [0, 1, 1]
  for _ in 0..<18 {
    frequencies.append(frequencies[frequencies.count - 2] + frequencies[frequencies.count - 1])
  }
  frequencies.append(0)
  var original: [Int] = []
  huffmanCodeLengths(frequencies: frequencies, into: &original)
  try #require((original.max() ?? 0) > maxBits)

  var lengths: [Int] = []
  huffmanCodeLengths(frequencies: frequencies, maxBits: maxBits, into: &lengths)

  #expect(lengths.count == frequencies.count)
  #expect(lengths.first == 0)
  #expect(lengths.last == 0)
  let used = lengths.dropFirst().dropLast()
  #expect(used.allSatisfy { (1...maxBits).contains($0) })
  // Kraft equality independently checks that the lengths describe a full tree.
  #expect(used.reduce(0) { $0 + (1 << (maxBits - $1)) } == (1 << maxBits))
  var codes: [UInt16?] = []
  canonicalHuffmanCodes(lengths: lengths, into: &codes)
  #expect(codes.compactMap { $0 }.count == 20)
}
