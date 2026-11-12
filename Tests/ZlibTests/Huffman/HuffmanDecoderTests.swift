import Testing

@testable import Zlib

@Test(
  arguments: [
    ([], .codeLength),
    ([0, 0], .literalLength),
    ([1], .codeLength),
    ([1, 1, 1], .literalLength),
    ([2, 2], .literalLength),
    ([2], .distance),
    ([1, 1, 1], .distance),
    ([-1, 1], .distance),
    ([16], .literalLength),
    ([8], .codeLength)
  ] as [(lengths: [Int], alphabet: HuffmanDecoder.Alphabet)])
func huffmanDecoderRejectsInvalidTrees(
  testCase: (lengths: [Int], alphabet: HuffmanDecoder.Alphabet)
) {
  #expect(throws: BitReaderError.invalidHuffmanTable) {
    _ = try HuffmanDecoder(lengths: testCase.lengths, alphabet: testCase.alphabet)
  }
}

@Test func huffmanDecoderReadsCanonicalCodesInSymbolOrder() throws {
  let decoder = try HuffmanDecoder(lengths: [2, 1, 3, 3], alphabet: .literalLength)
  // Codes 10, 0, 110, 111, packed starting at the low bit of each byte.
  let input: [UInt8] = [0xD9, 0x01]
  var reader = BitReader(input.span.bytes)

  for symbol: UInt32 in 0...3 {
    #expect(try decoder.readSymbol(from: &reader) == symbol)
  }
  #expect(reader.byteOffset == 1)
  #expect(reader.bitOffset == 1)
}

@Test func huffmanDecoderReadsTheLongestAllowedCode() throws {
  let decoder = try HuffmanDecoder(lengths: Array(1...14) + [15, 15], alphabet: .literalLength)
  let input: [UInt8] = [0xFF, 0x7F]
  var reader = BitReader(input.span.bytes)

  #expect(try decoder.readSymbol(from: &reader) == 15)
  #expect(reader.byteOffset == 1)
  #expect(reader.bitOffset == 7)
}

@Test func huffmanDecoderRejectsAnUnusedOneBitCode() throws {
  let decoder = try HuffmanDecoder(lengths: [0, 1, 0], alphabet: .distance)
  let input: [UInt8] = [0x01]
  var reader = BitReader(input.span.bytes)

  #expect(throws: BitReaderError.invalidHuffmanTable) {
    _ = try decoder.readSymbol(from: &reader)
  }
}

@Test func huffmanDecoderRejectsReadingAnEmptyDistanceAlphabet() throws {
  let decoder = try HuffmanDecoder(lengths: [0], alphabet: .distance)
  let input: [UInt8] = []
  var reader = BitReader(input.span.bytes)

  #expect(throws: BitReaderError.invalidHuffmanTable) {
    _ = try decoder.readSymbol(from: &reader)
  }
}

@Test func huffmanDecoderReportsTruncatedCodes() throws {
  let decoder = try HuffmanDecoder(lengths: Array(1...14) + [15, 15], alphabet: .literalLength)
  let input: [UInt8] = [0xFF]
  var reader = BitReader(input.span.bytes)

  #expect(throws: BitReaderError.unexpectedEndOfInput) {
    _ = try decoder.readSymbol(from: &reader)
  }
}
