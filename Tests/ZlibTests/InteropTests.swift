import Testing
import Zlib
import zlib

enum InteropPayload: CaseIterable, Sendable {
  case empty
  case singleByte
  case allBytes
  case text
  case repeatedByte
  case multipleBlocks
  case pseudoRandom
  case skewedFrequencies

  var bytes: [UInt8] {
    switch self {
    case .empty:
      return []
    case .singleByte:
      return [0x41]
    case .allBytes:
      return Array(UInt8.min...UInt8.max)
    case .text:
      return Array(String(repeating: "Swift deflate / inflate.\n", count: 1_024).utf8)
    case .repeatedByte:
      return [UInt8](repeating: 0x5A, count: 65_537)
    case .multipleBlocks:
      return (0..<196_605).map { UInt8(truncatingIfNeeded: $0 * 37 + 11) }
    case .pseudoRandom:
      var state: UInt32 = 0xC0FFEE
      return (0..<65_537).map { _ in
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return UInt8(truncatingIfNeeded: state)
      }
    case .skewedFrequencies:
      var frequencies = [1, 1]
      for _ in 0..<18 {
        frequencies.append(frequencies[frequencies.count - 2] + frequencies[frequencies.count - 1])
      }
      return frequencies.enumerated().flatMap { symbol, count in
        [UInt8](repeating: UInt8(symbol), count: count)
      }
    }
  }
}

// A negative windowBits selects raw DEFLATE, matching the Swift API.
private func cZlibDeflate(_ input: [UInt8], level: Int32, strategy: Int32 = Z_FIXED) throws -> [UInt8] {
  var stream = z_stream()
  let initialized = deflateInit2_(
    &stream, level, Z_DEFLATED, -MAX_WBITS, 8, strategy,
    ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)
  )
  try #require(initialized == Z_OK)
  defer { _ = deflateEnd(&stream) }

  var output = [UInt8](repeating: 0, count: Int(deflateBound(&stream, uLong(input.count))))
  let status = input.withUnsafeBytes { inputBuffer in
    output.withUnsafeMutableBytes { outputBuffer in
      stream.next_in = UnsafeMutablePointer(mutating: inputBuffer.bindMemory(to: Bytef.self).baseAddress)
      stream.avail_in = uInt(inputBuffer.count)
      stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
      stream.avail_out = uInt(outputBuffer.count)
      return zlib.deflate(&stream, Z_FINISH)
    }
  }
  try #require(status == Z_STREAM_END)
  #expect(stream.avail_in == 0)
  return Array(output.prefix(Int(stream.total_out)))
}

private func cZlibInflate(_ input: [UInt8], expectedCount: Int) throws -> [UInt8] {
  var stream = z_stream()
  let initialized = inflateInit2_(
    &stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)
  )
  try #require(initialized == Z_OK)
  defer { _ = inflateEnd(&stream) }

  // Leave room for the decoder to detect the end marker, even for empty output.
  var output = [UInt8](repeating: 0, count: expectedCount + 1)
  let status = input.withUnsafeBytes { inputBuffer in
    output.withUnsafeMutableBytes { outputBuffer in
      stream.next_in = UnsafeMutablePointer(mutating: inputBuffer.bindMemory(to: Bytef.self).baseAddress)
      stream.avail_in = uInt(inputBuffer.count)
      stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
      stream.avail_out = uInt(outputBuffer.count)
      return zlib.inflate(&stream, Z_FINISH)
    }
  }
  try #require(status == Z_STREAM_END)
  #expect(stream.avail_in == 0)
  try #require(Int(stream.total_out) == expectedCount)
  return Array(output.prefix(Int(stream.total_out)))
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
