import Testing
import Zlib
import zlib

private func cZlibAdler32(_ input: [UInt8]) -> UInt32 {
  input.withUnsafeBufferPointer { buffer in
    UInt32(zlib.adler32(1, buffer.baseAddress, uInt(buffer.count)))
  }
}

@Test(
  arguments: [
    ("", 0x0000_0001),
    ("a", 0x0062_0062),
    ("abc", 0x024D_0127),
    ("message digest", 0x2975_0586),
    ("Wikipedia", 0x11E6_0398),
    ("123456789", 0x091E_01DE)
  ] as [(text: String, expected: UInt32)])
func adler32MatchesKnownVectors(testCase: (text: String, expected: UInt32)) {
  let input = Array(testCase.text.utf8)
  #expect(Adler32.checksum(input: input.span) == testCase.expected)

  var checksum = Adler32()
  checksum.update(input: input.span)
  #expect(checksum.value == testCase.expected)
}

@Test func adler32EmptyUpdatesPreserveTheChecksum() {
  let empty: [UInt8] = []
  let input = Array("Wikipedia".utf8)
  var checksum = Adler32()
  #expect(checksum.value == 1)
  checksum.update(input: empty.span)
  #expect(checksum.value == 1)
  checksum.update(input: input.span)
  checksum.update(input: empty.span)
  checksum.update(input: empty.span)
  #expect(checksum.value == 0x11E6_0398)
}

@Test(arguments: [1, 7, 255, 5_551, 5_552, 5_553, 8_192])
func adler32IncrementalUpdatesMatchCZlib(chunkSize: Int) {
  let input = (0..<100_003).map { UInt8(truncatingIfNeeded: $0 * 37 + 11) }
  var checksum = Adler32()
  for start in stride(from: 0, to: input.count, by: chunkSize) {
    let end = min(start + chunkSize, input.count)
    checksum.update(input: input.span.extracting(start..<end))
  }
  #expect(checksum.value == cZlibAdler32(input))
}

@Test func adler32CopiesCanBeUpdatedIndependently() {
  let prefix = Array("shared prefix: ".utf8)
  let firstSuffix = Array("first".utf8)
  let secondSuffix = Array("second".utf8)
  var prefixChecksum = Adler32()
  prefixChecksum.update(input: prefix.span)

  var first = prefixChecksum
  var second = prefixChecksum
  first.update(input: firstSuffix.span)
  second.update(input: secondSuffix.span)

  #expect(prefixChecksum.value == cZlibAdler32(prefix))
  #expect(first.value == cZlibAdler32(prefix + firstSuffix))
  #expect(second.value == cZlibAdler32(prefix + secondSuffix))
}

@Test func adler32ReadsOnlyTheSuppliedSpan() {
  let expected = Array("Wikipedia".utf8)
  let allocation = [UInt8](repeating: 0xFF, count: 17) + expected + [UInt8](repeating: 0xA5, count: 23)
  let input = allocation.span.extracting(17..<(17 + expected.count))
  #expect(Adler32.checksum(input: input) == cZlibAdler32(expected))

  var checksum = Adler32()
  checksum.update(input: input)
  checksum.update(input: allocation.span.extracting(17..<17))
  #expect(checksum.value == cZlibAdler32(expected))
}

@Test(
  arguments: [
    0, 1, 255, 256, 257, 5_551, 5_552, 5_553, 11_103, 11_104, 11_105,
    65_520, 65_521, 65_522, 1_000_000
  ])
func adler32HighBytesMatchCZlibAcrossReductionBoundaries(length: Int) {
  let input = [UInt8](repeating: 0xFF, count: length)
  #expect(Adler32.checksum(input: input.span) == cZlibAdler32(input))
}

@Test(arguments: [0, 1, 31, 5_552, 5_553, 65_537, 250_000])
func adler32DeterministicRandomInputsMatchCZlib(length: Int) {
  var state: UInt32 = 0xC0FFEE
  let input = (0..<length).map { _ in
    state ^= state << 13
    state ^= state >> 17
    state ^= state << 5
    return UInt8(truncatingIfNeeded: state)
  }
  #expect(Adler32.checksum(input: input.span) == cZlibAdler32(input))
}
