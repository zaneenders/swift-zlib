import Foundation
import Testing
import Zlib

#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

#if os(Linux) || os(macOS)
private typealias AllocationProbe = @convention(c) (Int32) -> Int64

private func measuredAllocations(
  _ probe: AllocationProbe, _ operation: () throws(DeflateError) -> Void
) throws(DeflateError) -> Int64 {
  _ = probe(1)
  defer { _ = probe(0) }
  try operation()
  return probe(0)
}

// Exercise output backpressure with a reusable small chunk. Capturing the bytes
// in reserved caller storage lets C zlib check the entire stream after probing.
private func driveWithoutAllocations(
  _ deflater: inout Deflater, input: borrowing Span<UInt8>, flush: Deflater.Flush,
  chunk: inout UniqueArray<UInt8>, encoded: inout UniqueArray<UInt8>
) throws(DeflateError) {
  var offset = 0
  while true {
    chunk.removeAll()
    let progress = try chunk.edit { (output: inout OutputSpan<UInt8>) throws(DeflateError) in
      try deflater.process(input: input.extracting(droppingFirst: offset), output: &output, flush: flush)
    }
    offset += progress.inputConsumed
    encoded.append(copying: chunk.span)
    if progress.status != .needsOutput {
      precondition(offset == input.count)
      return
    }
    precondition(progress.inputConsumed > 0 || progress.outputProduced > 0)
  }
}

@Test(arguments: [ZLib.Format.rawDeflate, .zlib, .gzip], [ZLib.Strategy.stored, .fixed, .dynamic, .automatic])
func streamingDeflaterReusesWorkingStorageWithoutAllocations(format: ZLib.Format, strategy: ZLib.Strategy) throws {
  guard ProcessInfo.processInfo.environment["SWIFT_ZLIB_ALLOCATIONS"] == "1" else { return }
  #if os(macOS)
  let scope = UnsafeMutableRawPointer(bitPattern: -2)
  #else
  let scope: UnsafeMutableRawPointer? = nil
  #endif
  let symbol = try #require(dlsym(scope, "swift_zlib_allocation_probe"))
  let probe = unsafeBitCast(symbol, to: AllocationProbe.self)
  let calibrationSymbol = try #require(dlsym(scope, "swift_zlib_allocation_calibration"))
  let calibrate = unsafeBitCast(calibrationSymbol, to: (@convention(c) () -> Int32).self)
  _ = probe(1)
  let calibration = calibrate()
  let calibrationCalls = probe(0)
  try #require(calibration != 0 && calibrationCalls > 0)
  // Cross several DEFLATE block boundaries without an application-specific size.
  let maximumInput = 65_535 * 3 + 1
  var random: UInt32 = 1
  let noise = (0..<maximumInput).map { _ in
    random ^= random << 13
    random ^= random >> 17
    random ^= random << 5
    return UInt8(truncatingIfNeeded: random)
  }
  let payloads: [[UInt8]] = [
    [], [0xFF], [UInt8](repeating: 0x5A, count: maximumInput), noise,
    Array(noise.prefix(65_535)) + [UInt8](repeating: 0x5A, count: 65_536),
    InteropPayload.skewedFrequencies.bytes
  ]
  let empty: [UInt8] = []
  for effort in ZLib.Effort.allCases {
    var totalCalls: Int64 = 0
    for input in payloads {
      // Initialization is outside the measured scope. There is no warmup encode.
      var deflater = Deflater(format: format, strategy: strategy, effort: effort)
      var chunk = UniqueArray<UInt8>(capacity: 257)
      var encoded = UniqueArray<UInt8>(capacity: maximumInput * 2 + 1_024)
      let calls = try measuredAllocations(probe) { () throws(DeflateError) in
        try driveWithoutAllocations(&deflater, input: input.span, flush: .finish, chunk: &chunk, encoded: &encoded)
      }
      #expect(calls == 0)
      let bytes = (0..<encoded.count).map { encoded[$0] }
      #expect(try cZlibInflate(bytes, expectedCount: input.count, windowBits: deflaterWindowBits(format)) == input)

      let syncCalls = try measuredAllocations(probe) { () throws(DeflateError) in
        deflater.reset()
        encoded.removeAll()
        try driveWithoutAllocations(&deflater, input: input.span, flush: .none, chunk: &chunk, encoded: &encoded)
        try driveWithoutAllocations(&deflater, input: empty.span, flush: .sync, chunk: &chunk, encoded: &encoded)
        try driveWithoutAllocations(&deflater, input: empty.span, flush: .finish, chunk: &chunk, encoded: &encoded)
      }
      #expect(syncCalls == 0)
      let synced = (0..<encoded.count).map { encoded[$0] }
      #expect(try cZlibInflate(synced, expectedCount: input.count, windowBits: deflaterWindowBits(format)) == input)

      var consumed = 0
      let blockedCalls = try measuredAllocations(probe) { () throws(DeflateError) in
        deflater.reset()
        var noOutput = OutputSpan<UInt8>()
        let blocked = try deflater.process(input: input.span, output: &noOutput, flush: .finish)
        precondition(blocked.status == .needsOutput)
        consumed = blocked.inputConsumed
      }
      #expect(blockedCalls == 0)
      // Swift error boxing is outside the allocation guarantee. The reset and
      // subsequent encoding must still reuse all working storage after failure.
      var invalidState = false
      var noOutput = OutputSpan<UInt8>()
      do throws(DeflateError) {
        _ = try deflater.process(input: input.span.extracting(droppingFirst: consumed), output: &noOutput, flush: .sync)
      } catch {
        if case .invalidState = error { invalidState = true } else { throw error }
      }
      let recoveryCalls = try measuredAllocations(probe) { () throws(DeflateError) in
        deflater.reset()
        encoded.removeAll()
        try driveWithoutAllocations(&deflater, input: input.span, flush: .finish, chunk: &chunk, encoded: &encoded)
      }
      #expect(recoveryCalls == 0)
      #expect(invalidState)
      let recovered = (0..<encoded.count).map { encoded[$0] }
      #expect(try cZlibInflate(recovered, expectedCount: input.count, windowBits: deflaterWindowBits(format)) == input)
      totalCalls += calls + syncCalls + blockedCalls + recoveryCalls
    }
    print("DEFLATER_ALLOCATIONS format=\(format) strategy=\(strategy) effort=\(effort) calls=\(totalCalls)")
  }
}
#endif
