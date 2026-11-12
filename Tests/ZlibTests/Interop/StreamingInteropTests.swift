import Testing
import Zlib
import zlib

@Test(arguments: [InteropPayload.text, .pseudoRandom, .multipleBlocks], [Z_NO_COMPRESSION, Z_DEFAULT_COMPRESSION])
func chunkedInflaterDecodesCZlibStreams(payload: InteropPayload, level: Int32) throws {
  let input = payload.bytes
  let compressed = try cZlibDeflate(input, level: level, strategy: Z_DEFAULT_STRATEGY)
  #expect(try inflateInChunks(compressed, inputChunkSize: 7, outputChunkSize: 257) == input)
}

@Test func inflaterAcceptsEveryInputSplitOfACZlibDynamicStream() throws {
  let input = InteropPayload.text.bytes
  let compressed = try cZlibDeflate(input, level: Z_DEFAULT_COMPRESSION, strategy: Z_DEFAULT_STRATEGY)
  try #require(compressed[0] & 0b110 == 0b100)

  for split in 0...compressed.count {
    var inflater = try Inflater()
    var decoded = UniqueArray<UInt8>(minimumCapacity: input.count)
    let first = try decoded.edit { span in
      try inflater.process(input: compressed.span.extracting(..<split), output: &span)
    }
    #expect(first.inputConsumed == split)
    let last = try decoded.edit { span in
      try inflater.process(input: compressed.span.extracting(split...), output: &span, isFinalInput: true)
    }
    #expect(last.status == .finished)
    #expect(decoded.count == input.count)
    #expect(input.indices.allSatisfy { decoded[$0] == input[$0] })
  }
}
