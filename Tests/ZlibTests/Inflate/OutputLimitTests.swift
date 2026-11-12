import Testing
import Zlib

@Test(arguments: [ZLib.Strategy.stored, .fixed, .dynamic], [0, 1, 257, 258, 259, 999])
func inflateRejectsOutputBeyondTheLimit(strategy: ZLib.Strategy, limit: Int) throws {
  let input = [UInt8](repeating: 90, count: 1_000)
  let compressed = try ZLib.deflate(input: input.span, strategy: strategy)

  #expect(throws: InflateError.outputLimitExceeded) {
    _ = try ZLib.inflate(input: compressed.span, maximumOutputSize: limit)
  }
  let bytes = (0..<compressed.count).map { compressed[$0] }
  #expect(throws: InflateError.outputLimitExceeded) {
    _ = try inflateInChunks(bytes, inputChunkSize: 1, outputChunkSize: 7, maximumOutputSize: limit)
  }
}

@Test(arguments: [ZLib.Strategy.stored, .fixed, .dynamic])
func inflateAcceptsExactlyTheOutputLimit(strategy: ZLib.Strategy) throws {
  let input = [UInt8](repeating: 90, count: 1_000)
  let compressed = try ZLib.deflate(input: input.span, strategy: strategy)
  let decoded = try ZLib.inflate(input: compressed.span, maximumOutputSize: input.count)
  #expect(decoded.count == input.count)
  #expect(input.indices.allSatisfy { decoded[$0] == input[$0] })
}

@Test(arguments: [ZLib.Strategy.stored, .fixed, .dynamic])
func outputLimitAppliesAcrossBlocksAndChunks(strategy: ZLib.Strategy) throws {
  let input = [UInt8](repeating: 90, count: 65_537)
  let encoded = try ZLib.deflate(input: input.span, strategy: strategy)
  let compressed = (0..<encoded.count).map { encoded[$0] }
  #expect(throws: InflateError.outputLimitExceeded) {
    _ = try inflateInChunks(
      compressed, inputChunkSize: 7, outputChunkSize: 257, maximumOutputSize: input.count - 1)
  }
  #expect(
    try inflateInChunks(
      compressed, inputChunkSize: 7, outputChunkSize: 257, maximumOutputSize: input.count) == input)
}

@Test(arguments: [-1, Int.min])
func inflateRejectsNegativeOutputLimits(limit: Int) {
  #expect(throws: InflateError.invalidOutputLimit) { _ = try Inflater(maximumOutputSize: limit) }
  let empty: [UInt8] = []
  #expect(throws: InflateError.invalidOutputLimit) {
    _ = try ZLib.inflate(input: empty.span, maximumOutputSize: limit)
  }
}

@Test func inflaterRejectsAWholeMatchBeforeEmittingAnyOfIt() throws {
  // One literal Z followed by a length-258, distance-1 match.
  let compressed: [UInt8] = [0x8B, 0x1A, 0x05, 0x00]
  var inflater = try Inflater(maximumOutputSize: 258)
  var output = UniqueArray<UInt8>(minimumCapacity: 300)
  #expect(throws: InflateError.outputLimitExceeded) {
    try output.edit { span in
      _ = try inflater.process(input: compressed.span, output: &span, isFinalInput: true)
    }
  }
  #expect(output.count == 1)
  #expect(inflater.totalOutputCount == 1)
}
