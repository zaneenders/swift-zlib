import Testing

@testable import Zlib

@Test func pendingMatchExpandsOverlappingHistory() throws {
  var history = HistoryWindow(capacity: 4)
  for byte in "AB".utf8 {
    history.appendLiteral(byte)
  }
  var match = PendingMatch(distance: 2, length: 5)
  var produced = 0

  let bytes = try [UInt8](capacity: 5) { output in
    produced = try match.emit(into: &output, history: &history)
  }

  #expect(bytes == Array("ABABA".utf8))
  #expect(produced == 5)
  #expect(match.remaining == 0)
  #expect(match.isComplete == true)
  #expect(history.count == 4)
  #expect(try history.byte(distance: 1) == 0x41)
  #expect(try history.byte(distance: 2) == 0x42)
}

@Test func pendingMatchRepeatsWithSingleByteHistory() throws {
  var history = HistoryWindow(capacity: 1)
  history.appendLiteral(0x5A)
  var match = PendingMatch(distance: 1, length: 7)

  let bytes = try [UInt8](capacity: 7) { output in
    try match.emit(into: &output, history: &history)
  }

  #expect(bytes == Array("ZZZZZZZ".utf8))
  #expect(match.remaining == 0)
  #expect(history.count == 1)
  #expect(history.capacity == 1)
  #expect(try history.byte(distance: 1) == 0x5A)
}

@Test func pendingMatchReadsOldestByteBeforeOverwritingItsSlot() throws {
  var history = HistoryWindow(capacity: 4)
  for byte in "ABCDEF".utf8 {
    history.appendLiteral(byte)
  }
  var match = PendingMatch(distance: 4, length: 6)

  let bytes = try [UInt8](capacity: 6) { output in
    try match.emit(into: &output, history: &history)
  }

  #expect(bytes == Array("CDEFCD".utf8))
  #expect(match.isComplete == true)
  #expect(history.count == 4)
  #expect(history.writeIndex == 0)
  #expect(try history.byte(distance: 1) == 0x44)
  #expect(try history.byte(distance: 4) == 0x45)
}

@Test(arguments: [1, 2, 3, 4])
func pendingMatchResumesInFreshOutputChunk(firstCapacity: Int) throws {
  var history = HistoryWindow(capacity: 4)
  for byte in "AB".utf8 {
    history.appendLiteral(byte)
  }
  var match = PendingMatch(distance: 2, length: 5)
  let expected = Array("ABABA".utf8)
  var firstProduced = 0
  var secondProduced = 0

  let first = try [UInt8](capacity: firstCapacity) { output in
    firstProduced = try match.emit(into: &output, history: &history)
  }

  #expect(first == Array(expected.prefix(firstCapacity)))
  #expect(firstProduced == firstCapacity)
  #expect(match.remaining == 5 - firstCapacity)
  #expect(match.isComplete == false)

  let second = try [UInt8](capacity: 5 - firstCapacity) { output in
    secondProduced = try match.emit(into: &output, history: &history)
  }

  #expect(second == Array(expected.dropFirst(firstCapacity)))
  #expect(secondProduced == 5 - firstCapacity)
  #expect(first + second == expected)
  #expect(match.remaining == 0)
  #expect(match.isComplete == true)
}

@Test func pendingMatchUsesOnlyFreeOutputCapacity() throws {
  var history = HistoryWindow(capacity: 4)
  for byte in "AB".utf8 {
    history.appendLiteral(byte)
  }
  var match = PendingMatch(distance: 2, length: 5)
  var produced = 0

  let bytes = try [UInt8](capacity: 3) { output in
    output.append(0x58)
    produced = try match.emit(into: &output, history: &history)
  }

  #expect(bytes == Array("XAB".utf8))
  #expect(produced == 2)
  #expect(match.remaining == 3)
  #expect(history.count == 4)
  #expect(try history.byte(distance: 1) == 0x42)
}

@Test func pendingMatchWaitsWhenOutputIsFull() throws {
  var history = HistoryWindow(capacity: 4)
  for byte in "AB".utf8 {
    history.appendLiteral(byte)
  }
  var match = PendingMatch(distance: 2, length: 5)
  var output = OutputSpan<UInt8>()

  #expect(try match.emit(into: &output, history: &history) == 0)

  #expect(output.count == 0)
  #expect(match.remaining == 5)
  #expect(history.count == 2)
  #expect(history.writeIndex == 2)
  #expect(try history.byte(distance: 1) == 0x42)
}

@Test func completedMatchProducesNoMoreBytes() throws {
  var history = HistoryWindow(capacity: 4)
  history.appendLiteral(0x41)
  var match = PendingMatch(distance: 1, length: 0)
  var produced = -1

  let bytes = try [UInt8](capacity: 2) { output in
    produced = try match.emit(into: &output, history: &history)
  }

  #expect(bytes.isEmpty)
  #expect(produced == 0)
  #expect(match.isComplete == true)
  #expect(history.count == 1)
  #expect(history.writeIndex == 1)
}

@Test(arguments: [-1, 0, 3, Int.max])
func pendingMatchRejectsUnavailableDistanceWithoutWriting(distance: Int) throws {
  var history = HistoryWindow(capacity: 4)
  for byte in "AB".utf8 {
    history.appendLiteral(byte)
  }
  var match = PendingMatch(distance: distance, length: 3)
  var output = OwnedBytes(capacity: 3)
  try output.append(0x58)

  #expect(throws: HistoryWindowError.invalidDistance) {
    try output.withOutputSpan { span in
      try match.emit(into: &span, history: &history)
    }
  }

  #expect(output.count == 1)
  #expect(output.readSpan()[0] == 0x58)
  #expect(match.remaining == 3)
  #expect(history.count == 2)
  #expect(history.writeIndex == 2)
}

@Test func pendingMatchRejectsEmptyHistory() {
  var history = HistoryWindow(capacity: 4)
  var match = PendingMatch(distance: 1, length: 3)
  var output = OutputSpan<UInt8>()

  #expect(throws: HistoryWindowError.invalidDistance) {
    try match.emit(into: &output, history: &history)
  }

  #expect(output.count == 0)
  #expect(match.remaining == 3)
  #expect(history.count == 0)
}

@Test(arguments: [-1, Int.min])
func pendingMatchRejectsNegativeLengthWithoutWriting(length: Int) {
  var history = HistoryWindow(capacity: 4)
  history.appendLiteral(0x41)
  var match = PendingMatch(distance: 1, length: length)
  var output = OutputSpan<UInt8>()

  #expect(throws: HistoryWindowError.invalidLength) {
    try match.emit(into: &output, history: &history)
  }

  #expect(output.count == 0)
  #expect(match.remaining == length)
  #expect(history.count == 1)
  #expect(history.writeIndex == 1)
}
