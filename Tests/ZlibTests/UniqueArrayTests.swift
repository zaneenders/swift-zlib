import Testing

import Zlib

@Test func uniqueArrayStartsEmpty() {
  let output = UniqueArray<UInt8>(capacity: 4)

  #expect(output.capacity == 4)
  #expect(output.count == 0)
  #expect(output.span.count == 0)
}

@Test func uniqueArrayExposesOnlyInitializedBytes() throws {
  var output = UniqueArray<UInt8>(capacity: 4)
  output.append(0x41)
  output.append(0x42)

  #expect(output.count == 2)
  let view = output.span
  try #require(view.count == 2)
  #expect(view[0] == 0x41)
  #expect(view[1] == 0x42)
}

@Test(arguments: [0, 2])
func uniqueArrayAppendGrowsWhenFull(capacity: Int) throws {
  var output = UniqueArray<UInt8>(capacity: capacity)
  for _ in 0..<capacity {
    output.append(0x41)
  }
  #expect(output.count == capacity)

  output.append(0x42)

  #expect(output.count == capacity + 1)
  #expect(output.capacity >= output.count)
  let view = output.span
  try #require(view.count == capacity + 1)
  for index in 0..<capacity {
    #expect(view[index] == 0x41)
  }
  #expect(view[capacity] == 0x42)
}

@Test func movingUniqueArrayPreservesItsContents() throws {
  var original = UniqueArray<UInt8>(capacity: 1)
  original.append(0x41)

  let moved = consume original

  #expect(moved.count == 1)
  let view = moved.span
  try #require(view.count == 1)
  #expect(view[0] == 0x41)
}

@Test func reservingMoreCapacityPreservesInitializedBytes() throws {
  var output = UniqueArray<UInt8>(capacity: 2)
  output.append(0x41)
  output.append(0x42)

  output.reserveCapacity(8)

  #expect(output.capacity >= 8)
  #expect(output.count == 2)
  let view = output.span
  try #require(view.count == 2)
  #expect(view[0] == 0x41)
  #expect(view[1] == 0x42)
}

@Test func reservedCapacityCanBeUsedAcrossMultipleGrowths() throws {
  var output = UniqueArray<UInt8>(capacity: 1)
  output.append(0x41)

  output.reserveCapacity(3)
  output.append(0x42)
  output.append(0x43)
  output.reserveCapacity(8)
  output.append(0x44)

  #expect(output.capacity >= 8)
  #expect(output.count == 4)
  let view = output.span
  try #require(view.count == 4)
  #expect(view[0] == 0x41)
  #expect(view[1] == 0x42)
  #expect(view[2] == 0x43)
  #expect(view[3] == 0x44)
}

@Test func reservingFromZeroCapacityAllowsAppending() throws {
  var output = UniqueArray<UInt8>(capacity: 0)

  output.reserveCapacity(2)

  #expect(output.capacity >= 2)
  #expect(output.count == 0)
  output.append(0x41)
  #expect(output.count == 1)
  let view = output.span
  try #require(view.count == 1)
  #expect(view[0] == 0x41)
}

@Test(arguments: [0, 1, 2])
func reservingExistingCapacityDoesNotShrink(minimumCapacity: Int) throws {
  var output = UniqueArray<UInt8>(capacity: 2)
  output.append(0x41)

  output.reserveCapacity(minimumCapacity)

  #expect(output.capacity == 2)
  #expect(output.count == 1)
  let view = output.span
  try #require(view.count == 1)
  #expect(view[0] == 0x41)
}
