import Testing
import Zlib

// A reset stream must be byte-for-byte equivalent to a freshly initialized
// compressor, and independently decodable with C zlib (including its trailer).
private func expectIndependentStreamAfterReset(_ deflater: inout Deflater, input: [UInt8]) throws {
  let format = deflater.format
  let strategy = deflater.strategy
  deflater.reset()
  #expect(deflater.format == format)
  #expect(deflater.strategy == strategy)
  #expect(deflater.isFinished == false)
  #expect(deflater.totalInputCount == 0)
  #expect(deflater.totalOutputCount == 0)

  let encoded = try driveDeflater(&deflater, input: input, flush: .finish, outputChunkSize: 17)
  var fresh = Deflater(format: format, strategy: strategy)
  let expected = try driveDeflater(&fresh, input: input, flush: .finish, outputChunkSize: 4_096)
  #expect(encoded == expected)
  #expect(deflater.isFinished == true)
  #expect(try cZlibInflate(encoded, expectedCount: input.count, windowBits: deflaterWindowBits(format)) == input)
}

@Test(arguments: [ZLib.Format.rawDeflate, .zlib, .gzip], [ZLib.Strategy.stored, .fixed, .dynamic, .automatic])
func streamingDeflaterResetSupportsRepeatedIndependentStreams(format: ZLib.Format, strategy: ZLib.Strategy) throws {
  let input = (0..<65_536).map { UInt8(truncatingIfNeeded: $0 * 37 + 11) }
  var deflater = Deflater(format: format, strategy: strategy)
  // Reset before first use, after a multiblock stream, and around an empty stream.
  for next in [input, Array(input.suffix(4_096)), [], Array("After an empty stream".utf8)] {
    try expectIndependentStreamAfterReset(&deflater, input: next)
  }
}

@Test(arguments: [ZLib.Format.rawDeflate, .zlib, .gzip], [ZLib.Strategy.stored, .fixed, .dynamic, .automatic])
func streamingDeflaterResetDiscardsBufferedInputAndHistory(format: ZLib.Format, strategy: ZLib.Strategy) throws {
  for (length, flush) in [(19, Deflater.Flush.none), (65_535, .none), (65_535, .sync)] {
    let input = (0..<length).map { UInt8(truncatingIfNeeded: $0 * 37 + 11) }
    var deflater = Deflater(format: format, strategy: strategy)
    _ = try driveDeflater(&deflater, input: input, flush: flush, outputChunkSize: 4_096)
    #expect(deflater.isFinished == false)
    #expect(deflater.totalInputCount == input.count)

    // Reuse old bytes to expose references into history from the abandoned stream.
    try expectIndependentStreamAfterReset(&deflater, input: Array(input.suffix(257)))
  }
}

@Test(arguments: [ZLib.Format.rawDeflate, .zlib, .gzip], [ZLib.Strategy.stored, .fixed, .dynamic, .automatic])
func streamingDeflaterResetDiscardsPendingFlushOutput(format: ZLib.Format, strategy: ZLib.Strategy) throws {
  let input = Array("Abandon a partially emitted stream and its pending trailer".utf8)
  for flush in [Deflater.Flush.sync, .finish] {
    for capacity in [0, 1] {
      var deflater = Deflater(format: format, strategy: strategy)
      // Drain the header to reach body/trailer backpressure in every format.
      _ = try driveDeflater(&deflater, input: [], flush: .none, outputChunkSize: 17)
      var progress: Deflater.Progress?
      let emitted = try [UInt8](capacity: capacity) { output in
        progress = try deflater.process(input: input.span, output: &output, flush: flush)
      }
      let initial = try #require(progress)
      #expect(initial.status == .needsOutput)
      #expect(initial.inputConsumed == input.count)
      #expect(emitted.count == capacity)
      try expectIndependentStreamAfterReset(&deflater, input: Array("Replacement stream".utf8))
    }
  }
}

@Test(arguments: [ZLib.Format.rawDeflate, .zlib, .gzip], [ZLib.Strategy.stored, .fixed, .dynamic, .automatic])
func streamingDeflaterResetCancelsAFlushWithUnconsumedInput(format: ZLib.Format, strategy: ZLib.Strategy) throws {
  let input = [UInt8](repeating: 0x5A, count: 65_536)
  var deflater = Deflater(format: format, strategy: strategy)
  _ = try driveDeflater(&deflater, input: [], flush: .none, outputChunkSize: 17)
  var progress: Deflater.Progress?
  _ = try [UInt8](capacity: 1) { output in
    progress = try deflater.process(input: input.span, output: &output, flush: .finish)
  }
  let initial = try #require(progress)
  #expect(initial.status == .needsOutput)
  #expect(initial.inputConsumed == 65_535)
  try expectIndependentStreamAfterReset(&deflater, input: Array("No remaining flush request".utf8))
}

@Test(arguments: [ZLib.Format.rawDeflate, .zlib, .gzip], [ZLib.Strategy.stored, .fixed, .dynamic, .automatic])
func streamingDeflaterResetRecoversAfterAnError(format: ZLib.Format, strategy: ZLib.Strategy) throws {
  let input = Array("An unfinished request".utf8)
  var deflater = Deflater(format: format, strategy: strategy)
  var output = OutputSpan<UInt8>()
  let initial = try deflater.process(input: input.span, output: &output, flush: .finish)
  try #require(initial.status == .needsOutput)
  let remaining = Array(input.dropFirst(initial.inputConsumed))
  expectInvalidDeflaterState {
    _ = try deflater.process(input: remaining.span, output: &output, flush: .sync)
  }
  expectInvalidDeflaterState {
    _ = try deflater.process(input: remaining.span, output: &output, flush: .finish)
  }
  try expectIndependentStreamAfterReset(&deflater, input: Array("Recovered after reset".utf8))
}
