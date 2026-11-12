import Testing
import Zlib
import zlib

func deflaterWindowBits(_ format: ZLib.Format) -> Int32 {
  switch format {
  case .rawDeflate: -MAX_WBITS
  case .zlib: MAX_WBITS
  case .gzip: MAX_WBITS + 16
  }
}

// Drives one input/flush request to completion, retaining its exact unconsumed
// suffix across output retries. outputChunkSize excludes any preexisting prefix.
func driveDeflater(
  _ deflater: inout Deflater, input: [UInt8], flush: Deflater.Flush,
  outputChunkSize: Int, outputPrefix: [UInt8] = []
) throws -> [UInt8] {
  precondition(outputChunkSize > 0)
  let initialInputCount = deflater.totalInputCount
  let initialOutputCount = deflater.totalOutputCount
  var offset = 0
  var encoded: [UInt8] = []
  while true {
    var progress: Deflater.Progress?
    let chunk = try [UInt8](capacity: outputChunkSize + outputPrefix.count) { output in
      for byte in outputPrefix { output.append(byte) }
      progress = try deflater.process(input: input.span.extracting(offset...), output: &output, flush: flush)
    }
    let step = try #require(progress)
    #expect(step.inputConsumed >= 0 && step.inputConsumed <= input.count - offset)
    #expect(step.outputProduced == chunk.count - outputPrefix.count)
    #expect(Array(chunk.prefix(outputPrefix.count)) == outputPrefix)
    offset += step.inputConsumed
    encoded += chunk.dropFirst(outputPrefix.count)
    #expect(deflater.totalInputCount == initialInputCount + offset)
    #expect(deflater.totalOutputCount == initialOutputCount + encoded.count)
    if step.status == .needsOutput {
      try #require(step.inputConsumed > 0 || step.outputProduced > 0)
      continue
    }
    #expect(offset == input.count)
    switch flush {
    case .none: #expect(step.status == .needsInput)
    case .sync: #expect(step.status == .flushed)
    case .finish: #expect(step.status == .finished)
    }
    return encoded
  }
}

func deflateInChunks(
  _ input: [UInt8], format: ZLib.Format, strategy: ZLib.Strategy,
  inputChunkSize: Int, outputChunkSize: Int
) throws -> [UInt8] {
  var deflater = Deflater(format: format, strategy: strategy)
  var encoded: [UInt8] = []
  var offset = 0
  while offset < input.count {
    let end = min(input.count, offset + inputChunkSize)
    encoded += try driveDeflater(
      &deflater, input: Array(input[offset..<end]), flush: .none, outputChunkSize: outputChunkSize)
    offset = end
  }
  encoded += try driveDeflater(&deflater, input: [], flush: .finish, outputChunkSize: outputChunkSize)
  #expect(deflater.isFinished == true)
  #expect(deflater.totalInputCount == input.count)
  #expect(deflater.totalOutputCount == encoded.count)
  return encoded
}

// Z_SYNC_FLUSH output is readable before the enclosing compressed stream ends.
// The extra output byte lets C zlib consume the complete marker after decoding.
func cZlibInflatePrefix(_ input: [UInt8], expectedCount: Int, windowBits: Int32) throws -> [UInt8] {
  var stream = z_stream()
  let initialized = inflateInit2_(
    &stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
  try #require(initialized == Z_OK)
  defer { _ = inflateEnd(&stream) }
  var output = [UInt8](repeating: 0, count: expectedCount + 1)
  let status = input.withUnsafeBytes { inputBuffer in
    output.withUnsafeMutableBytes { outputBuffer in
      stream.next_in = UnsafeMutablePointer(mutating: inputBuffer.bindMemory(to: Bytef.self).baseAddress)
      stream.avail_in = uInt(inputBuffer.count)
      stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
      stream.avail_out = uInt(outputBuffer.count)
      return zlib.inflate(&stream, Z_SYNC_FLUSH)
    }
  }
  try #require(status == Z_OK)
  #expect(stream.avail_in == 0)
  try #require(Int(stream.total_out) == expectedCount)
  return Array(output.prefix(Int(stream.total_out)))
}

func expectInvalidDeflaterState(_ operation: () throws -> Void) {
  do {
    try operation()
    Issue.record("Expected DeflateError.invalidState")
  } catch let error as DeflateError {
    if case .invalidState = error {
      return
    }
    Issue.record("Expected invalidState, received \(error)")
  } catch {
    Issue.record(error)
  }
}
