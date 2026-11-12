import Testing

@testable import Zlib

enum AutomaticBlockBoundary: CaseIterable, Sendable {
  case continued
  case final
  case sync
}

private struct AutomaticBlockMeasurement {
  let bitCount: Int
  let blockType: UInt8
}

// Measure actual output rather than reimplementing the encoder's cost formula.
// Nonfinal measurements remove only the padding added by finish() for inspection.
private func measureAutomaticBlockCandidate(
  _ input: [UInt8], strategy: ZLib.Strategy, bitPosition: Int, boundary: AutomaticBlockBoundary
) throws -> AutomaticBlockMeasurement {
  var writer = BitWriter(minimumCapacity: input.count + 256)
  writer.writeBits(0, count: bitPosition)
  var finder = LZ77MatchFinder()
  var position = 0
  let isFinal = boundary == .final
  switch strategy {
  case .stored:
    DeflateEncoder.writeStoredBlock(input: input.span, isFinal: isFinal, writer: &writer)
    position = input.count
  case .fixed:
    try DeflateEncoder.writeFixedBlock(
      input: input.span, position: &position, end: input.count, isFinal: isFinal, finder: &finder, writer: &writer)
  case .dynamic:
    try DeflateEncoder.writeDynamicBlock(
      input: input.span, position: &position, end: input.count, isFinal: isFinal, finder: &finder, writer: &writer)
  case .automatic:
    try DeflateEncoder.writeAutomaticBlock(
      input: input.span, position: &position, end: input.count, isFinal: isFinal,
      syncFlush: boundary == .sync, finder: &finder, writer: &writer)
  }
  #expect(position == input.count)
  switch boundary {
  case .continued:
    break
  case .final:
    writer.alignToByte()
  case .sync:
    let empty: [UInt8] = []
    DeflateEncoder.writeStoredBlock(input: empty.span, isFinal: false, writer: &writer)
  }
  let remainder = writer.bitPosition
  let bytes = writer.finish()
  let inspectionPadding = (8 - remainder) % 8
  let bitCount = bytes.count * 8 - inspectionPadding - bitPosition
  let lowTypeBit = (bytes[(bitPosition + 1) / 8] >> ((bitPosition + 1) % 8)) & 1
  let highTypeBit = (bytes[(bitPosition + 2) / 8] >> ((bitPosition + 2) % 8)) & 1
  return AutomaticBlockMeasurement(bitCount: bitCount, blockType: lowTypeBit | (highTypeBit << 1))
}

@Test(arguments: 0...7, AutomaticBlockBoundary.allCases)
func automaticDeflateChoosesTheCheapestActualBlock(bitPosition: Int, boundary: AutomaticBlockBoundary) throws {
  let random = InteropPayload.pseudoRandom.bytes
  let payloads: [[UInt8]] = [
    [], [65], [144], Array("tiny input".utf8), Array(UInt8.min...UInt8.max),
    [UInt8](repeating: 90, count: 64), [UInt8](repeating: 90, count: 4_096),
    Array(random.prefix(257)), Array(random.prefix(4_096)), [UInt8](repeating: 90, count: 65_535)
  ]
  for input in payloads {
    let candidates = try [ZLib.Strategy.stored, .fixed, .dynamic].map {
      try measureAutomaticBlockCandidate(input, strategy: $0, bitPosition: bitPosition, boundary: boundary)
    }
    let minimum = try #require(candidates.map(\.bitCount).min())
    // Candidate order also checks deterministic stored, fixed, dynamic tie-breaking.
    let winner = try #require(candidates.first(where: { $0.bitCount == minimum }))
    let automatic = try measureAutomaticBlockCandidate(
      input, strategy: .automatic, bitPosition: bitPosition, boundary: boundary)

    #expect(automatic.bitCount == minimum, "Input size: \(input.count)")
    #expect(automatic.blockType == winner.blockType, "Input size: \(input.count)")
  }
}

@Test(arguments: [(40, 40, 0), (41, 40, 0), (20, 20, 1), (21, 20, 2)])
func automaticDeflateUsesTheDocumentedTieOrder(fixed: Int, dynamic: Int, expectedType: Int) {
  // An empty stored block at a byte boundary costs 40 bits.
  let costs = DeflateBlockCosts(
    inputCount: 0, fixedBitCount: fixed, dynamicBitCount: dynamic, bitPosition: 0, isFinal: false)
  switch expectedType {
  case 0: #expect(costs.choice == .stored)
  case 1: #expect(costs.choice == .fixed)
  default: #expect(costs.choice == .dynamic)
  }
}

@Test(arguments: [(0, UInt8(1)), (1, UInt8(0)), (2, UInt8(2))])
func automaticDeflateCanSelectEveryBlockType(fixture: Int, expectedType: UInt8) throws {
  let input: [UInt8] =
    switch fixture {
    case 0: Array("ABC".utf8)
    case 1: Array(InteropPayload.pseudoRandom.bytes.prefix(4_096))
    default: [UInt8](repeating: 90, count: 4_096)
    }
  let compressed = try ZLib.deflate(input: input.span, strategy: .automatic)
  #expect((compressed[0] >> 1) & 3 == expectedType)
  let bytes = (0..<compressed.count).map { compressed[$0] }
  #expect(try cZlibInflate(bytes, expectedCount: input.count) == input)
}

@Test(arguments: [ZLib.Format.rawDeflate, .zlib, .gzip])
func automaticDeflateIsTheDefaultForOneShotAndStreamingCompression(format: ZLib.Format) throws {
  let input = Array(String(repeating: "Default automatic compression\n", count: 20).utf8)
  let implicit = try ZLib.deflate(input: input.span, format: format)
  let explicit = try ZLib.deflate(input: input.span, format: format, strategy: .automatic)
  try #require(implicit.count == explicit.count)
  #expect((0..<implicit.count).allSatisfy { implicit[$0] == explicit[$0] })

  var defaultDeflater = Deflater(format: format)
  var automaticDeflater = Deflater(format: format, strategy: .automatic)
  let prefix = Array(input.prefix(input.count / 2))
  let suffix = Array(input.dropFirst(input.count / 2))
  let implicitPrefix = try driveDeflater(&defaultDeflater, input: prefix, flush: .sync, outputChunkSize: 17)
  let explicitPrefix = try driveDeflater(&automaticDeflater, input: prefix, flush: .sync, outputChunkSize: 17)
  let implicitSuffix = try driveDeflater(&defaultDeflater, input: suffix, flush: .finish, outputChunkSize: 17)
  let explicitSuffix = try driveDeflater(&automaticDeflater, input: suffix, flush: .finish, outputChunkSize: 17)
  #expect(implicitPrefix + implicitSuffix == explicitPrefix + explicitSuffix)
}

@Test func automaticDeflateRetainsHistoryAfterAStoredBlockAndSyncFlush() throws {
  let input = Array(InteropPayload.pseudoRandom.bytes.prefix(8_192))
  var deflater = Deflater()
  let flushed = try driveDeflater(&deflater, input: input, flush: .sync, outputChunkSize: 257)
  #expect((flushed[0] >> 1) & 3 == 0)
  #expect(try cZlibInflatePrefix(flushed, expectedCount: input.count, windowBits: -15) == input)
  let continuation = try driveDeflater(&deflater, input: input, flush: .finish, outputChunkSize: 257)

  #expect(continuation.count < input.count / 4)
  #expect(try cZlibInflate(flushed + continuation, expectedCount: input.count * 2) == input + input)
}

@Test(arguments: [ZLib.Format.rawDeflate, .zlib, .gzip])
func automaticDeflateHandlesLargeMixedDataAndStoredBlockHistory(format: ZLib.Format) throws {
  let random = InteropPayload.pseudoRandom.bytes
  let first = Array(random.prefix(65_535))
  let repeated = Array(first.suffix(32_768))
  let input = first + repeated + [UInt8](repeating: 90, count: 65_535) + random.prefix(32_768)
  let compressed = try ZLib.deflate(input: input.span, format: format)
  let bytes = (0..<compressed.count).map { compressed[$0] }
  let bodyOffset: Int
  switch format {
  case .rawDeflate: bodyOffset = 0
  case .zlib: bodyOffset = 2
  case .gzip: bodyOffset = 10
  }
  #expect((bytes[bodyOffset] >> 1) & 3 == 0)
  // The first random block must remain available to matches in the second block.
  #expect(bytes.count < first.count + 32_768 + 8_192)
  #expect(try cZlibInflate(bytes, expectedCount: input.count, windowBits: deflaterWindowBits(format)) == input)

  let streamed = try deflateInChunks(
    input, format: format, strategy: .automatic, inputChunkSize: 4_096, outputChunkSize: 257)
  #expect(try cZlibInflate(streamed, expectedCount: input.count, windowBits: deflaterWindowBits(format)) == input)
}
