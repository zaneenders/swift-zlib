import Testing
import Zlib

@Test(arguments: [ZLib.Format.rawDeflate, .zlib, .gzip], [ZLib.Strategy.stored, .fixed, .dynamic, .automatic])
func compressionEffortsInteroperateWithCZlib(format: ZLib.Format, strategy: ZLib.Strategy) throws {
  for effort in ZLib.Effort.allCases {
    for payload in InteropPayload.allCases {
      let input = payload.bytes
      let compressed = try ZLib.deflate(input: input.span, format: format, strategy: strategy, effort: effort)
      let bytes = (0..<compressed.count).map { compressed[$0] }
      #expect(try cZlibInflate(bytes, expectedCount: input.count, windowBits: deflaterWindowBits(format)) == input)
    }
  }
}

@Test(arguments: [ZLib.Format.rawDeflate, .zlib, .gzip], [ZLib.Strategy.stored, .fixed, .dynamic, .automatic])
func compressionEffortDefaultsPreserveBalancedOutput(format: ZLib.Format, strategy: ZLib.Strategy) throws {
  let input = effortCollisionInput(recentCandidates: 8).bytes
  let implicit = try ZLib.deflate(input: input.span, format: format, strategy: strategy)
  let balanced = try ZLib.deflate(input: input.span, format: format, strategy: strategy, effort: .balanced)
  #expect(implicit.count == balanced.count)
  #expect((0..<implicit.count).allSatisfy { implicit[$0] == balanced[$0] })

  var defaultDeflater = Deflater(format: format, strategy: strategy)
  var balancedDeflater = Deflater(format: format, strategy: strategy, effort: .balanced)
  let actual = try driveDeflater(&defaultDeflater, input: input, flush: .finish, outputChunkSize: 17)
  let expected = try driveDeflater(&balancedDeflater, input: input, flush: .finish, outputChunkSize: 257)
  #expect(actual == expected)
}

@Test(arguments: [ZLib.Format.rawDeflate, .zlib, .gzip], [ZLib.Strategy.stored, .fixed, .dynamic, .automatic])
func compressionEffortReachesEveryFormatAndStrategy(format: ZLib.Format, strategy: ZLib.Strategy) throws {
  let input = effortCollisionInput(recentCandidates: 8).bytes
  let fast = try ZLib.deflate(input: input.span, format: format, strategy: strategy, effort: .fast)
  let balanced = try ZLib.deflate(input: input.span, format: format, strategy: strategy, effort: .balanced)
  let identical = fast.count == balanced.count && (0..<fast.count).allSatisfy { fast[$0] == balanced[$0] }
  #expect(identical == (strategy == .stored))

  for effort in ZLib.Effort.allCases {
    var deflater = Deflater(format: format, strategy: strategy, effort: effort)
    let encoded = try driveDeflater(&deflater, input: input, flush: .finish, outputChunkSize: 257)
    // This fixture fits a single block, so one-shot and streaming parses agree.
    let oneShot = try ZLib.deflate(input: input.span, format: format, strategy: strategy, effort: effort)
    #expect(encoded == (0..<oneShot.count).map { oneShot[$0] })
  }
}

@Test(arguments: [ZLib.Format.rawDeflate, .zlib, .gzip], [ZLib.Strategy.stored, .fixed, .dynamic, .automatic])
func compressionEffortSurvivesSyncBackpressureAndReset(format: ZLib.Format, strategy: ZLib.Strategy) throws {
  let input = Array(InteropPayload.pseudoRandom.bytes.prefix(8_192))
  for effort in ZLib.Effort.allCases {
    var deflater = Deflater(format: format, strategy: strategy, effort: effort)
    let first = try driveDeflater(&deflater, input: input, flush: .sync, outputChunkSize: 17)
    let second = try driveDeflater(&deflater, input: input, flush: .finish, outputChunkSize: 17)
    #expect(
      try cZlibInflate(first + second, expectedCount: input.count * 2, windowBits: deflaterWindowBits(format))
        == input + input)
    if strategy != .stored { #expect(second.count < input.count / 4) }
    deflater.reset()
    #expect(deflater.effort == effort)
    #expect(deflater.totalInputCount == 0 && deflater.totalOutputCount == 0)
    let next = try driveDeflater(&deflater, input: input, flush: .finish, outputChunkSize: 17)
    var fresh = Deflater(format: format, strategy: strategy, effort: effort)
    let expected = try driveDeflater(&fresh, input: input, flush: .finish, outputChunkSize: 257)
    #expect(next == expected)
    #expect(try cZlibInflate(next, expectedCount: input.count, windowBits: deflaterWindowBits(format)) == input)
  }
}
