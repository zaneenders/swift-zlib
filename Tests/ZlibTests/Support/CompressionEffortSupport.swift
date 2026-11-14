// Identical three-byte prefixes put short matches in front of an older, long
// match. The unique separator prevents parsing a match across the test boundary.
func effortCollisionInput(recentCandidates: Int) -> (bytes: [UInt8], start: Int) {
  let best = [UInt8(65), 66, 67] + [UInt8](repeating: 90, count: 253)
  let short = [UInt8(65), 66, 67, 0, 0, 0, 0, 0]
  let history = best + Array(repeating: short, count: recentCandidates).flatMap { $0 } + [0xFF]
  return (history + best, history.count)
}
