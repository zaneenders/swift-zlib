import BasicContainers

enum DeflateToken: Equatable, Sendable {
  case literal(UInt8)
  case match(length: Int, distance: Int)
}

/// A bounded hash-chain search over the previous 32 KiB of input.
struct LZ77MatchFinder: ~Copyable {
  private var heads = RigidArray<Int>(repeating: -1, count: 65_536)
  private var previous = RigidArray<Int>(repeating: -1, count: 32_768)
  private static let maximumCandidates = 128

  /// Reuses the hash chains for a rebased block without retaining old positions.
  mutating func reset() {
    for index in 0..<heads.count { heads[index] = -1 }
    for index in 0..<previous.count { previous[index] = -1 }
  }

  /// Seeds a fresh finder with history at `0..<end` before encoding new input.
  /// Lookahead may extend into new input, so the last two history positions can
  /// participate in matches without inserting any new input positions.
  mutating func seed(input: borrowing Span<UInt8>, end: Int) {
    precondition(end >= 0 && end <= input.count)
    for index in 0..<end where input.count - index >= 3 {
      insert(input: input, at: index)
    }
  }

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
          while maximumLength - length >= 8 {
            let difference =
              input.bytes.load(fromByteOffset: candidate + length, as: UInt64.self)
              ^ input.bytes.load(fromByteOffset: position + length, as: UInt64.self)
            if difference != 0 {
              length += difference.littleEndian.trailingZeroBitCount / 8
              break
            }
            length += 8
          }
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
      insert(input: input, at: index)
    }
    let token: DeflateToken =
      bestDistance > 0 ? .match(length: bestLength, distance: bestDistance) : .literal(input[position])
    position += consumed
    return token
  }

  private mutating func insert(input: borrowing Span<UInt8>, at index: Int) {
    let key = hash(input, at: index)
    previous[index & 32_767] = heads[key]
    heads[key] = index
  }

  private func hash(_ input: borrowing Span<UInt8>, at index: Int) -> Int {
    ((Int(input[index]) * 251 + Int(input[index + 1])) * 251 + Int(input[index + 2])) & 65_535
  }
}
