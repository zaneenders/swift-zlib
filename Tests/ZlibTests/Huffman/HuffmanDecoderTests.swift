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

@Test(arguments: 0...7)
func huffmanDecoderReadsEveryCodeAcrossRootAndSubtables(offset: Int) throws {
  let lengths = Array(1...14) + [15, 15]
  let decoder = try HuffmanDecoder(lengths: lengths, alphabet: .literalLength)
  var codes: [UInt16?] = []
  canonicalHuffmanCodes(lengths: lengths, into: &codes)
  var writer = BitWriter(minimumCapacity: 0)
  writer.writeBits(0, count: offset)
  for symbol in lengths.indices {
    writer.writeHuffmanCode(codes[symbol]!, bitCount: lengths[symbol])
  }
  writer.writeBits(0b10101, count: 5)
  let input = writer.finish()
  var reader = BitReader(input.span.bytes)
  _ = try reader.readBits(offset)

  for symbol in lengths.indices {
    #expect(try decoder.readSymbol(from: &reader) == UInt32(symbol))
  }
  #expect(try reader.readBits(5) == 0b10101)
}

@Test func huffmanDecoderAcceptsAShortCodeWithOneBitRemaining() throws {
  let decoder = try HuffmanDecoder(lengths: Array(1...14) + [15, 15], alphabet: .literalLength)
  let input: [UInt8] = [0]
  var reader = BitReader(input.span.bytes)
  _ = try reader.readBits(7)

  #expect(try decoder.readSymbol(from: &reader) == 0)
  #expect(reader.byteOffset == 1)
  #expect(reader.bitOffset == 0)
}

@Test(arguments: 0..<15)
func huffmanDecoderDoesNotTreatMissingLookaheadAsCodeBits(available: Int) throws {
  let decoder = try HuffmanDecoder(lengths: Array(1...14) + [15, 15], alphabet: .literalLength)
  let input: [UInt8] = []
  let prefix = BufferedBits(value: UInt64.max >> (64 - available), count: available)
  var reader = BitReader(input.span.bytes, bufferedBits: prefix)

  #expect(throws: BitReaderError.unexpectedEndOfInput) {
    _ = try decoder.readSymbol(from: &reader)
  }
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
