import Testing

@testable import Zlib

@Test func appendsLiterals() throws {
  var output = LZ77Output()
  try output.appendLiteral(0x41)  // A
  try output.appendLiteral(0x42)  // B

  #expect(output.bytes == Array("AB".utf8))
}

@Test func expandsOverlappingMatch() throws {
  var output = LZ77Output()
  try output.appendLiteral(0x41)  // A
  try output.appendLiteral(0x42)  // B

  try output.appendMatch(distance: 2, length: 5)

  #expect(output.bytes == Array("ABABABA".utf8))
}

@Test func expandsMatchFromEndOfHistory() throws {
  var output = LZ77Output()
  for byte in "XYZAB".utf8 {
    try output.appendLiteral(byte)
  }

  try output.appendMatch(distance: 2, length: 5)

  #expect(output.bytes == Array("XYZABABABA".utf8))
}

@Test func rejectsUnavailableHistory() throws {
  var output = LZ77Output()
  try output.appendLiteral(0x41)

  #expect(throws: LZ77Error.invalidDistance) {
    try output.appendMatch(distance: 2, length: 3)
  }

  #expect(output.bytes == [0x41])
}

@Test func zeroLengthMatchLeavesOutputUnchanged() throws {
  var output = LZ77Output()
  try output.appendLiteral(0x41)
  try output.appendLiteral(0x42)

  try output.appendMatch(distance: 2, length: 0)

  #expect(output.bytes == Array("AB".utf8))
}

@Test func rejectsMatchWithoutHistory() {
  var output = LZ77Output()

  #expect(throws: LZ77Error.invalidDistance) {
    try output.appendMatch(distance: 1, length: 1)
  }

  #expect(output.bytes.isEmpty)
}

@Test(arguments: [0, 1])
func rejectsLiteralBeyondOutputLimit(maximumOutputSize: Int) throws {
  var output = LZ77Output(maximumOutputSize: maximumOutputSize)
  for _ in 0..<maximumOutputSize {
    try output.appendLiteral(0x41)
  }
  let before = output.bytes
  #expect(before.count == maximumOutputSize)

  #expect(throws: LZ77Error.outputLimitExceeded) {
    try output.appendLiteral(0x42)
  }

  #expect(output.bytes == before)
}

@Test func matchMayExactlyFillOutputLimit() throws {
  var output = LZ77Output(maximumOutputSize: 7)
  try output.appendLiteral(0x41)
  try output.appendLiteral(0x42)

  try output.appendMatch(distance: 2, length: 5)

  #expect(output.bytes == Array("ABABABA".utf8))
}

@Test func rejectsWholeMatchBeyondOutputLimit() throws {
  var output = LZ77Output(maximumOutputSize: 6)
  try output.appendLiteral(0x41)
  try output.appendLiteral(0x42)

  #expect(throws: LZ77Error.outputLimitExceeded) {
    try output.appendMatch(distance: 2, length: 5)
  }

  #expect(output.bytes == Array("AB".utf8))
}

@Test func zeroLengthMatchSucceedsAtOutputLimit() throws {
  var output = LZ77Output(maximumOutputSize: 1)
  try output.appendLiteral(0x41)

  try output.appendMatch(distance: 1, length: 0)

  #expect(output.bytes == [0x41])
}
