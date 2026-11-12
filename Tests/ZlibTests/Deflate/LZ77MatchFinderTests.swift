import Testing

@testable import Zlib

@Test func matchFinderEmitsOverlappingMaximumLengthMatches() {
  let input = [UInt8](repeating: 90, count: 600)
  var finder = LZ77MatchFinder()
  var position = 0
  #expect(finder.next(input: input.span, position: &position, end: input.count) == .literal(90))
  #expect(finder.next(input: input.span, position: &position, end: input.count) == .match(length: 258, distance: 1))
  #expect(finder.next(input: input.span, position: &position, end: input.count) == .match(length: 258, distance: 1))
  #expect(finder.next(input: input.span, position: &position, end: input.count) == .match(length: 83, distance: 1))
  #expect(position == input.count)
}

@Test(arguments: [32_768, 32_769])
func matchFinderHonorsTheHistoryWindow(distance: Int) {
  let prefix = [UInt8(65), 66, 67] + [UInt8](repeating: 0, count: distance - 3)
  let input = prefix + prefix.prefix(258)
  var finder = LZ77MatchFinder()
  var position = 0
  while position < distance {
    _ = finder.next(input: input.span, position: &position, end: distance)
  }

  let token = finder.next(input: input.span, position: &position, end: input.count)

  #expect(token == (distance == 32_768 ? .match(length: 258, distance: 32_768) : .literal(65)))
}

@Test(arguments: [1, 2])
func matchFinderSeedsOverlappingMatchesAcrossTheHistoryBoundary(distance: Int) {
  let pattern = Array([UInt8(65), 66].prefix(distance))
  let history = [UInt8](repeating: 0, count: 32_768 - distance) + pattern
  let payload = (0..<258).map { pattern[$0 % pattern.count] }
  let input = history + payload
  var finder = LZ77MatchFinder()
  finder.seed(input: input.span, end: history.count)
  var position = history.count

  let token = finder.next(input: input.span, position: &position, end: input.count)

  #expect(token == .match(length: payload.count, distance: distance))
  #expect(position == input.count)
}

@Test(arguments: [32_768, 32_769])
func matchFinderSeedHonorsTheHistoryWindow(distance: Int) {
  let history = [UInt8(65), 66, 67] + [UInt8](repeating: 0, count: distance - 3)
  let input = history + history.prefix(258)
  var finder = LZ77MatchFinder()
  finder.seed(input: input.span, end: history.count)
  var position = history.count

  let token = finder.next(input: input.span, position: &position, end: input.count)

  #expect(token == (distance == 32_768 ? .match(length: 258, distance: 32_768) : .literal(65)))
  #expect(position == distance + (distance == 32_768 ? 258 : 1))
}

@Test(arguments: [0, 1, 2, 3, 257, 258, 259, 32_768, 65_537])
func matchFinderTokensReconstructTheirInput(length: Int) {
  let input = (0..<length).map { UInt8(truncatingIfNeeded: $0 * 37 + 11) }
  var finder = LZ77MatchFinder()
  var position = 0
  var decoded: [UInt8] = []
  while position < input.count {
    let token = finder.next(input: input.span, position: &position, end: input.count)
    switch token {
    case .literal(let byte): decoded.append(byte)
    case .match(let length, let distance):
      #expect((3...258).contains(length))
      #expect((1...min(decoded.count, 32_768)).contains(distance))
      for _ in 0..<length {
        decoded.append(decoded[decoded.count - distance])
      }
    }
  }
  #expect(decoded == input)
}
