import Testing
import Zlib

func inflateInChunks(
  _ input: [UInt8], inputChunkSize: Int, outputChunkSize: Int, maximumOutputSize: Int = .max
) throws -> [UInt8] {
  var inflater = try Inflater(maximumOutputSize: maximumOutputSize)
  var offset = 0
  var decoded: [UInt8] = []
  while !inflater.isFinished {
    let end = min(input.count, offset + inputChunkSize)
    var progress: Inflater.Progress?
    let chunk = try [UInt8](capacity: outputChunkSize) { output in
      progress = try inflater.process(
        input: input.span.extracting(offset..<end), output: &output, isFinalInput: end == input.count)
    }
    let step = try #require(progress)
    #expect(step.inputConsumed <= end - offset)
    #expect(step.outputProduced == chunk.count)
    try #require(step.inputConsumed > 0 || step.outputProduced > 0 || step.status == .finished)
    offset += step.inputConsumed
    decoded += chunk
    #expect(inflater.totalOutputCount == decoded.count)
    if step.status == .needsInput {
      #expect(offset == end)
    }
  }
  #expect(offset == input.count)
  return decoded
}
