import Testing
import Zlib

@Test(arguments: [ZLib.Format.rawDeflate, .zlib, .gzip], [ZLib.Strategy.stored, .fixed, .dynamic])
func streamingDeflaterInteroperatesWithCZlibAcrossChunkSizes(format: ZLib.Format, strategy: ZLib.Strategy) throws {
  let input = Array(String(repeating: "Streaming compression: ABCABC!ZZZZZZZ\n", count: 3).utf8)
  for (inputChunk, outputChunk) in [(1, 1), (7, 17), (1_024, 4_096)] {
    let encoded = try deflateInChunks(
      input, format: format, strategy: strategy, inputChunkSize: inputChunk, outputChunkSize: outputChunk)
    #expect(try cZlibInflate(encoded, expectedCount: input.count, windowBits: deflaterWindowBits(format)) == input)
  }
}

@Test(arguments: [ZLib.Format.rawDeflate, .zlib, .gzip], [ZLib.Strategy.stored, .fixed, .dynamic])
func streamingDeflaterFinishesEmptyAndExactBlockBoundaries(format: ZLib.Format, strategy: ZLib.Strategy) throws {
  for length in [0, 65_535, 65_536, 131_070] {
    let input = (0..<length).map { UInt8(truncatingIfNeeded: $0 * 37 + 11) }
    var deflater = Deflater(format: format, strategy: strategy)
    let encoded = try driveDeflater(&deflater, input: input, flush: .finish, outputChunkSize: 1_024)

    #expect(deflater.isFinished == true)
    #expect(deflater.totalInputCount == input.count)
    #expect(deflater.totalOutputCount == encoded.count)
    #expect(try cZlibInflate(encoded, expectedCount: input.count, windowBits: deflaterWindowBits(format)) == input)
  }
}

@Test(arguments: [ZLib.Format.rawDeflate, .zlib, .gzip], [ZLib.Strategy.stored, .fixed, .dynamic])
func streamingDeflaterHandlesZeroOutputCapacity(format: ZLib.Format, strategy: ZLib.Strategy) throws {
  let input = Array("Resubmit the remaining input after backpressure".utf8)
  var deflater = Deflater(format: format, strategy: strategy)
  var output = OutputSpan<UInt8>()
  let initial = try deflater.process(input: input.span, output: &output, flush: .finish)

  #expect(initial.status == .needsOutput)
  #expect(initial.outputProduced == 0)
  try #require(initial.inputConsumed >= 0 && initial.inputConsumed <= input.count)
  #expect(deflater.totalInputCount == initial.inputConsumed)
  #expect(deflater.totalOutputCount == 0)
  let encoded = try driveDeflater(
    &deflater, input: Array(input.dropFirst(initial.inputConsumed)), flush: .finish, outputChunkSize: 1)

  #expect(deflater.totalInputCount == input.count)
  #expect(try cZlibInflate(encoded, expectedCount: input.count, windowBits: deflaterWindowBits(format)) == input)
}

@Test(arguments: [ZLib.Format.rawDeflate, .zlib, .gzip])
func streamingDeflaterCountsExcludePreexistingOutput(format: ZLib.Format) throws {
  let input = Array("Caller-owned output has an existing prefix".utf8)
  var deflater = Deflater(format: format, strategy: .dynamic)
  let encoded = try driveDeflater(
    &deflater, input: input, flush: .finish, outputChunkSize: 1, outputPrefix: [0xDE, 0xAD])

  #expect(deflater.totalInputCount == input.count)
  #expect(deflater.totalOutputCount == encoded.count)
  #expect(try cZlibInflate(encoded, expectedCount: input.count, windowBits: deflaterWindowBits(format)) == input)
}

@Test(arguments: [ZLib.Format.rawDeflate, .zlib, .gzip], [ZLib.Strategy.stored, .fixed, .dynamic])
func streamingDeflaterSyncIsReadableBeforeFinishAndRetryOutputIsStable(format: ZLib.Format, strategy: ZLib.Strategy)
  throws
{
  for prefix in [[], Array("The sync-flushed prefix is already readable. ".utf8)] {
    let suffix = Array("The stream continues after the flush.".utf8)
    var reference = Deflater(format: format, strategy: strategy)
    let referencePrefix = try driveDeflater(
      &reference, input: prefix, flush: .sync, outputChunkSize: 4_096)
    let referenceSuffix = try driveDeflater(
      &reference, input: suffix, flush: .finish, outputChunkSize: 4_096)

    var deflater = Deflater(format: format, strategy: strategy)
    let flushed = try driveDeflater(&deflater, input: prefix, flush: .sync, outputChunkSize: 1)
    #expect(deflater.isFinished == false)
    #expect(flushed == referencePrefix)
    #expect(
      try cZlibInflatePrefix(flushed, expectedCount: prefix.count, windowBits: deflaterWindowBits(format)) == prefix)
    let finished = try driveDeflater(&deflater, input: suffix, flush: .finish, outputChunkSize: 1)
    #expect(finished == referenceSuffix)
    let encoded = flushed + finished
    let expected = prefix + suffix
    #expect(
      try cZlibInflate(encoded, expectedCount: expected.count, windowBits: deflaterWindowBits(format)) == expected)
  }
}

@Test(arguments: [ZLib.Format.rawDeflate, .zlib, .gzip], [ZLib.Strategy.fixed, .dynamic])
func streamingDeflaterRetainsMatchHistoryAcrossSync(format: ZLib.Format, strategy: ZLib.Strategy) throws {
  let input = Array(InteropPayload.pseudoRandom.bytes.prefix(8_192))
  var deflater = Deflater(format: format, strategy: strategy)
  let buffered = try driveDeflater(
    &deflater, input: Array(input.prefix(4_096)), flush: .none, outputChunkSize: 257)
  let flushed = try driveDeflater(
    &deflater, input: Array(input.dropFirst(4_096)), flush: .sync, outputChunkSize: 257)
  #expect(
    try cZlibInflatePrefix(buffered + flushed, expectedCount: input.count, windowBits: deflaterWindowBits(format))
      == input)
  let continuation = try driveDeflater(&deflater, input: input, flush: .finish, outputChunkSize: 257)

  // The random data has little redundancy within itself. A compact second copy
  // demonstrates that sync flush preserved matches into the previous input.
  #expect(continuation.count < input.count / 4)
  let encoded = buffered + flushed + continuation
  #expect(
    try cZlibInflate(encoded, expectedCount: input.count * 2, windowBits: deflaterWindowBits(format)) == input + input)
}

@Test(arguments: [ZLib.Strategy.fixed, .dynamic])
func streamingDeflaterRetainsHistoryAcrossTheBlockBoundary(strategy: ZLib.Strategy) throws {
  let first = Array(InteropPayload.pseudoRandom.bytes.prefix(65_535))
  let repeated = Array(first.suffix(32_768))
  let independentlyEncoded = try ZLib.deflate(input: first.span, strategy: strategy)
  var deflater = Deflater(strategy: strategy)
  let initial = try driveDeflater(&deflater, input: first, flush: .none, outputChunkSize: 4_096)
  let final = try driveDeflater(&deflater, input: repeated, flush: .finish, outputChunkSize: 4_096)
  let encoded = initial + final

  #expect(encoded.count < independentlyEncoded.count + repeated.count / 4)
  #expect(try cZlibInflate(encoded, expectedCount: first.count + repeated.count) == first + repeated)
}

@Test(arguments: [false, true])
func streamingDeflaterRejectsChangedPendingFlushRequests(changeFlush: Bool) throws {
  let input = Array("A pending finish request".utf8)
  var deflater = Deflater(strategy: .stored)
  var output = OutputSpan<UInt8>()
  let initial = try deflater.process(input: input.span, output: &output, flush: .finish)
  try #require(initial.status == .needsOutput)
  let remaining = Array(input.dropFirst(initial.inputConsumed))
  let retry = changeFlush ? remaining : remaining + [0xFF]
  expectInvalidDeflaterState {
    _ = try deflater.process(input: retry.span, output: &output, flush: changeFlush ? .sync : .finish)
  }
  let empty: [UInt8] = []
  expectInvalidDeflaterState {
    _ = try deflater.process(input: empty.span, output: &output, flush: .finish)
  }
}

@Test(arguments: [ZLib.Format.rawDeflate, .zlib, .gzip])
func streamingDeflaterFinishedEmptyCallsAreIdempotentAndNewInputFails(format: ZLib.Format) throws {
  let input = Array("finished".utf8)
  var deflater = Deflater(format: format, strategy: .dynamic)
  let encoded = try driveDeflater(&deflater, input: input, flush: .finish, outputChunkSize: 17)
  let empty: [UInt8] = []
  var output = OutputSpan<UInt8>()
  for flush in [Deflater.Flush.none, .sync, .finish] {
    let repeated = try deflater.process(input: empty.span, output: &output, flush: flush)
    #expect(repeated.status == .finished)
    #expect(repeated.inputConsumed == 0 && repeated.outputProduced == 0)
    #expect(deflater.totalInputCount == input.count)
    #expect(deflater.totalOutputCount == encoded.count)
  }
  expectInvalidDeflaterState {
    _ = try deflater.process(input: input.span, output: &output)
  }
  expectInvalidDeflaterState {
    _ = try deflater.process(input: empty.span, output: &output)
  }
}

@Test(arguments: [ZLib.Format.rawDeflate, .zlib, .gzip])
func streamingDeflaterEmptyInputWithoutFlushCanLaterFinish(format: ZLib.Format) throws {
  var deflater = Deflater(format: format, strategy: .stored)
  let initial = try driveDeflater(&deflater, input: [], flush: .none, outputChunkSize: 1)
  #expect(deflater.isFinished == false)
  let final = try driveDeflater(&deflater, input: [], flush: .finish, outputChunkSize: 1)
  let encoded = initial + final

  #expect(deflater.totalInputCount == 0)
  #expect(try cZlibInflate(encoded, expectedCount: 0, windowBits: deflaterWindowBits(format)) == [])
}

@Test(arguments: [ZLib.Format.rawDeflate, .zlib, .gzip], [ZLib.Strategy.stored, .fixed, .dynamic])
func streamingDeflaterFinishesAfterAnExactlyFullNonfinalBlock(format: ZLib.Format, strategy: ZLib.Strategy) throws {
  let input = (0..<65_535).map { UInt8(truncatingIfNeeded: $0 * 37 + 11) }
  var deflater = Deflater(format: format, strategy: strategy)
  let initial = try driveDeflater(&deflater, input: input, flush: .none, outputChunkSize: 4_096)
  #expect(deflater.isFinished == false)
  #expect(deflater.totalInputCount == input.count)
  let final = try driveDeflater(&deflater, input: [], flush: .finish, outputChunkSize: 1)
  let encoded = initial + final

  #expect(try cZlibInflate(encoded, expectedCount: input.count, windowBits: deflaterWindowBits(format)) == input)
}

@Test(arguments: [ZLib.Format.rawDeflate, .zlib, .gzip], [ZLib.Strategy.stored, .fixed, .dynamic])
func streamingDeflaterSupportsRepeatedEmptySyncRequests(format: ZLib.Format, strategy: ZLib.Strategy) throws {
  var deflater = Deflater(format: format, strategy: strategy)
  var encoded: [UInt8] = []
  var expected: [UInt8] = []
  for round in 0..<4 {
    if round == 2 {
      let input = Array("Input between repeated empty flushes".utf8)
      encoded += try driveDeflater(&deflater, input: input, flush: .none, outputChunkSize: 1)
      expected += input
    }
    encoded += try driveDeflater(&deflater, input: [], flush: .sync, outputChunkSize: 1)
    #expect(deflater.isFinished == false)
    #expect(
      try cZlibInflatePrefix(encoded, expectedCount: expected.count, windowBits: deflaterWindowBits(format)) == expected
    )
  }
  encoded += try driveDeflater(&deflater, input: [], flush: .finish, outputChunkSize: 1)

  #expect(try cZlibInflate(encoded, expectedCount: expected.count, windowBits: deflaterWindowBits(format)) == expected)
}

@Test(arguments: [ZLib.Format.rawDeflate, .zlib, .gzip], [ZLib.Strategy.stored, .fixed, .dynamic])
func streamingDeflaterAcceptsAtMostOneBlockWithoutOutputSpace(format: ZLib.Format, strategy: ZLib.Strategy) throws {
  let input = (0..<(65_535 * 3)).map { UInt8(truncatingIfNeeded: $0 * 37 + 11) }
  var deflater = Deflater(format: format, strategy: strategy)
  // Drain any container header so every format starts with the same body state.
  let header = try driveDeflater(&deflater, input: [], flush: .none, outputChunkSize: 17)
  var output = OutputSpan<UInt8>()
  let initial = try deflater.process(input: input.span, output: &output, flush: .finish)
  try #require(initial.status == .needsOutput)
  try #require(initial.inputConsumed >= 0 && initial.inputConsumed <= 65_535)
  #expect(initial.outputProduced == 0)
  let remaining = Array(input.dropFirst(initial.inputConsumed))
  let blocked = try deflater.process(input: remaining.span, output: &output, flush: .finish)
  #expect(blocked.status == .needsOutput)
  #expect(blocked.inputConsumed == 0 && blocked.outputProduced == 0)
  #expect(deflater.totalInputCount == initial.inputConsumed)
  #expect(deflater.totalOutputCount == header.count)
  let body = try driveDeflater(&deflater, input: remaining, flush: .finish, outputChunkSize: 4_096)
  let encoded = header + body

  #expect(deflater.totalInputCount == input.count)
  #expect(try cZlibInflate(encoded, expectedCount: input.count, windowBits: deflaterWindowBits(format)) == input)
}
