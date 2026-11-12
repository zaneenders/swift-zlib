import Testing
import Zlib
import zlib

@Test(arguments: InteropPayload.allCases, [ZLib.Strategy.stored, .fixed, .dynamic, .automatic])
func swiftGzipOutputIsDecodedByCZlib(payload: InteropPayload, strategy: ZLib.Strategy) throws {
  let input = payload.bytes
  let encoded = try ZLib.deflate(input: input.span, format: .gzip, strategy: strategy)
  let compressed = (0..<encoded.count).map { encoded[$0] }

  #expect(try cZlibInflate(compressed, expectedCount: input.count, windowBits: MAX_WBITS + 16) == input)
}

@Test(arguments: [InteropPayload.empty, .text, .pseudoRandom, .multipleBlocks], [Int32(0), 1, 6, 9])
func swiftGzipInflateDecodesCZlibOutput(payload: InteropPayload, level: Int32) throws {
  let input = payload.bytes
  let encoded = try cZlibDeflate(
    input, level: level, strategy: Z_DEFAULT_STRATEGY, windowBits: MAX_WBITS + 16)
  let decoded = try ZLib.inflate(input: encoded.span, format: .gzip)

  try #require(decoded.count == input.count)
  #expect(input.indices.allSatisfy { decoded[$0] == input[$0] })
}

@Test(arguments: [ZLib.Strategy.stored, .fixed, .dynamic, .automatic])
func gzipEncodingIsDeterministic(strategy: ZLib.Strategy) throws {
  let input = Array("A reproducible gzip stream".utf8)
  let first = try ZLib.deflate(input: input.span, format: .gzip, strategy: strategy)
  let second = try ZLib.deflate(input: input.span, format: .gzip, strategy: strategy)

  try #require(first.count == second.count)
  #expect((0..<first.count).allSatisfy { first[$0] == second[$0] })
  #expect(first[0] == 0x1F && first[1] == 0x8B && first[2] == 8)
}

@Test func gzipAcceptsOptionalHeadersAndTheirChecksum() throws {
  let input = Array(String(repeating: "Optional gzip metadata\n", count: 20).utf8)
  let encoded = try gzipFixtureWithOptionalHeader(input)
  #expect(try cZlibInflate(encoded, expectedCount: input.count, windowBits: MAX_WBITS + 16) == input)

  let decoded = try ZLib.inflate(input: encoded.span, format: .gzip)
  try #require(decoded.count == input.count)
  #expect(input.indices.allSatisfy { decoded[$0] == input[$0] })
  #expect(try inflateGzipInChunks(encoded, inputChunkSize: 1, outputChunkSize: 1) == input)
}

@Test(arguments: UInt8(0)...UInt8(31), [false, true])
func gzipAcceptsEveryHeaderFlagCombination(flags: UInt8, emptyMetadata: Bool) throws {
  let input = Array("Every optional gzip header combination".utf8)
  let encoded = try gzipFixtureWithOptionalHeader(input, flags: flags, emptyMetadata: emptyMetadata)

  #expect(try cZlibInflate(encoded, expectedCount: input.count, windowBits: MAX_WBITS + 16) == input)
  #expect(try inflateGzipInChunks(encoded, inputChunkSize: 1, outputChunkSize: 1) == input)
}

@Test(arguments: [
  (0, UInt8(0), InflateError.invalidGzipHeader),
  (1, UInt8(0), InflateError.invalidGzipHeader),
  (2, UInt8(0), InflateError.unsupportedCompressionMethod),
  (3, UInt8(0x20), InflateError.invalidGzipHeader),
  (3, UInt8(0x40), InflateError.invalidGzipHeader),
  (3, UInt8(0x80), InflateError.invalidGzipHeader)
])
func gzipRejectsInvalidHeaders(offset: Int, value: UInt8, expectedError: InflateError) throws {
  var encoded = try cZlibDeflate([], level: Z_DEFAULT_COMPRESSION, windowBits: MAX_WBITS + 16)
  encoded[offset] = value

  #expect(throws: expectedError) {
    _ = try ZLib.inflate(input: encoded.span, format: .gzip)
  }
}

@Test func gzipRejectsAnIncorrectHeaderChecksum() throws {
  var encoded = try gzipFixtureWithOptionalHeader(Array("header checksum".utf8))
  encoded[4] ^= 1  // Change MTIME without updating FHCRC.

  #expect(throws: InflateError.headerChecksumMismatch) {
    _ = try ZLib.inflate(input: encoded.span, format: .gzip)
  }
}

@Test(arguments: [(8, InflateError.checksumMismatch), (4, InflateError.sizeMismatch)])
func gzipRejectsIncorrectTrailers(distanceFromEnd: Int, expectedError: InflateError) throws {
  let input = Array("CRC32 and ISIZE are checked".utf8)
  var encoded = try cZlibDeflate(input, level: Z_DEFAULT_COMPRESSION, windowBits: MAX_WBITS + 16)
  encoded[encoded.count - distanceFromEnd] ^= 1

  #expect(throws: expectedError) {
    _ = try ZLib.inflate(input: encoded.span, format: .gzip)
  }
  #expect(throws: expectedError) {
    _ = try inflateGzipInChunks(encoded, inputChunkSize: 1, outputChunkSize: 1)
  }
}

@Test func gzipRejectsEveryTruncatedPrefixIncludingOptionalHeadersAndTrailer() throws {
  let encoded = try gzipFixtureWithOptionalHeader(Array("truncated gzip".utf8))
  for count in 0..<encoded.count {
    let prefix = encoded.span.extracting(..<count)
    #expect(throws: InflateError.unexpectedEndOfInput) {
      _ = try ZLib.inflate(input: prefix, format: .gzip)
    }
  }
}

@Test(arguments: [ZLib.Strategy.stored, .fixed, .dynamic, .automatic])
func gzipDecodesConcatenatedMembersIncludingEmptyMembers(strategy: ZLib.Strategy) throws {
  let first = Array("first member".utf8)
  let second = Array("second member".utf8)
  let empty = try cZlibDeflate([], level: Z_DEFAULT_COMPRESSION, windowBits: MAX_WBITS + 16)
  let a = try ZLib.deflate(input: first.span, format: .gzip, strategy: strategy)
  let b = try cZlibDeflate(second, level: Z_DEFAULT_COMPRESSION, windowBits: MAX_WBITS + 16)
  let encoded = empty + (0..<a.count).map { a[$0] } + empty + b + empty

  let decoded = try ZLib.inflate(input: encoded.span, format: .gzip)
  let expected = first + second
  try #require(decoded.count == expected.count)
  #expect(expected.indices.allSatisfy { decoded[$0] == expected[$0] })
  #expect(try inflateGzipInChunks(encoded, inputChunkSize: 1, outputChunkSize: 1) == expected)
}

@Test func gzipOutputLimitAppliesAcrossMemberBoundaries() throws {
  let input = [UInt8](repeating: 90, count: 1_000)
  let member = try cZlibDeflate(input, level: Z_DEFAULT_COMPRESSION, windowBits: MAX_WBITS + 16)
  let encoded = member + member

  #expect(throws: InflateError.outputLimitExceeded) {
    _ = try ZLib.inflate(input: encoded.span, format: .gzip, maximumOutputSize: 1_999)
  }
  #expect(throws: InflateError.outputLimitExceeded) {
    _ = try inflateGzipInChunks(encoded, inputChunkSize: 1, outputChunkSize: 7, maximumOutputSize: 1_999)
  }
  #expect(
    try inflateGzipInChunks(encoded, inputChunkSize: 7, outputChunkSize: 257, maximumOutputSize: 2_000)
      == input + input)
}

@Test(arguments: [ZLib.Strategy.stored, .fixed, .dynamic, .automatic], [(1, 1), (1, 17), (7, 257)])
func gzipResumesAcrossInputAndOutputChunks(strategy: ZLib.Strategy, chunks: (Int, Int)) throws {
  let input = Array(String(repeating: "ABCABC!ZZZZZZZ\n", count: 100).utf8)
  let encoded = try ZLib.deflate(input: input.span, format: .gzip, strategy: strategy)
  let compressed = (0..<encoded.count).map { encoded[$0] }

  #expect(try inflateGzipInChunks(compressed, inputChunkSize: chunks.0, outputChunkSize: chunks.1) == input)
}

@Test func gzipAcceptsEveryInputSplitAcrossHeadersTrailersAndMemberBoundaries() throws {
  let input = Array("gzip input splits".utf8)
  let first = try gzipFixtureWithOptionalHeader(input)
  let second = try cZlibDeflate(input, level: Z_DEFAULT_COMPRESSION, windowBits: MAX_WBITS + 16)
  let encoded = first + second
  let expected = input + input

  for split in 0...encoded.count {
    var inflater = try Inflater(format: .gzip)
    var decoded = UniqueArray<UInt8>(minimumCapacity: expected.count)
    let initial = try decoded.edit { output in
      try inflater.process(input: encoded.span.extracting(..<split), output: &output)
    }
    #expect(initial.inputConsumed == split)
    #expect(initial.status == .needsInput)
    #expect(inflater.isFinished == false)
    let final = try decoded.edit { output in
      try inflater.process(input: encoded.span.extracting(split...), output: &output, isFinalInput: true)
    }
    #expect(final.status == .finished)
    #expect(initial.inputConsumed + final.inputConsumed == encoded.count)
    try #require(decoded.count == expected.count)
    #expect(expected.indices.allSatisfy { decoded[$0] == expected[$0] })
  }
}

@Test func gzipChecksumAndCountsExcludePreexistingOutputBytes() throws {
  let input = Array("ABC".utf8)
  let encoded = try cZlibDeflate(input, level: Z_DEFAULT_COMPRESSION, windowBits: MAX_WBITS + 16)
  var inflater = try Inflater(format: .gzip, maximumOutputSize: input.count)
  var progress: Inflater.Progress?
  let decoded = try [UInt8](capacity: input.count + 1) { output in
    output.append(0x58)
    progress = try inflater.process(input: encoded.span, output: &output, isFinalInput: true)
  }

  #expect(decoded == [0x58] + input)
  let result = try #require(progress)
  #expect(result.status == .finished)
  #expect(result.outputProduced == input.count)
  #expect(inflater.totalOutputCount == input.count)
}

@Test(arguments: [ZLib.Strategy.stored, .fixed, .dynamic, .automatic])
func gzipCanDecodeEmptyMembersWithoutOutputStorage(strategy: ZLib.Strategy) throws {
  let empty: [UInt8] = []
  let member = try ZLib.deflate(input: empty.span, format: .gzip, strategy: strategy)
  let bytes = (0..<member.count).map { member[$0] }
  let encoded = bytes + bytes
  var inflater = try Inflater(format: .gzip, maximumOutputSize: 0)
  var output = OutputSpan<UInt8>()

  let progress = try inflater.process(input: encoded.span, output: &output, isFinalInput: true)

  #expect(progress.status == .finished)
  #expect(progress.inputConsumed == encoded.count)
  #expect(progress.outputProduced == 0)
}

@Test func gzipWaitsForFinalInputAfterACompleteMember() throws {
  let encoded = try cZlibDeflate([], level: Z_DEFAULT_COMPRESSION, windowBits: MAX_WBITS + 16)
  var inflater = try Inflater(format: .gzip)
  var output = OutputSpan<UInt8>()
  let first = try inflater.process(input: encoded.span, output: &output)

  #expect(first.status == .needsInput)
  #expect(first.inputConsumed == encoded.count)
  #expect(inflater.isFinished == false)
  let empty: [UInt8] = []
  let final = try inflater.process(input: empty.span, output: &output, isFinalInput: true)
  #expect(final.status == .finished)
  #expect(inflater.isFinished == true)
  let repeated = try inflater.process(input: empty.span, output: &output, isFinalInput: true)
  #expect(repeated.status == .finished)
  #expect(repeated.inputConsumed == 0 && repeated.outputProduced == 0)
}

@Test func gzipChecksTheTrailerEvenWhenOutputIsExactlyFull() throws {
  let input = Array("ABC".utf8)
  let encoded = try cZlibDeflate(input, level: Z_DEFAULT_COMPRESSION, windowBits: MAX_WBITS + 16)
  var inflater = try Inflater(format: .gzip)
  var progress: Inflater.Progress?
  let decoded = try [UInt8](capacity: input.count) { output in
    progress = try inflater.process(input: encoded.span, output: &output, isFinalInput: true)
  }

  #expect(decoded == input)
  let result = try #require(progress)
  #expect(result.status == .finished)
  #expect(result.inputConsumed == encoded.count)
}

@Test func gzipPreservesUnconsumedInputWhenOutputIsUnavailable() throws {
  let input = Array("ABC".utf8)
  let encoded = try cZlibDeflate(input, level: Z_DEFAULT_COMPRESSION, windowBits: MAX_WBITS + 16)
  var inflater = try Inflater(format: .gzip)
  var emptyOutput = OutputSpan<UInt8>()
  let initial = try inflater.process(input: encoded.span, output: &emptyOutput, isFinalInput: true)
  #expect(initial.status == .needsOutput)
  #expect(initial.outputProduced == 0)
  var progress: Inflater.Progress?
  let decoded = try [UInt8](capacity: input.count) { output in
    progress = try inflater.process(
      input: encoded.span.extracting(initial.inputConsumed...), output: &output, isFinalInput: true)
  }

  #expect(decoded == input)
  let final = try #require(progress)
  #expect(final.status == .finished)
  #expect(initial.inputConsumed + final.inputConsumed == encoded.count)
}

@Test(arguments: [
  ([UInt8(0x00)], InflateError.invalidGzipHeader),
  ([UInt8(0xDE), 0xAD], InflateError.invalidGzipHeader),
  ([UInt8(0x1F)], InflateError.unexpectedEndOfInput)
])
func gzipRejectsTrailingGarbageOrPartialMembers(tail: [UInt8], expectedError: InflateError) throws {
  let member = try cZlibDeflate([], level: Z_DEFAULT_COMPRESSION, windowBits: MAX_WBITS + 16)
  let encoded = member + tail

  #expect(throws: expectedError) {
    _ = try ZLib.inflate(input: encoded.span, format: .gzip)
  }
}

@Test func gzipCannotResumeAfterAChecksumFailure() throws {
  let input = Array("verified only after the trailer".utf8)
  var encoded = try cZlibDeflate(input, level: Z_DEFAULT_COMPRESSION, windowBits: MAX_WBITS + 16)
  encoded[encoded.count - 8] ^= 1
  var inflater = try Inflater(format: .gzip)
  var decoded = UniqueArray<UInt8>(minimumCapacity: input.count)

  #expect(throws: InflateError.checksumMismatch) {
    try decoded.edit { output in
      _ = try inflater.process(input: encoded.span, output: &output, isFinalInput: true)
    }
  }
  #expect(decoded.count == input.count)
  #expect(inflater.totalOutputCount == input.count)
  #expect(inflater.isFinished == false)
  let empty: [UInt8] = []
  var output = OutputSpan<UInt8>()
  #expect(throws: InflateError.invalidState) {
    try inflater.process(input: empty.span, output: &output, isFinalInput: true)
  }
}

@Test func gzipResetsDeflateHistoryBetweenMembers() throws {
  let first = try cZlibDeflate([90], level: Z_DEFAULT_COMPRESSION, windowBits: MAX_WBITS + 16)
  // Fixed DEFLATE block: length 3, distance 1, end marker, with no literal.
  // This would decode as ZZZ if history leaked from the previous member.
  let rawMatch: [UInt8] = [0x03, 0x02, 0x00]
  let header: [UInt8] = [0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 255]
  let checksum = gzipFixtureCRC32([90, 90, 90])
  let second = header + rawMatch + gzipFixtureLittleEndian(checksum) + gzipFixtureLittleEndian(3)
  let encoded = first + second

  #expect(throws: InflateError.invalidDistance) {
    _ = try ZLib.inflate(input: encoded.span, format: .gzip)
  }
}
