import Testing
import Zlib
import zlib

@Test(arguments: InteropPayload.allCases, [ZLib.Strategy.stored, .fixed, .dynamic])
func swiftZlibOutputIsDecodedByCZlib(payload: InteropPayload, strategy: ZLib.Strategy) throws {
  let input = payload.bytes
  let encoded = try ZLib.deflate(input: input.span, format: .zlib, strategy: strategy)
  let compressed = (0..<encoded.count).map { encoded[$0] }

  #expect(try cZlibInflate(compressed, expectedCount: input.count, windowBits: MAX_WBITS) == input)
}

@Test(arguments: [InteropPayload.empty, .text, .pseudoRandom, .multipleBlocks], [Int32(0), 1, 6, 9])
func swiftZlibInflateDecodesCZlibOutput(payload: InteropPayload, level: Int32) throws {
  let input = payload.bytes
  let encoded = try cZlibDeflate(input, level: level, strategy: Z_DEFAULT_STRATEGY, windowBits: MAX_WBITS)
  let decoded = try ZLib.inflate(input: encoded.span, format: .zlib)

  try #require(decoded.count == input.count)
  #expect(input.indices.allSatisfy { decoded[$0] == input[$0] })
}

@Test(arguments: [ZLib.Strategy.stored, .fixed, .dynamic])
func zlibEmptyStreamsFinishWithoutOutputStorage(strategy: ZLib.Strategy) throws {
  let empty: [UInt8] = []
  let encoded = try ZLib.deflate(input: empty.span, format: .zlib, strategy: strategy)
  var inflater = try Inflater(format: .zlib, maximumOutputSize: 0)
  var output = OutputSpan<UInt8>()

  let progress = try inflater.process(input: encoded.span, output: &output)

  #expect(progress.status == .finished)
  #expect(progress.inputConsumed == encoded.count)
  #expect(progress.outputProduced == 0)
  #expect(inflater.isFinished == true)
  let decoded = try ZLib.inflate(input: encoded.span, format: .zlib, maximumOutputSize: 0)
  #expect(decoded.count == 0)
}

@Test(arguments: [ZLib.Strategy.stored, .fixed, .dynamic], [(1, 1), (1, 17), (7, 257), (4_096, 13)])
func zlibResumesAcrossInputAndOutputChunks(strategy: ZLib.Strategy, chunks: (Int, Int)) throws {
  let input = Array(String(repeating: "ABCABC!ZZZZZZZ\n", count: 100).utf8)
  let encoded = try ZLib.deflate(input: input.span, format: .zlib, strategy: strategy)
  let compressed = (0..<encoded.count).map { encoded[$0] }

  #expect(try inflateZlibInChunks(compressed, inputChunkSize: chunks.0, outputChunkSize: chunks.1) == input)
}

@Test func zlibAcceptsEveryInputSplitIncludingHeaderAndTrailer() throws {
  let input = Array(String(repeating: "zlib input splits\n", count: 20).utf8)
  let encoded = try cZlibDeflate(
    input, level: Z_DEFAULT_COMPRESSION, strategy: Z_DEFAULT_STRATEGY, windowBits: MAX_WBITS)

  for split in 0...encoded.count {
    var inflater = try Inflater(format: .zlib)
    var decoded = UniqueArray<UInt8>(minimumCapacity: input.count)
    let initial = try decoded.edit { output in
      try inflater.process(input: encoded.span.extracting(..<split), output: &output)
    }
    #expect(initial.inputConsumed == split)
    #expect(initial.status == (split == encoded.count ? .finished : .needsInput))
    let final = try decoded.edit { output in
      try inflater.process(input: encoded.span.extracting(split...), output: &output, isFinalInput: true)
    }
    #expect(final.status == .finished)
    #expect(initial.inputConsumed + final.inputConsumed == encoded.count)
    try #require(decoded.count == input.count)
    #expect(input.indices.allSatisfy { decoded[$0] == input[$0] })
  }
}

@Test(arguments: [
  (UInt8(8), UInt8(8), InflateError.invalidZlibHeader),
  (UInt8(15), UInt8(8), InflateError.invalidZlibHeader),
  (UInt8(7), UInt8(0), InflateError.unsupportedCompressionMethod),
  (UInt8(7), UInt8(9), InflateError.unsupportedCompressionMethod)
])
func zlibRejectsInvalidCompressionHeaders(cinfo: UInt8, method: UInt8, expectedError: InflateError) throws {
  let member = try cZlibDeflate([], level: Z_DEFAULT_COMPRESSION, windowBits: MAX_WBITS)
  let encoded = zlibFixtureHeader(cinfo: cinfo, method: method) + member.dropFirst(2)

  #expect(throws: expectedError) {
    _ = try ZLib.inflate(input: encoded.span, format: .zlib)
  }
}

@Test func zlibRejectsBadHeaderCheckBitsAndPresetDictionaries() throws {
  let member = try cZlibDeflate([], level: Z_DEFAULT_COMPRESSION, windowBits: MAX_WBITS)
  var badCheck = member
  badCheck[1] ^= 1
  #expect(throws: InflateError.invalidZlibHeader) {
    _ = try ZLib.inflate(input: badCheck.span, format: .zlib)
  }

  let dictionaryID: [UInt8] = [0, 0, 0, 1]
  let dictionary = zlibFixtureHeader(dictionary: true) + dictionaryID + member.dropFirst(2)
  #expect(throws: InflateError.unsupportedDictionary) {
    _ = try ZLib.inflate(input: dictionary.span, format: .zlib)
  }
}

@Test func zlibRejectsChecksumCorruptionAndCannotResumeAfterFailure() throws {
  let input = Array("Adler-32 verifies the uncompressed bytes".utf8)
  var encoded = try cZlibDeflate(input, level: Z_DEFAULT_COMPRESSION, windowBits: MAX_WBITS)
  encoded[encoded.count - 1] ^= 1
  #expect(throws: InflateError.checksumMismatch) {
    _ = try ZLib.inflate(input: encoded.span, format: .zlib)
  }
  #expect(throws: InflateError.checksumMismatch) {
    _ = try inflateZlibInChunks(encoded, inputChunkSize: 1, outputChunkSize: 1)
  }

  var inflater = try Inflater(format: .zlib)
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
    try inflater.process(input: empty.span, output: &output)
  }
}

@Test func zlibRejectsEveryTruncatedPrefix() throws {
  let input = Array("truncated zlib stream".utf8)
  let encoded = try cZlibDeflate(input, level: Z_DEFAULT_COMPRESSION, windowBits: MAX_WBITS)
  for count in 0..<encoded.count {
    let prefix = encoded.span.extracting(..<count)
    #expect(throws: InflateError.unexpectedEndOfInput) {
      _ = try ZLib.inflate(input: prefix, format: .zlib)
    }
  }
}

@Test(arguments: [(UInt8(0), 256), (UInt8(0), 257), (UInt8(1), 257), (UInt8(7), 257)], UInt8(0)...UInt8(3))
func zlibHonorsTheAdvertisedWindowSize(windowAndDistance: (UInt8, Int), level: UInt8) throws {
  let (cinfo, distance) = windowAndDistance
  let history = (0..<257).map { UInt8(truncatingIfNeeded: $0) }
  // Nonfinal stored block with 257 bytes, then a final fixed block containing
  // length 3 at distance 256 or 257 followed by its end marker.
  let match: [UInt8] = distance == 256 ? [0x03, 0xFA, 0x1F, 0] : [0x03, 0x06, 0, 0]
  let raw = [UInt8(0), 1, 1, 0xFE, 0xFE] + history + match
  let expected = history + history[(257 - distance)..<(260 - distance)]
  let encoded = zlibFixtureHeader(cinfo: cinfo, level: level) + raw + zlibFixtureTrailer(expected)

  if distance > (1 << (Int(cinfo) + 8)) {
    #expect(throws: InflateError.invalidDistance) {
      _ = try ZLib.inflate(input: encoded.span, format: .zlib)
    }
    #expect(throws: InflateError.invalidDistance) {
      _ = try inflateZlibInChunks(encoded, inputChunkSize: 1, outputChunkSize: 17)
    }
  } else {
    #expect(try cZlibInflate(encoded, expectedCount: expected.count, windowBits: MAX_WBITS) == expected)
    #expect(try inflateZlibInChunks(encoded, inputChunkSize: 1, outputChunkSize: 17) == expected)
  }
}

@Test(arguments: [ZLib.Strategy.stored, .fixed, .dynamic])
func zlibEnforcesTheOutputLimitAndAcceptsAnExactFit(strategy: ZLib.Strategy) throws {
  let input = [UInt8](repeating: 90, count: 1_000)
  let encoded = try ZLib.deflate(input: input.span, format: .zlib, strategy: strategy)
  let compressed = (0..<encoded.count).map { encoded[$0] }

  #expect(throws: InflateError.outputLimitExceeded) {
    _ = try ZLib.inflate(input: encoded.span, format: .zlib, maximumOutputSize: input.count - 1)
  }
  let decoded = try ZLib.inflate(input: encoded.span, format: .zlib, maximumOutputSize: input.count)
  #expect(decoded.count == input.count)
  #expect(
    try inflateZlibInChunks(compressed, inputChunkSize: 1, outputChunkSize: 7, maximumOutputSize: input.count)
      == input)
}

@Test func zlibChecksumAndCountsExcludePreexistingOutputBytes() throws {
  let input = Array("ABC".utf8)
  let encoded = try cZlibDeflate(input, level: Z_DEFAULT_COMPRESSION, windowBits: MAX_WBITS)
  var inflater = try Inflater(format: .zlib, maximumOutputSize: input.count)
  var progress: Inflater.Progress?
  let decoded = try [UInt8](capacity: input.count + 1) { output in
    output.append(0x58)
    progress = try inflater.process(input: encoded.span, output: &output, isFinalInput: true)
  }

  #expect(decoded == [0x58] + input)
  let result = try #require(progress)
  #expect(result.status == .finished)
  #expect(result.inputConsumed == encoded.count)
  #expect(result.outputProduced == input.count)
  #expect(inflater.totalOutputCount == input.count)
}

@Test func zlibResumesAfterOutputBackpressureAndConsumesItsTrailerWithFullOutput() throws {
  let input = Array("ABC".utf8)
  let encoded = try cZlibDeflate(input, level: Z_DEFAULT_COMPRESSION, windowBits: MAX_WBITS)
  var inflater = try Inflater(format: .zlib)
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

@Test(arguments: [false, true])
func zlibOneShotRejectsTrailingDataIncludingAnotherStream(appendStream: Bool) throws {
  let input = Array("one zlib stream".utf8)
  let member = try cZlibDeflate(input, level: Z_DEFAULT_COMPRESSION, windowBits: MAX_WBITS)
  let encoded = member + (appendStream ? member : [0xDE, 0xAD])

  #expect(throws: InflateError.trailingData) {
    _ = try ZLib.inflate(input: encoded.span, format: .zlib)
  }
}

@Test func zlibStreamingStopsAfterItsTrailerWithoutWaitingForFinalInput() throws {
  let input = Array("embedded zlib stream".utf8)
  let member = try cZlibDeflate(input, level: Z_DEFAULT_COMPRESSION, windowBits: MAX_WBITS)
  let trailing: [UInt8] = [0xDE, 0xAD]
  let encoded = member + trailing
  var inflater = try Inflater(format: .zlib)
  var progress: Inflater.Progress?
  let decoded = try [UInt8](capacity: input.count) { output in
    progress = try inflater.process(input: encoded.span, output: &output)
  }

  #expect(decoded == input)
  let final = try #require(progress)
  #expect(final.status == .finished)
  #expect(final.inputConsumed == member.count)
  #expect(inflater.isFinished == true)
  var output = OutputSpan<UInt8>()
  let repeated = try inflater.process(input: trailing.span, output: &output, isFinalInput: true)
  #expect(repeated.status == .finished)
  #expect(repeated.inputConsumed == 0 && repeated.outputProduced == 0)
}
