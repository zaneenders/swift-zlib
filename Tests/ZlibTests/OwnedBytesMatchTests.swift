import Testing

@testable import Zlib

@Test(arguments: [1, 2, 3, 4], [0, 2, 5])
func ownedMatchesAgreeWithArrayReference(distance: Int, length: Int) throws {
  let seed = Array("ABCD".utf8)
  var reference = LZ77Output()
  var output = OwnedBytes(capacity: seed.count + length)
  for byte in seed {
    try reference.appendLiteral(byte)
    try output.append(byte)
  }

  try reference.appendMatch(distance: distance, length: length)
  try output.appendMatch(distance: distance, length: length)

  #expect(output.count == reference.bytes.count)
  let view = output.readSpan()
  try #require(view.count == reference.bytes.count)
  for index in reference.bytes.indices {
    #expect(view[index] == reference.bytes[index])
  }
}

@Test func ownedMatchWorksAfterGrowingTheAllocation() throws {
  var output = OwnedBytes(capacity: 2)
  try output.append(0x41)
  try output.append(0x42)

  output.reserveCapacity(7)
  try output.appendMatch(distance: 2, length: 5)

  let expected = Array("ABABABA".utf8)
  #expect(output.count == expected.count)
  let view = output.readSpan()
  try #require(view.count == expected.count)
  for index in expected.indices {
    #expect(view[index] == expected[index])
  }
}

@Test(arguments: [-1, 0, 3, Int.max])
func ownedMatchRejectsInvalidDistance(distance: Int) throws {
  var output = OwnedBytes(capacity: 8)
  try output.append(0x41)
  try output.append(0x42)

  #expect(throws: OwnedBytesError.invalidDistance) {
    try output.appendMatch(distance: distance, length: 3)
  }

  #expect(output.count == 2)
  let view = output.readSpan()
  try #require(view.count == 2)
  #expect(view[0] == 0x41)
  #expect(view[1] == 0x42)
}

@Test func ownedMatchRejectsEmptyHistory() {
  var output = OwnedBytes(capacity: 8)

  #expect(throws: OwnedBytesError.invalidDistance) {
    try output.appendMatch(distance: 1, length: 1)
  }

  #expect(output.count == 0)
  #expect(output.readSpan().count == 0)
}

@Test(arguments: [-1, Int.min])
func ownedMatchRejectsNegativeLength(length: Int) throws {
  var output = OwnedBytes(capacity: 1)
  try output.append(0x41)

  #expect(throws: OwnedBytesError.invalidLength) {
    try output.appendMatch(distance: 1, length: length)
  }

  #expect(output.count == 1)
  let view = output.readSpan()
  try #require(view.count == 1)
  #expect(view[0] == 0x41)
}

@Test(arguments: [5, Int.max])
func ownedMatchRejectsInsufficientCapacityBeforeWriting(length: Int) throws {
  var output = OwnedBytes(capacity: 6)
  try output.append(0x41)
  try output.append(0x42)

  #expect(throws: OwnedBytesError.capacityExceeded) {
    try output.appendMatch(distance: 2, length: length)
  }

  #expect(output.count == 2)
  let view = output.readSpan()
  try #require(view.count == 2)
  #expect(view[0] == 0x41)
  #expect(view[1] == 0x42)
}
