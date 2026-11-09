import Testing
import Zlib

private func expectDeflateBytes(
  _ output: borrowing UniqueArray<UInt8>,
  _ expected: [UInt8]
) throws {
  let bytes = output.span
  try #require(bytes.count == expected.count)
  let allBytesMatch = expected.indices.allSatisfy { bytes[$0] == expected[$0] }
  #expect(allBytesMatch)
}

@Test(
  arguments: [
    ([], [0x01, 0x00, 0x00, 0xFF, 0xFF]),
    ([0x41], [0x01, 0x01, 0x00, 0xFE, 0xFF, 0x41]),
    ([0x41, 0x42, 0x43], [0x01, 0x03, 0x00, 0xFC, 0xFF, 0x41, 0x42, 0x43]),
    ([0x00, 0x80, 0xFF], [0x01, 0x03, 0x00, 0xFC, 0xFF, 0x00, 0x80, 0xFF])
  ] as [(input: [UInt8], expected: [UInt8])])
func deflateEncodesExactStoredBlockFixtures(
  testCase: (input: [UInt8], expected: [UInt8])
) throws {
  let output = try ZLib.deflate(input: testCase.input.span)

  try expectDeflateBytes(output, testCase.expected)
}

@Test(
  arguments: [
    (255, [0xFF, 0x00, 0x00, 0xFF]),
    (256, [0x00, 0x01, 0xFF, 0xFE]),
    (257, [0x01, 0x01, 0xFE, 0xFE]),
    (32_767, [0xFF, 0x7F, 0x00, 0x80]),
    (32_768, [0x00, 0x80, 0xFF, 0x7F]),
    (32_769, [0x01, 0x80, 0xFE, 0x7F]),
    (65_534, [0xFE, 0xFF, 0x01, 0x00]),
    (65_535, [0xFF, 0xFF, 0x00, 0x00])
  ] as [(length: Int, fields: [UInt8])])
func deflateHandlesStoredLengthBoundaries(
  testCase: (length: Int, fields: [UInt8])
) throws {
  let input = (0..<testCase.length).map { UInt8(truncatingIfNeeded: $0) }

  let output = try ZLib.deflate(input: input.span)

  let bytes = output.span
  let header: [UInt8] = [0x01] + testCase.fields
  try #require(bytes.count == header.count + input.count)
  for index in header.indices {
    #expect(bytes[index] == header[index], "Header byte at index \(index)")
  }
  let payloadMatches = input.indices.allSatisfy {
    bytes[header.count + $0] == input[$0]
  }
  #expect(payloadMatches)
}

@Test(arguments: [0, 1, 8, 256, 1_024, 65_535, 65_536, 65_537, 131_070, 131_071, 196_605])
func deflateRoundTripsThroughInflate(length: Int) throws {
  let input = (0..<length).map { UInt8(truncatingIfNeeded: $0 * 37 + 11) }

  let encoded = try ZLib.deflate(input: input.span)
  let decoded = try ZLib.inflate(input: encoded.span)

  try expectDeflateBytes(decoded, input)
}

@Test(
  arguments: [
    (0, [0]),
    (65_535, [65_535]),
    (65_536, [65_535, 1]),
    (65_537, [65_535, 2]),
    (131_069, [65_535, 65_534]),
    (131_070, [65_535, 65_535]),
    (131_071, [65_535, 65_535, 1]),
    (196_605, [65_535, 65_535, 65_535])
  ] as [(length: Int, blockLengths: [Int])])
func deflateSplitsInputIntoStoredBlocks(testCase: (length: Int, blockLengths: [Int])) throws {
  let input = (0..<testCase.length).map { UInt8(truncatingIfNeeded: $0 * 37 + 11) }

  let output = try ZLib.deflate(input: input.span)

  let bytes = output.span
  try #require(bytes.count == input.count + 5 * testCase.blockLengths.count)
  var encodedOffset = 0
  var inputOffset = 0
  for (blockIndex, blockLength) in testCase.blockLengths.enumerated() {
    let isFinal = blockIndex == testCase.blockLengths.count - 1
    #expect(bytes[encodedOffset] == (isFinal ? 0x01 : 0x00))

    let length = UInt16(bytes[encodedOffset + 1]) | (UInt16(bytes[encodedOffset + 2]) << 8)
    let complement = UInt16(bytes[encodedOffset + 3]) | (UInt16(bytes[encodedOffset + 4]) << 8)
    #expect(Int(length) == blockLength)
    #expect(length ^ complement == UInt16.max)

    let payloadMatches = (0..<blockLength).allSatisfy {
      bytes[encodedOffset + 5 + $0] == input[inputOffset + $0]
    }
    #expect(payloadMatches, "Payload in block \(blockIndex)")
    encodedOffset += 5 + blockLength
    inputOffset += blockLength
  }
  #expect(encodedOffset == bytes.count)
  #expect(inputOffset == input.count)
}

@Test(arguments: [7, 65_536])
func deflateReadsOnlyTheSuppliedSpanWithinAnAllocation(allocationSize: Int) throws {
  var allocation = [UInt8](repeating: 0xA5, count: allocationSize)
  allocation[2] = 0x41
  allocation[3] = 0x42
  allocation[4] = 0x43
  let input = allocation.span.extracting(2..<5)

  let output = try ZLib.deflate(input: input)

  try expectDeflateBytes(output, [0x01, 0x03, 0x00, 0xFC, 0xFF, 0x41, 0x42, 0x43])
}

@Test func deflateReturnsMutableOutputThatOutlivesInput() throws {
  var output: UniqueArray<UInt8>
  do {
    let input: [UInt8] = [0x41]
    output = try ZLib.deflate(input: input.span)
  }
  try expectDeflateBytes(output, [0x01, 0x01, 0x00, 0xFE, 0xFF, 0x41])

  output[5] = 0x42
  output.append(0x43)

  try expectDeflateBytes(output, [0x01, 0x01, 0x00, 0xFE, 0xFF, 0x42, 0x43])
}
