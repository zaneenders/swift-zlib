import Testing
import Zlib
import zlib

@Test(arguments: [InteropPayload.text, .repeatedByte, .multipleBlocks], [ZLib.Strategy.fixed, .dynamic])
func lz77CompressionReducesRepetitivePayloads(payload: InteropPayload, strategy: ZLib.Strategy) throws {
  let input = payload.bytes
  let encoded = try ZLib.deflate(input: input.span, strategy: strategy)
  #expect(encoded.count < input.count / 20)
  let compressed = (0..<encoded.count).map { encoded[$0] }
  #expect(try cZlibInflate(compressed, expectedCount: input.count) == input)
}

@Test(arguments: InteropPayload.allCases, [ZLib.Strategy.stored, .fixed, .dynamic])
func swiftDeflateOutputIsDecodedByCZlib(payload: InteropPayload, strategy: ZLib.Strategy) throws {
  let input = payload.bytes
  let encoded = try ZLib.deflate(input: input.span, strategy: strategy)
  let encodedBytes = encoded.span
  let compressed = (0..<encodedBytes.count).map { encodedBytes[$0] }

  let decoded = try cZlibInflate(compressed, expectedCount: input.count)

  #expect(decoded == input)
}

// Level zero produces stored blocks. Z_FIXED at the default level permits
// stored and fixed blocks, including LZ77 matches, without dynamic Huffman tables.
@Test(arguments: InteropPayload.allCases, [Z_NO_COMPRESSION, Z_DEFAULT_COMPRESSION])
func swiftInflateDecodesCZlibOutput(payload: InteropPayload, level: Int32) throws {
  let input = payload.bytes
  let encoded = try cZlibDeflate(input, level: level)

  let decoded = try ZLib.inflate(input: encoded.span)

  let bytes = decoded.span
  try #require(bytes.count == input.count)
  let allBytesMatch = input.indices.allSatisfy { bytes[$0] == input[$0] }
  #expect(allBytesMatch)
}

@Test(arguments: InteropPayload.allCases, [Int32(1), Z_DEFAULT_COMPRESSION, Z_BEST_COMPRESSION])
func swiftInflateDecodesCZlibDefaultStrategy(payload: InteropPayload, level: Int32) throws {
  let input = payload.bytes
  let encoded = try cZlibDeflate(input, level: level, strategy: Z_DEFAULT_STRATEGY)
  if payload == .text {
    // Ensure the independent encoder exercises dynamic tables and LZ77 matches.
    try #require(encoded[0] & 0b110 == 0b100)
    #expect(encoded.count < input.count / 10)
  }

  let decoded = try ZLib.inflate(input: encoded.span)

  let bytes = decoded.span
  try #require(bytes.count == input.count)
  #expect(input.indices.allSatisfy { bytes[$0] == input[$0] })
}
