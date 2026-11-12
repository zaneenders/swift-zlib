import Testing
import zlib

// A negative windowBits selects raw DEFLATE; MAX_WBITS + 16 selects gzip.
func cZlibDeflate(
  _ input: [UInt8], level: Int32, strategy: Int32 = Z_FIXED, windowBits: Int32 = -MAX_WBITS
) throws -> [UInt8] {
  var stream = z_stream()
  let initialized = deflateInit2_(
    &stream, level, Z_DEFLATED, windowBits, 8, strategy,
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

func cZlibInflate(_ input: [UInt8], expectedCount: Int, windowBits: Int32 = -MAX_WBITS) throws -> [UInt8] {
  var stream = z_stream()
  let initialized = inflateInit2_(
    &stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)
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
