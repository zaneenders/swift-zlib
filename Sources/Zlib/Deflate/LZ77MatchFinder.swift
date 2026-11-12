enum DeflateToken: Equatable, Sendable {
  case literal(UInt8)
  case match(length: Int, distance: Int)
}

/// A bounded hash-chain search over the previous 32 KiB of input.
struct LZ77MatchFinder: ~Copyable {
  private var heads = [Int](repeating: -1, count: 65_536)
  private var previous = [Int](repeating: -1, count: 32_768)
  private static let maximumCandidates = 128

  /// Advances `position` by one literal or a match of up to 258 bytes.
  /// Matches may overlap and may refer into previous blocks.
  mutating func next(
    input: borrowing Span<UInt8>, position: inout Int, end: Int
  ) -> DeflateToken {
    precondition(position >= 0 && position < end && end <= input.count)
    var bestLength = 2
    var bestDistance = 0
    let maximumLength = min(258, end - position)
    if maximumLength >= 3 {
      var candidate = heads[hash(input, at: position)]
      let oldest = max(0, position - 32_768)
      var searched = 0
      while candidate >= oldest && searched < Self.maximumCandidates {
        if input[candidate + bestLength] == input[position + bestLength] {
          var length = 0
          while length < maximumLength && input[candidate + length] == input[position + length] {
            length += 1
          }
          if length > bestLength {
            bestLength = length
            bestDistance = position - candidate
            if length == maximumLength { break }
          }
        }
        candidate = previous[candidate & 32_767]
        searched += 1
      }
    }
    let consumed = bestDistance > 0 ? bestLength : 1
    for index in position..<(position + consumed) where input.count - index >= 3 {
      let key = hash(input, at: index)
      previous[index & 32_767] = heads[key]
      heads[key] = index
    }
    let token: DeflateToken =
      bestDistance > 0 ? .match(length: bestLength, distance: bestDistance) : .literal(input[position])
    position += consumed
    return token
  }

  private func hash(_ input: borrowing Span<UInt8>, at index: Int) -> Int {
    ((Int(input[index]) * 251 + Int(input[index + 1])) * 251 + Int(input[index + 2])) & 65_535
  }
}
