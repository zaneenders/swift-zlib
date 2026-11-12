import Testing
import Zlib

@Test(arguments: [ZLib.Strategy.stored, .fixed, .dynamic], [(1, 1), (1, 17), (2, 1), (7, 257), (4_096, 13)])
func inflaterResumesAcrossInputAndOutputChunks(strategy: ZLib.Strategy, chunks: (Int, Int)) throws {
  let input = Array(String(repeating: "ABCABC!ZZZZZZZ\n", count: 100).utf8)
  let encoded = try ZLib.deflate(input: input.span, strategy: strategy)
  let compressed = (0..<encoded.count).map { encoded[$0] }

  let decoded = try inflateInChunks(compressed, inputChunkSize: chunks.0, outputChunkSize: chunks.1)

  #expect(decoded == input)
}

@Test(arguments: [ZLib.Strategy.stored, .fixed, .dynamic])
func inflaterCanFinishEmptyStreamsWithoutOutputStorage(strategy: ZLib.Strategy) throws {
  let input: [UInt8] = []
  let encoded = try ZLib.deflate(input: input.span, strategy: strategy)
  var inflater = try Inflater(maximumOutputSize: 0)
  var output = OutputSpan<UInt8>()

  let progress = try inflater.process(input: encoded.span, output: &output, isFinalInput: true)

  #expect(progress.status == .finished)
  #expect(progress.inputConsumed == encoded.count)
  #expect(progress.outputProduced == 0)
}

@Test func inflaterWaitsForOutputAndPreservesTrailingInput() throws {
  let compressed: [UInt8] = [0x73, 0x74, 0x72, 0x06, 0x00, 0xDE, 0xAD]
  var inflater = try Inflater()
  var emptyOutput = OutputSpan<UInt8>()
  let first = try inflater.process(input: compressed.span, output: &emptyOutput, isFinalInput: true)
  #expect(first.status == .needsOutput)
  #expect(first.outputProduced == 0)

  var last: Inflater.Progress?
  let output = try [UInt8](capacity: 3) { span in
    span.append(0x58)
    last = try inflater.process(
      input: compressed.span.extracting(first.inputConsumed...), output: &span, isFinalInput: true)
  }
  #expect(output == Array("XAB".utf8))
  let second = try #require(last)
  #expect(second.outputProduced == 2)
  #expect(second.status == .needsOutput)

  let tail = try [UInt8](capacity: 1) { span in
    last = try inflater.process(
      input: compressed.span.extracting((first.inputConsumed + second.inputConsumed)...),
      output: &span, isFinalInput: true)
  }
  let third = try #require(last)
  #expect(tail == [0x43])
  #expect(third.status == .finished)
  #expect(first.inputConsumed + second.inputConsumed + third.inputConsumed == 5)
  #expect(inflater.totalOutputCount == 3)
}

@Test func inflaterDistinguishesTemporaryInputExhaustionFromTruncation() throws {
  var inflater = try Inflater()
  var output = OutputSpan<UInt8>()
  let empty: [UInt8] = []

  #expect(try inflater.process(input: empty.span, output: &output).status == .needsInput)
  #expect(throws: InflateError.unexpectedEndOfInput) {
    try inflater.process(input: empty.span, output: &output, isFinalInput: true)
  }
  #expect(throws: InflateError.invalidState) {
    try inflater.process(input: empty.span, output: &output)
  }
}

@Test func inflaterRetainsHistoryAcrossSeveralWindowWraps() throws {
  let input = (0..<100_000).map { UInt8(truncatingIfNeeded: $0 * 37 + 11) }
  let encoded = try ZLib.deflate(input: input.span, strategy: .dynamic)
  let compressed = (0..<encoded.count).map { encoded[$0] }
  #expect(try inflateInChunks(compressed, inputChunkSize: 3, outputChunkSize: 257) == input)
}
