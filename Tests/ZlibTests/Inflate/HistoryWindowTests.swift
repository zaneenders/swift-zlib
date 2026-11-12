import Testing

@testable import Zlib

@Test func historyStartsEmptyWithDeflateWindow() {
  let history = HistoryWindow()

  #expect(history.capacity == 32 * 1024)
  #expect(history.count == 0)
  #expect(history.writeIndex == 0)
  #expect(throws: HistoryWindowError.invalidDistance) {
    try history.byte(distance: 1)
  }
}

@Test func historyReadsBackwardBeforeWrapping() throws {
  var history = HistoryWindow(capacity: 4)
  for byte in "AB".utf8 {
    history.appendLiteral(byte)
  }

  #expect(history.count == 2)
  #expect(history.writeIndex == 2)
  #expect(try history.byte(distance: 1) == 0x42)
  #expect(try history.byte(distance: 2) == 0x41)
  #expect(throws: HistoryWindowError.invalidDistance) {
    try history.byte(distance: 3)
  }
}

@Test func historyCanReadTheOldestByteWhenFull() throws {
  var history = HistoryWindow(capacity: 4)
  for byte in "ABCD".utf8 {
    history.appendLiteral(byte)
  }

  #expect(history.count == 4)
  #expect(history.writeIndex == 0)
  #expect(try history.byte(distance: 1) == 0x44)
  #expect(try history.byte(distance: 4) == 0x41)
}

@Test func historyWrapsAndDiscardsTheOldestBytes() throws {
  var history = HistoryWindow(capacity: 4)
  for byte in "ABCDEF".utf8 {
    history.appendLiteral(byte)
  }

  #expect(history.capacity == 4)
  #expect(history.count == 4)
  #expect(history.writeIndex == 2)
  #expect(try history.byte(distance: 1) == 0x46)
  #expect(try history.byte(distance: 2) == 0x45)
  #expect(try history.byte(distance: 3) == 0x44)
  #expect(try history.byte(distance: 4) == 0x43)
  #expect(throws: HistoryWindowError.invalidDistance) {
    try history.byte(distance: 5)
  }
}

@Test func historySurvivesMultipleWraps() throws {
  var history = HistoryWindow(capacity: 3)
  for byte in "ABCDEFGHIJK".utf8 {
    history.appendLiteral(byte)
  }

  #expect(history.capacity == 3)
  #expect(history.count == 3)
  #expect(history.writeIndex == 2)
  #expect(try history.byte(distance: 1) == 0x4B)
  #expect(try history.byte(distance: 2) == 0x4A)
  #expect(try history.byte(distance: 3) == 0x49)
}

@Test func singleByteHistoryAlwaysKeepsTheNewestByte() throws {
  var history = HistoryWindow(capacity: 1)
  for byte in "ABCD".utf8 {
    history.appendLiteral(byte)
  }

  #expect(history.capacity == 1)
  #expect(history.count == 1)
  #expect(history.writeIndex == 0)
  #expect(try history.byte(distance: 1) == 0x44)
  #expect(throws: HistoryWindowError.invalidDistance) {
    try history.byte(distance: 2)
  }
}

@Test(arguments: [-1, 0, 3, Int.max])
func historyRejectsUnavailableDistances(distance: Int) {
  var history = HistoryWindow(capacity: 4)
  for byte in "AB".utf8 {
    history.appendLiteral(byte)
  }

  #expect(throws: HistoryWindowError.invalidDistance) {
    try history.byte(distance: distance)
  }
  #expect(history.count == 2)
  #expect(history.writeIndex == 2)
}
