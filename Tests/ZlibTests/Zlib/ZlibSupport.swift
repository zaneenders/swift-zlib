import Testing
import Zlib
import zlib

func zlibFixtureHeader(cinfo: UInt8 = 7, method: UInt8 = 8, dictionary: Bool = false, level: UInt8 = 0) -> [UInt8] {
  let cmf = (cinfo << 4) | method
  var flags = (level << 6) | (dictionary ? 0x20 : 0)
  let remainder = (UInt16(cmf) * 256 + UInt16(flags)) % 31
  flags += UInt8((31 - remainder) % 31)
  return [cmf, flags]
}

func zlibFixtureTrailer(_ payload: [UInt8]) -> [UInt8] {
  let checksum = payload.withUnsafeBufferPointer { buffer in
    UInt32(zlib.adler32(1, buffer.baseAddress, uInt(buffer.count)))
  }
  return [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: checksum >> $0) }
}

func inflateZlibInChunks(
  _ input: [UInt8], inputChunkSize: Int, outputChunkSize: Int, maximumOutputSize: Int = .max
) throws -> [UInt8] {
  var inflater = try Inflater(format: .zlib, maximumOutputSize: maximumOutputSize)
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
