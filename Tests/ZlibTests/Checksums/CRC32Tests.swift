import Testing
import zlib

@testable import Zlib

private func cZlibCRC32(_ input: [UInt8]) -> UInt32 {
  input.withUnsafeBufferPointer { buffer in
    UInt32(zlib.crc32(0, buffer.baseAddress, uInt(buffer.count)))
  }
}

@Test(
  arguments: [
    ("", 0x0000_0000),
    ("a", 0xE8B7_BE43),
    ("abc", 0x3524_41C2),
    ("message digest", 0x2015_9D7F),
    ("Wikipedia", 0xADAA_C02E),
    ("123456789", 0xCBF4_3926)
  ] as [(text: String, expected: UInt32)])
func crc32MatchesKnownVectors(testCase: (text: String, expected: UInt32)) {
  let input = Array(testCase.text.utf8)
  #expect(CRC32.checksum(input: input.span) == testCase.expected)

  var checksum = CRC32()
  checksum.update(input: input.span)
  #expect(checksum.value == testCase.expected)
}

@Test func crc32EmptyUpdatesPreserveTheChecksum() {
  let empty: [UInt8] = []
  let input = Array("123456789".utf8)
  var checksum = CRC32()
  #expect(checksum.value == 0)
  checksum.update(input: empty.span)
  #expect(checksum.value == 0)
  checksum.update(input: input.span)
  checksum.update(input: empty.span)
  checksum.update(input: empty.span)
  #expect(checksum.value == 0xCBF4_3926)
}

@Test(arguments: [1, 7, 255, 1_024, 8_192])
func crc32IncrementalUpdatesMatchCZlib(chunkSize: Int) {
  let input = (0..<100_003).map { UInt8(truncatingIfNeeded: $0 * 37 + 11) }
  var checksum = CRC32()
  for start in stride(from: 0, to: input.count, by: chunkSize) {
    let end = min(start + chunkSize, input.count)
    checksum.update(input: input.span.extracting(start..<end))
  }
  #expect(checksum.value == cZlibCRC32(input))
}

@Test func crc32SingleByteUpdatesMatchCZlib() {
  let input = Array(UInt8.min...UInt8.max)
  var checksum = CRC32()
  for byte in input {
    checksum.update(byte: byte)
  }
  #expect(checksum.value == cZlibCRC32(input))
}

@Test func crc32CopiesCanBeUpdatedIndependently() {
  let prefix = Array("shared prefix: ".utf8)
  let firstSuffix = Array("first".utf8)
  let secondSuffix = Array("second".utf8)
  var prefixChecksum = CRC32()
  prefixChecksum.update(input: prefix.span)

  var first = prefixChecksum
  var second = prefixChecksum
  first.update(input: firstSuffix.span)
  second.update(input: secondSuffix.span)

  #expect(prefixChecksum.value == cZlibCRC32(prefix))
  #expect(first.value == cZlibCRC32(prefix + firstSuffix))
  #expect(second.value == cZlibCRC32(prefix + secondSuffix))
}

@Test func crc32ReadsOnlyTheSuppliedSpan() {
  let expected = Array("Wikipedia".utf8)
  let allocation = [UInt8](repeating: 0xFF, count: 17) + expected + [UInt8](repeating: 0xA5, count: 23)
  let input = allocation.span.extracting(17..<(17 + expected.count))
  #expect(CRC32.checksum(input: input) == cZlibCRC32(expected))

  var checksum = CRC32()
  checksum.update(input: input)
  checksum.update(input: allocation.span.extracting(17..<17))
  #expect(checksum.value == cZlibCRC32(expected))
}

@Test(arguments: [0, 1, 255, 256, 257, 65_535, 65_536, 65_537, 1_000_000])
func crc32HighBytesMatchCZlib(length: Int) {
  let input = [UInt8](repeating: 0xFF, count: length)
  #expect(CRC32.checksum(input: input.span) == cZlibCRC32(input))
}

@Test(arguments: [0, 1, 31, 256, 65_537, 250_000])
func crc32DeterministicRandomInputsMatchCZlib(length: Int) {
  var state: UInt32 = 0xC0FFEE
  let input = (0..<length).map { _ in
    state ^= state << 13
    state ^= state >> 17
    state ^= state << 5
    return UInt8(truncatingIfNeeded: state)
  }
  #expect(CRC32.checksum(input: input.span) == cZlibCRC32(input))
}
