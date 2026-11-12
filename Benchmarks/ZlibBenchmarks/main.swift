import Foundation
import Zlib

let arguments = CommandLine.arguments
let iterations: Int
if arguments.count == 3, arguments[1] == "--iterations", let count = Int(arguments[2]), count > 0 {
  iterations = count
} else if arguments.count == 1 {
  iterations = 10
} else {
  fatalError("Usage: swift run -c release ZlibBenchmarks [--iterations COUNT]")
}

func seconds(_ duration: Duration) -> Double {
  let components = duration.components
  return Double(components.seconds) + Double(components.attoseconds) / 1e18
}

var randomState: UInt32 = 0xC0FFEE
let random = (0..<65_536).map { _ in
  randomState ^= randomState << 13
  randomState ^= randomState >> 17
  randomState ^= randomState << 5
  return UInt8(truncatingIfNeeded: randomState)
}
let payloads: [(String, [UInt8])] = [
  ("repeated", [UInt8](repeating: 90, count: 65_536)),
  ("text", Array(String(repeating: "Swift deflate / inflate.\n", count: 2_731).utf8)),
  ("all-bytes", (0..<65_536).map { UInt8(truncatingIfNeeded: $0) }),
  ("random", random)
]

print("payload,strategy,input_bytes,compressed_bytes,ratio,encode_mib_s,decode_mib_s")
for (name, input) in payloads {
  for (strategyName, strategy) in [
    ("stored", ZLib.Strategy.stored), ("fixed", .fixed), ("dynamic", .dynamic)
  ] {
    let encoded = try ZLib.deflate(input: input.span, strategy: strategy)
    let decoded = try ZLib.inflate(input: encoded.span)
    precondition(decoded.count == input.count && input.indices.allSatisfy { decoded[$0] == input[$0] })

    var observedBytes = 0
    let encodeTime = ContinuousClock().measure {
      for _ in 0..<iterations {
        let result = try! ZLib.deflate(input: input.span, strategy: strategy)
        observedBytes += result.count
      }
    }
    let decodeTime = ContinuousClock().measure {
      for _ in 0..<iterations {
        let result = try! ZLib.inflate(input: encoded.span)
        observedBytes += result.count
      }
    }
    precondition(observedBytes > 0)
    let mebibytes = Double(input.count) * Double(iterations) / 1_048_576
    let metrics = String(
      format: "%.5f,%.2f,%.2f", Double(encoded.count) / Double(input.count),
      mebibytes / seconds(encodeTime), mebibytes / seconds(decodeTime))
    print("\(name),\(strategyName),\(input.count),\(encoded.count),\(metrics)")
  }
}
