import Testing
import Zlib
import zlib

func gzipFixtureCRC32(_ input: [UInt8]) -> UInt32 {
  input.withUnsafeBufferPointer { buffer in
    UInt32(zlib.crc32(0, buffer.baseAddress, uInt(buffer.count)))
  }
}

func gzipFixtureLittleEndian(_ value: UInt32) -> [UInt8] {
  (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
}

// Optional metadata includes non-ASCII bytes unless emptyMetadata is requested.
// C zlib independently computes the header checksum, body, and trailer.
func gzipFixtureWithOptionalHeader(
  _ payload: [UInt8], flags: UInt8 = 0x1F, emptyMetadata: Bool = false
) throws -> [UInt8] {
  let member = try cZlibDeflate(payload, level: Z_DEFAULT_COMPRESSION, windowBits: MAX_WBITS + 16)
  var header: [UInt8] = [0x1F, 0x8B, 8, flags, 0x78, 0x56, 0x34, 0x12, 0, 3]
  if flags & 0x04 != 0 {
    header += emptyMetadata ? [0, 0] : [4, 0, 0x41, 0x42, 0, 0]  // XLEN and an empty AB subfield.
  }
  if flags & 0x08 != 0 {
    header += emptyMetadata ? [0] : [0xE9, 0x2E, 0x74, 0x78, 0x74, 0]  // Original name.
  }
  if flags & 0x10 != 0 {
    header += emptyMetadata ? [0] : [0xFF, 0x41, 0]  // Comment.
  }
  if flags & 0x02 != 0 {
    let checksum = gzipFixtureCRC32(header)
    header += [UInt8(truncatingIfNeeded: checksum), UInt8(truncatingIfNeeded: checksum >> 8)]
  }
  return header + member.dropFirst(10)
}

func inflateGzipInChunks(
  _ input: [UInt8], inputChunkSize: Int, outputChunkSize: Int, maximumOutputSize: Int = .max
) throws -> [UInt8] {
  var inflater = try Inflater(format: .gzip, maximumOutputSize: maximumOutputSize)
  var offset = 0
  var decoded: [UInt8] = []
  while !inflater.isFinished {
    let end = min(input.count, offset + inputChunkSize)
    var progress: Inflater.Progress?
    let chunk = try [UInt8](capacity: outputChunkSize) { output in
      progress = try inflater.process(
        input: input.span.extracting(offset..<end), output: &output, isFinalInput: end == input.count)
    }
    let step = try #require(progress)
    #expect(step.inputConsumed <= end - offset)
    #expect(step.outputProduced == chunk.count)
    try #require(step.inputConsumed > 0 || step.outputProduced > 0 || step.status == .finished)
    offset += step.inputConsumed
    decoded += chunk
    #expect(inflater.totalOutputCount == decoded.count)
    if step.status == .needsInput {
      #expect(offset == end)
    }
  }
  #expect(offset == input.count)
  return decoded
}
