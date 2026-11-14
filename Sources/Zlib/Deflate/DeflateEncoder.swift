import struct BasicContainers.RigidArray

enum DeflateEncoder: ~Sendable {
  static func automatic(input: borrowing Span<UInt8>) throws(BitWriterError) -> UniqueArray<UInt8> {
    var writer = BitWriter(minimumCapacity: min(input.count, 65_536))
    var finder = LZ77MatchFinder()
    var workspace = DeflateWorkspace(maximumTokens: min(input.count, 65_535))
    var position = 0
    repeat {
      let end = position + min(65_535, input.count - position)
      try writeAutomaticBlock(
        input: input, position: &position, end: end, isFinal: end == input.count,
        finder: &finder, workspace: &workspace, writer: &writer)
    } while position < input.count
    return writer.finish()
  }

  static func stored(input: borrowing Span<UInt8>) throws(BitWriterError) -> UniqueArray<UInt8> {
    var writer = BitWriter(minimumCapacity: input.count)
    var offset = 0
    repeat {
      let blockLength = min(input.count - offset, Int(UInt16.max))
      let end = offset + blockLength
      writeStoredBlock(input: input.extracting(offset..<end), isFinal: end == input.count, writer: &writer)
      offset = end
    } while offset < input.count
    return writer.finish()
  }

  static func fixed(input: borrowing Span<UInt8>) throws(BitWriterError) -> UniqueArray<UInt8> {
    var writer = BitWriter(minimumCapacity: min(input.count, 65_536))
    var finder = LZ77MatchFinder()
    var position = 0
    try writeFixedBlock(
      input: input, position: &position, end: input.count, isFinal: true, finder: &finder, writer: &writer)
    return writer.finish()
  }

  static func dynamic(input: borrowing Span<UInt8>) throws(BitWriterError) -> UniqueArray<UInt8> {
    var writer = BitWriter(minimumCapacity: min(input.count, 65_536))
    var finder = LZ77MatchFinder()
    var workspace = DeflateWorkspace(maximumTokens: min(input.count, 65_535))
    var position = 0
    repeat {
      // Bound temporary token storage while preserving history across blocks.
      let end = position + min(65_535, input.count - position)
      try writeDynamicBlock(
        input: input, position: &position, end: end, isFinal: end == input.count,
        finder: &finder, workspace: &workspace, writer: &writer)
    } while position < input.count
    return writer.finish()
  }

  /// Appends a stored block, including its alignment and length fields.
  static func writeStoredBlock(input: borrowing Span<UInt8>, isFinal: Bool, writer: inout BitWriter) {
    precondition(input.count <= Int(UInt16.max))
    writer.writeBits(isFinal ? 0b001 : 0b000, count: 3)
    writer.alignToByte()
    let length = UInt16(input.count)
    writer.writeUInt16LittleEndian(length)
    writer.writeUInt16LittleEndian(~length)
    writer.alignToByte()
    writer.writeBytes(input)
  }

  /// Appends a fixed-Huffman block using the supplied match history.
  static func writeFixedBlock(
    input: borrowing Span<UInt8>, position: inout Int, end: Int, isFinal: Bool,
    finder: inout LZ77MatchFinder, writer: inout BitWriter
  ) throws(BitWriterError) {
    precondition(position >= 0 && position <= end && end <= input.count)
    writer.writeBits(isFinal ? 0b011 : 0b010, count: 3)
    while position < end {
      let token = finder.next(input: input, position: &position, end: end)
      try writeFixedToken(token, writer: &writer)
    }
    try writer.writeFixedLiteralLengthSymbol(256)
  }

  /// Appends a dynamic-Huffman block using the supplied match history.
  static func writeDynamicBlock(
    input: borrowing Span<UInt8>, position: inout Int, end: Int, isFinal: Bool,
    finder: inout LZ77MatchFinder, workspace: inout DeflateWorkspace, writer: inout BitWriter
  ) throws(BitWriterError) {
    workspace.prepare(input: input, position: &position, end: end, finder: &finder)
    workspace.writeDynamicBlock(isFinal: isFinal, writer: &writer)
  }

  /// Tokenizes once and emits the least expensive representation of this block.
  /// Final padding and a following sync marker affect selection but are left
  /// to the caller to emit.
  static func writeAutomaticBlock(
    input: borrowing Span<UInt8>, position: inout Int, end: Int, isFinal: Bool, syncFlush: Bool = false,
    finder: inout LZ77MatchFinder, workspace: inout DeflateWorkspace, writer: inout BitWriter
  ) throws(BitWriterError) {
    let start = position
    precondition(start >= 0 && start <= end && end <= input.count && end - start <= 65_535)
    workspace.prepare(input: input, position: &position, end: end, finder: &finder)
    let costs = DeflateBlockCosts(
      inputCount: end - start, fixedBitCount: workspace.fixedBitCount, dynamicBitCount: workspace.dynamicBitCount,
      bitPosition: writer.bitPosition, isFinal: isFinal, syncFlush: syncFlush)
    switch costs.choice {
    case .stored:
      // Tokenization has already advanced the finder, preserving match history
      // even when this block is emitted without compression.
      writeStoredBlock(input: input.extracting(start..<end), isFinal: isFinal, writer: &writer)
    case .fixed:
      writer.writeBits(isFinal ? 0b011 : 0b010, count: 3)
      for index in 0..<workspace.tokens.count { try writeFixedToken(workspace.tokens[index], writer: &writer) }
      try writer.writeFixedLiteralLengthSymbol(256)
    case .dynamic:
      workspace.writeDynamicBlock(isFinal: isFinal, writer: &writer)
    }
  }

  private static func writeFixedToken(_ token: DeflateToken, writer: inout BitWriter) throws(BitWriterError) {
    switch token {
    case .literal(let byte):
      try writer.writeFixedLiteralLengthSymbol(UInt32(byte))
    case .match(let length, let distance):
      let lengthCode = MatchCode.length(length)
      let distanceCode = MatchCode.distance(distance)
      try writer.writeFixedLiteralLengthSymbol(UInt32(lengthCode.symbol))
      writer.writeExtraBits(lengthCode.extraBits, count: lengthCode.extraBitCount)
      writer.writeHuffmanCode(UInt16(distanceCode.symbol), bitCount: 5)
      writer.writeExtraBits(distanceCode.extraBits, count: distanceCode.extraBitCount)
    }
  }
}
