import Testing

@testable import Zlib

@Test(arguments: [1, 2, 3, 4], [0, 2, 5])
func uniqueArrayMatchesAgreeWithArrayReference(distance: Int, length: Int) throws {
  let seed = Array("ABCD".utf8)
  var reference = LZ77Output()
  var output = UniqueArray<UInt8>(capacity: seed.count + length)
  for byte in seed {
    try reference.appendLiteral(byte)
    output.append(byte)
  }

  try reference.appendMatch(distance: distance, length: length)
  try output.appendMatch(distance: distance, length: length)

  #expect(output.count == reference.bytes.count)
  let view = output.span
  try #require(view.count == reference.bytes.count)
  for index in reference.bytes.indices {
    #expect(view[index] == reference.bytes[index])
  }
}

@Test func uniqueArrayMatchWorksAfterGrowingTheAllocation() throws {
  var output = UniqueArray<UInt8>(capacity: 2)
  output.append(0x41)
  output.append(0x42)

  output.reserveCapacity(7)
  try output.appendMatch(distance: 2, length: 5)

  let expected = Array("ABABABA".utf8)
  #expect(output.count == expected.count)
  let view = output.span
  try #require(view.count == expected.count)
  for index in expected.indices {
    #expect(view[index] == expected[index])
  }
}

@Test(arguments: [-1, 0, 3, Int.max])
func uniqueArrayMatchRejectsInvalidDistance(distance: Int) throws {
  var output = UniqueArray<UInt8>(capacity: 8)
  output.append(0x41)
  output.append(0x42)

  #expect(throws: MatchOutputError.invalidDistance) {
    try output.appendMatch(distance: distance, length: 3)
  }

  #expect(output.count == 2)
  let view = output.span
  try #require(view.count == 2)
  #expect(view[0] == 0x41)
  #expect(view[1] == 0x42)
}

@Test func uniqueArrayMatchRejectsEmptyHistory() {
  var output = UniqueArray<UInt8>(capacity: 8)

  #expect(throws: MatchOutputError.invalidDistance) {
    try output.appendMatch(distance: 1, length: 1)
  }

  #expect(output.count == 0)
  #expect(output.span.count == 0)
}

@Test(arguments: [-1, Int.min])
func uniqueArrayMatchRejectsNegativeLength(length: Int) throws {
  var output = UniqueArray<UInt8>(capacity: 1)
  output.append(0x41)

  #expect(throws: MatchOutputError.invalidLength) {
    try output.appendMatch(distance: 1, length: length)
  }

  #expect(output.count == 1)
  let view = output.span
  try #require(view.count == 1)
  #expect(view[0] == 0x41)
}

@Test(arguments: [5, Int.max])
func uniqueArrayMatchRejectsInsufficientCapacityBeforeWriting(length: Int) throws {
  var output = UniqueArray<UInt8>(capacity: 6)
  output.append(0x41)
  output.append(0x42)

  #expect(throws: MatchOutputError.capacityExceeded) {
    try output.appendMatch(distance: 2, length: length)
  }

  #expect(output.count == 2)
  let view = output.span
  try #require(view.count == 2)
  #expect(view[0] == 0x41)
  #expect(view[1] == 0x42)
}
