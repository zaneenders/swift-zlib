import Testing

@testable import Zlib

private let testCodeLengths: [Int] = {
  var lengths = [Int](repeating: 0, count: 19)
  for symbol in [0, 1, 2, 3, 15, 16, 17, 18] {
    lengths[symbol] = 3
  }
  return lengths
}()

private func run(_ symbol: Int, _ extraBits: UInt8 = 0, _ extraBitCount: Int = 0) -> HuffmanCodeLengthRun {
  .init(symbol: symbol, extraBits: extraBits, extraBitCount: extraBitCount)
}

// Write the table representation explicitly, so malformed headers do not depend
// on the encoder's validation or its choice of repeat symbols.
private func writeTestDynamicHeader(
  to writer: inout BitWriter,
  literalCount: Int = 257,
  distanceCount: Int = 1,
  codeLengths: [Int] = testCodeLengths,
  runs: [HuffmanCodeLengthRun] = []
) {
  writer.writeBits(0b101, count: 3)
  writer.writeBits(UInt8(literalCount - 257), count: 5)
  writer.writeBits(UInt8(distanceCount - 1), count: 5)
  writer.writeBits(15, count: 4)
  for symbol in huffmanCodeLengthOrder {
    writer.writeBits(UInt8(codeLengths[symbol]), count: 3)
  }
  if !runs.isEmpty {
    let codes = canonicalHuffmanCodes(lengths: codeLengths)
    for run in runs {
      writer.writeHuffmanCode(codes[run.symbol]!, bitCount: codeLengths[run.symbol])
      writer.writeBits(run.extraBits, count: run.extraBitCount)
    }
  }
}

@Test(arguments: [false, true])
func inflateDynamicAcceptsAnEmptyDistanceAlphabet(includeLiteral: Bool) throws {
  var lengths = [Int](repeating: 0, count: 257)
  lengths[256] = 1
  if includeLiteral {
    lengths[65] = 1
  }
  var writer = BitWriter(minimumCapacity: 0)
  writer.writeBits(0b101, count: 3)
  writer.writeDynamicHuffmanHeader(literalLengths: lengths, distanceLengths: [0])
  if includeLiteral {
    writer.writeHuffmanCode(0, bitCount: 1)
  }
  writer.writeHuffmanCode(includeLiteral ? 1 : 0, bitCount: 1)
  let encoded = writer.finish()

  let output = try ZLib.inflate(input: encoded.span)

  #expect(output.count == (includeLiteral ? 1 : 0))
  if includeLiteral {
    #expect(output[0] == 65)
  }
}

@Test(arguments: [16, 17])
func inflateDynamicExpandsZeroRepeats(symbol: Int) throws {
  let runs: [HuffmanCodeLengthRun]
  if symbol == 16 {
    runs = [run(0)] + Array(repeating: run(16, 3, 2), count: 42)
      + [run(16, 0, 2), run(1), run(0)]
  } else {
    runs = Array(repeating: run(17, 7, 3), count: 25) + [run(17, 3, 3), run(1), run(0)]
  }
  var writer = BitWriter(minimumCapacity: 0)
  writeTestDynamicHeader(to: &writer, runs: runs)
  writer.writeHuffmanCode(0, bitCount: 1)
  let encoded = writer.finish()

  let output = try ZLib.inflate(input: encoded.span)

  #expect(output.count == 0)
}

@Test func inflateDynamicExpandsARepeatAcrossTheAlphabetBoundary() throws {
  // Four two-bit literal codes (253...256), followed by four two-bit distances.
  // Symbol 16 spans the literal/length and distance alphabets.
  let runs = [run(18, 127, 7), run(18, 104, 7), run(2), run(16, 3, 2), run(2)]
  var writer = BitWriter(minimumCapacity: 0)
  writeTestDynamicHeader(to: &writer, distanceCount: 4, runs: runs)
  writer.writeHuffmanCode(0b11, bitCount: 2)
  let encoded = writer.finish()

  let output = try ZLib.inflate(input: encoded.span)

  #expect(output.count == 0)
}

@Test func inflateDynamicExpandsOverlappingMatches() throws {
  var lengths = [Int](repeating: 0, count: 286)
  lengths[90] = 1
  lengths[256] = 2
  lengths[285] = 2
  var writer = BitWriter(minimumCapacity: 0)
  writer.writeBits(0b101, count: 3)
  writer.writeDynamicHuffmanHeader(literalLengths: lengths, distanceLengths: [1])
  writer.writeHuffmanCode(0, bitCount: 1)  // Literal Z.
  writer.writeHuffmanCode(0b11, bitCount: 2)  // Length 258.
  writer.writeHuffmanCode(0, bitCount: 1)  // Distance 1.
  writer.writeHuffmanCode(0b10, bitCount: 2)  // End marker.
  let encoded = writer.finish()

  let output = try ZLib.inflate(input: encoded.span)

  #expect(output.count == 259)
  let bytes = output.span
  #expect((0..<bytes.count).allSatisfy { bytes[$0] == 90 })
}

@Test func inflateDynamicKeepsHistoryForTheMaximumDistance() throws {
  let history = (0..<32_768).map { UInt8(truncatingIfNeeded: $0) }
  var writer = BitWriter(minimumCapacity: history.count)
  writer.writeBits(0, count: 3)
  writer.alignToByte()
  writer.writeUInt16LittleEndian(32_768)
  writer.writeUInt16LittleEndian(~UInt16(32_768))
  for byte in history {
    writer.writeBits(byte, count: 8)
  }
  var lengths = [Int](repeating: 0, count: 286)
  lengths[256] = 1
  lengths[285] = 1
  var distances = [Int](repeating: 0, count: 30)
  distances[29] = 1
  writer.writeBits(0b101, count: 3)
  writer.writeDynamicHuffmanHeader(literalLengths: lengths, distanceLengths: distances)
  writer.writeHuffmanCode(1, bitCount: 1)  // Length 258.
  writer.writeHuffmanCode(0, bitCount: 1)  // Distance symbol 29.
  writer.writeBits(0xFF, count: 8)
  writer.writeBits(0x1F, count: 5)  // Extra value 8,191 gives distance 32,768.
  writer.writeHuffmanCode(0, bitCount: 1)
  let encoded = writer.finish()

  let output = try ZLib.inflate(input: encoded.span)

  let expected = history + history.prefix(258)
  let bytes = output.span
  try #require(bytes.count == expected.count)
  #expect(expected.indices.allSatisfy { bytes[$0] == expected[$0] })
}

@Test func inflateReadsUnalignedFixedDynamicAndStoredBlocks() throws {
  var writer = BitWriter(minimumCapacity: 0)
  writer.writeBits(0b010, count: 3)
  try writer.writeFixedLiteralLengthSymbol(65)
  try writer.writeFixedLiteralLengthSymbol(256)
  var lengths = [Int](repeating: 0, count: 257)
  lengths[66] = 1
  lengths[256] = 1
  writer.writeBits(0b100, count: 3)
  writer.writeDynamicHuffmanHeader(literalLengths: lengths, distanceLengths: [0])
  writer.writeHuffmanCode(0, bitCount: 1)
  writer.writeHuffmanCode(1, bitCount: 1)
  writer.writeBits(0b001, count: 3)
  writer.alignToByte()
  writer.writeUInt16LittleEndian(1)
  writer.writeUInt16LittleEndian(~UInt16(1))
  writer.writeBits(67, count: 8)
  let encoded = writer.finish()

  let output = try ZLib.inflate(input: encoded.span)

  try #require(output.count == 3)
  #expect(output[0] == 65)
  #expect(output[1] == 66)
  #expect(output[2] == 67)
}

@Test(arguments: [(287, 1), (288, 1), (257, 31), (257, 32)])
func inflateDynamicRejectsInvalidTableSizes(literalCount: Int, distanceCount: Int) {
  var writer = BitWriter(minimumCapacity: 0)
  writeTestDynamicHeader(to: &writer, literalCount: literalCount, distanceCount: distanceCount)
  let encoded = writer.finish()

  #expect(throws: BitReaderError.invalid) {
    _ = try ZLib.inflate(input: encoded.span)
  }
}

@Test(arguments: [
  [Int](repeating: 0, count: 19),
  [1] + [Int](repeating: 0, count: 18),
  [1, 1, 1] + [Int](repeating: 0, count: 16),
  [2, 2] + [Int](repeating: 0, count: 17)
])
func inflateDynamicRejectsInvalidCodeLengthTrees(codeLengths: [Int]) {
  var writer = BitWriter(minimumCapacity: 0)
  writeTestDynamicHeader(to: &writer, codeLengths: codeLengths)
  let encoded = writer.finish()

  #expect(throws: BitReaderError.invalid) {
    _ = try ZLib.inflate(input: encoded.span)
  }
}

@Test(arguments: [
  [run(16, 0, 2)],
  Array(repeating: run(17, 7, 3), count: 26),
  [run(18, 127, 7), run(18, 127, 7)],
  [run(2)] + Array(repeating: run(16, 3, 2), count: 43)
])
func inflateDynamicRejectsInvalidLengthRepeats(runs: [HuffmanCodeLengthRun]) {
  var writer = BitWriter(minimumCapacity: 0)
  writeTestDynamicHeader(to: &writer, runs: runs)
  let encoded = writer.finish()

  #expect(throws: BitReaderError.invalid) {
    _ = try ZLib.inflate(input: encoded.span)
  }
}

@Test(arguments: [0, 1, 2, 3, 4])
func inflateDynamicRejectsInvalidDataTrees(testCase: Int) {
  var lengths = [Int](repeating: 0, count: 257)
  lengths[65] = 1
  lengths[256] = 1
  var distances = [1]
  switch testCase {
  case 0: lengths[256] = 0  // Missing end marker.
  case 1: lengths[66] = 1  // Oversubscribed literal tree.
  case 2:
    lengths[65] = 2
    lengths[256] = 2  // Incomplete literal tree.
  case 3: distances = [1, 1, 1]  // Oversubscribed distance tree.
  default: distances = [2]  // Incomplete distance tree.
  }
  var writer = BitWriter(minimumCapacity: 0)
  writer.writeBits(0b101, count: 3)
  writer.writeDynamicHuffmanHeader(literalLengths: lengths, distanceLengths: distances)
  let encoded = writer.finish()

  #expect(throws: BitReaderError.invalid) {
    _ = try ZLib.inflate(input: encoded.span)
  }
}

@Test(arguments: [false, true])
func inflateDynamicRejectsMatchesWithoutAvailableHistory(emptyDistanceTable: Bool) {
  var lengths = [Int](repeating: 0, count: 258)
  lengths[256] = 1
  lengths[257] = 1
  var writer = BitWriter(minimumCapacity: 0)
  writer.writeBits(0b101, count: 3)
  writer.writeDynamicHuffmanHeader(literalLengths: lengths, distanceLengths: [emptyDistanceTable ? 0 : 1])
  writer.writeHuffmanCode(1, bitCount: 1)
  writer.writeHuffmanCode(0, bitCount: 1)
  writer.writeHuffmanCode(0, bitCount: 1)
  let encoded = writer.finish()

  #expect(throws: BitReaderError.invalid) {
    _ = try ZLib.inflate(input: encoded.span)
  }
}

@Test func inflateRejectsEveryTruncatedDynamicStreamPrefix() throws {
  let input = Array("AABABC".utf8)
  let encoded = try ZLib.deflate(input: input.span, strategy: .dynamic)
  let bytes = encoded.span

  for prefixLength in 0..<bytes.count {
    let prefix = bytes.extracting(0..<prefixLength)
    #expect(throws: BitReaderError.unexpectedEndOfInput) {
      _ = try ZLib.inflate(input: prefix)
    }
  }
}
