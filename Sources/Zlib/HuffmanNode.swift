struct HuffmanNode {
  let frequency: Int
  let symbol: Int?
  let left: Int?
  let right: Int?
}

struct HuffmanHeapEntry: Comparable {
  let frequency: Int
  let nodeIndex: Int

  static func < (lhs: Self, rhs: Self) -> Bool {
    return (lhs.frequency, lhs.nodeIndex) < (rhs.frequency, rhs.nodeIndex)
  }
}
