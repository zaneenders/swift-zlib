import Testing

@testable import Zlib

private func expectCZlibDecodesMatch(length: Int, distance: Int) throws {
  var writer = BitWriter(minimumCapacity: distance + 16)
  writer.writeBits(0b011, count: 3)
  var expected = (0..<distance).map { UInt8(truncatingIfNeeded: $0 * 37 + 11) }
  for byte in expected {
    try writer.writeFixedLiteralLengthSymbol(UInt32(byte))
  }
  let lengthCode = MatchCode.length(length)
  let distanceCode = MatchCode.distance(distance)
  try writer.writeFixedLiteralLengthSymbol(UInt32(lengthCode.symbol))
  writer.writeExtraBits(lengthCode.extraBits, count: lengthCode.extraBitCount)
  writer.writeHuffmanCode(UInt16(distanceCode.symbol), bitCount: 5)
  writer.writeExtraBits(distanceCode.extraBits, count: distanceCode.extraBitCount)
  try writer.writeFixedLiteralLengthSymbol(256)
  let encoded = writer.finish()
  let compressed = (0..<encoded.count).map { encoded[$0] }
  for _ in 0..<length {
    expected.append(expected[expected.count - distance])
  }
  #expect(try cZlibInflate(compressed, expectedCount: expected.count) == expected)
  #expect(try inflateInChunks(compressed, inputChunkSize: 1, outputChunkSize: 17) == expected)
}

@Test(arguments: 3...258)
func matchLengthCodesInteroperateWithCZlib(length: Int) throws {
  try expectCZlibDecodesMatch(length: length, distance: 1)
}

@Test(arguments: [
  1, 2, 3, 4, 5, 6, 7, 8, 9, 12, 13, 16, 17, 24, 25, 32,
  33, 48, 49, 64, 65, 96, 97, 128, 129, 192, 193, 256,
  257, 384, 385, 512, 513, 768, 769, 1_024, 1_025, 1_536,
  1_537, 2_048, 2_049, 3_072, 3_073, 4_096, 4_097, 6_144,
  6_145, 8_192, 8_193, 12_288, 12_289, 16_384, 16_385,
  24_576, 24_577, 32_768
])
func matchDistanceBoundariesInteroperateWithCZlib(distance: Int) throws {
  try expectCZlibDecodesMatch(length: 258, distance: distance)
}
