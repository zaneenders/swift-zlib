import Testing
import Zlib

@Test func outputSpanAppendsIntoOwnedStorage() throws {
  var output = UniqueArray<UInt8>(capacity: 4)
  output.append(0x41)

  output.edit { span in
    #expect(span.count == 1)
    #expect(span.capacity == 4)
    span[0] = 0x58
    span.append(0x42)
  }

  #expect(output.count == 2)
  let view = output.span
  try #require(view.count == 2)
  #expect(view[0] == 0x58)
  #expect(view[1] == 0x42)
}

@Test func outputSpanReturnsOwnershipWhenCallbackThrows() throws {
  var output = UniqueArray<UInt8>(capacity: 3)
  output.append(0x41)

  #expect(throws: OutputSpanTestError.stopped) {
    try output.edit { (span: inout OutputSpan<UInt8>) throws(OutputSpanTestError) in
      span.append(0x42)
      throw .stopped
    }
  }

  #expect(output.count == 2)
  output.append(0x43)
  let view = output.span
  try #require(view.count == 3)
  #expect(view[0] == 0x41)
  #expect(view[1] == 0x42)
  #expect(view[2] == 0x43)
}

@Test func outputSpanCanRemoveInitializedBytes() throws {
  var output = UniqueArray<UInt8>(capacity: 3)
  output.append(0x41)
  output.append(0x42)
  output.append(0x43)

  output.edit { span in
    span.removeLast(2)
  }

  #expect(output.count == 1)
  output.append(0x5A)
  let view = output.span
  try #require(view.count == 2)
  #expect(view[0] == 0x41)
  #expect(view[1] == 0x5A)
}

@Test(arguments: [0, 2])
func outputSpanHandlesEmptyStorage(capacity: Int) {
  var output = UniqueArray<UInt8>(capacity: capacity)

  output.edit { span in
    #expect(span.count == 0)
    #expect(span.capacity == capacity)
  }

  #expect(output.count == 0)
  #expect(output.capacity == capacity)
  #expect(output.span.count == 0)
}

private enum OutputSpanTestError: Error {
  case stopped
}
