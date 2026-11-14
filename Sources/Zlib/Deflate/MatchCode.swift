/// DEFLATE's length and distance alphabets and their numeric extra bits.
struct MatchCode {
  let symbol: Int
  let extraBits: UInt16
  let extraBitCount: Int

  static let lengthBases: InlineArray<29, Int> = [
    3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27,
    31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258
  ]
  static let lengthExtraBits: InlineArray<29, Int> = [
    0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2,
    2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0
  ]
  static let distanceBases: InlineArray<30, Int> = [
    1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129,
    193, 257, 385, 513, 769, 1_025, 1_537, 2_049, 3_073,
    4_097, 6_145, 8_193, 12_289, 16_385, 24_577
  ]
  static let distanceExtraBits: InlineArray<30, Int> = [
    0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6,
    6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13
  ]

  static func length(_ length: Int) -> MatchCode {
    precondition((3...258).contains(length))
    // Direct scans avoid temporary storage from generic predicate searches.
    var index = lengthBases.count - 1
    while lengthBases[index] > length { index -= 1 }
    return MatchCode(
      symbol: index + 257, extraBits: UInt16(length - lengthBases[index]),
      extraBitCount: lengthExtraBits[index])
  }

  static func distance(_ distance: Int) -> MatchCode {
    precondition((1...32_768).contains(distance))
    var index = distanceBases.count - 1
    while distanceBases[index] > distance { index -= 1 }
    return MatchCode(
      symbol: index, extraBits: UInt16(distance - distanceBases[index]),
      extraBitCount: distanceExtraBits[index])
  }
}
