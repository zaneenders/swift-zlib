/// Exact costs for one token parse at the writer's current bit position.
struct DeflateBlockCosts {
  enum Choice: Equatable {
    case stored, fixed, dynamic
  }

  let stored: Int
  let fixed: Int
  let dynamic: Int

  /// Equal costs prefer stored, then fixed, then dynamic blocks.
  var choice: Choice {
    if stored <= fixed && stored <= dynamic { return .stored }
    if fixed <= dynamic { return .fixed }
    return .dynamic
  }

  /// The supplied fixed and dynamic costs include block headers and end markers.
  /// Final padding or a following sync marker is charged here but emitted by
  /// the caller after the chosen block.
  init(
    inputCount: Int, fixedBitCount: Int, dynamicBitCount: Int, bitPosition: Int,
    isFinal: Bool, syncFlush: Bool = false
  ) {
    precondition((0...65_535).contains(inputCount))
    precondition((0...7).contains(bitPosition))
    precondition(fixedBitCount >= 3 && dynamicBitCount >= 3)
    precondition(!isFinal || !syncFlush)

    func padding(after bits: Int) -> Int {
      (8 - ((bitPosition + (bits & 7)) & 7)) & 7
    }
    func completeCost(_ bits: Int) -> Int {
      if isFinal { return bits + padding(after: bits) }
      if syncFlush {
        // Empty stored block: three header bits, alignment, LEN, and NLEN.
        return bits + 3 + padding(after: bits + 3) + 32
      }
      return bits
    }

    stored = completeCost(3 + padding(after: 3) + 32 + inputCount * 8)
    fixed = completeCost(fixedBitCount)
    dynamic = completeCost(dynamicBitCount)
  }
}
