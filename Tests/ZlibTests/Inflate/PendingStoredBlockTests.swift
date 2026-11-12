import Testing

@testable import Zlib

@Test func storedBlockCopiesIntoOutputAndHistory() throws {
  let input = Array("ABC!".utf8)
  var reader = BitReader(input.span.bytes)
  var history = HistoryWindow()
  var block = PendingStoredBlock(length: 3)
  var produced = 0

  let bytes = try [UInt8](capacity: 5) { output in
    output.append(0x58)
    produced = try block.emit(from: &reader, into: &output, history: &history)
  }

  #expect(bytes == Array("XABC".utf8))
  #expect(produced == 3)
  #expect(block.remaining == 0)
  #expect(block.isComplete == true)
  #expect(history.count == 3)
  #expect(try history.byte(distance: 1) == 0x43)
  #expect(try history.byte(distance: 3) == 0x41)
  #expect(reader.byteOffset == 3)
  #expect(try reader.readBits(8) == 0x21)
}

@Test(arguments: [1, 2])
func storedBlockResumesInAnotherOutputChunk(firstCapacity: Int) throws {
  let input = Array("ABC".utf8)
  var reader = BitReader(input.span.bytes)
  var history = HistoryWindow()
  var block = PendingStoredBlock(length: 3)

  let first = try [UInt8](capacity: firstCapacity) { output in
    _ = try block.emit(from: &reader, into: &output, history: &history)
  }

  #expect(first == Array(input.prefix(firstCapacity)))
  #expect(reader.byteOffset == firstCapacity)
  #expect(block.remaining == UInt16(3 - firstCapacity))
  #expect(block.isComplete == false)

  let second = try [UInt8](capacity: 3 - firstCapacity) { output in
    _ = try block.emit(from: &reader, into: &output, history: &history)
  }

  #expect(first + second == input)
  #expect(reader.byteOffset == 3)
  #expect(block.remaining == 0)
  #expect(block.isComplete == true)
  #expect(history.count == 3)
  #expect(try history.byte(distance: 1) == 0x43)
}

@Test func storedBlockDoesNotReadWhenOutputIsFull() throws {
  let input: [UInt8] = []
  var reader = BitReader(input.span.bytes)
  var history = HistoryWindow()
  var block = PendingStoredBlock(length: 3)
  var output = OutputSpan<UInt8>()

  let produced = try block.emit(from: &reader, into: &output, history: &history)

  #expect(produced == 0)
  #expect(reader.byteOffset == 0)
  #expect(reader.bitOffset == 0)
  #expect(block.remaining == 3)
  #expect(history.count == 0)
}

@Test func storedBlockRetainsProgressWhenInputIsTruncated() throws {
  let input = Array("AB".utf8)
  var reader = BitReader(input.span.bytes)
  var history = HistoryWindow()
  var block = PendingStoredBlock(length: 3)
  var output = UniqueArray<UInt8>(capacity: 3)

  #expect(throws: BitReaderError.unexpectedEndOfInput) {
    try output.edit { (span: inout OutputSpan<UInt8>) throws(BitReaderError) in
      _ = try block.emit(from: &reader, into: &span, history: &history)
    }
  }

  let bytes = output.span
  try #require(bytes.count == 2)
  #expect(bytes[0] == 0x41)
  #expect(bytes[1] == 0x42)
  #expect(reader.byteOffset == 2)
  #expect(reader.bitOffset == 0)
  #expect(block.remaining == 1)
  #expect(history.count == 2)
  #expect(try history.byte(distance: 1) == 0x42)
}
