import Testing

@testable import Zlib

@Test func ownedBytesStartsEmpty() {
  let output = OwnedBytes(capacity: 4)

  #expect(output.capacity == 4)
  #expect(output.count == 0)
  #expect(output.readSpan().count == 0)
}

@Test func ownedBytesExposesOnlyInitializedBytes() throws {
  var output = OwnedBytes(capacity: 4)
  try output.append(0x41)
  try output.append(0x42)

  #expect(output.count == 2)
  let view = output.readSpan()
  try #require(view.count == 2)
  #expect(view[0] == 0x41)
  #expect(view[1] == 0x42)
}

@Test(arguments: [0, 2])
func ownedBytesRejectsAppendWhenFull(capacity: Int) throws {
  var output = OwnedBytes(capacity: capacity)
  for _ in 0..<capacity {
    try output.append(0x41)
  }
  #expect(output.count == capacity)

  #expect(throws: OwnedBytesError.capacityExceeded) {
    try output.append(0x42)
  }

  #expect(output.count == capacity)
  let view = output.readSpan()
  try #require(view.count == capacity)
  for index in 0..<capacity {
    #expect(view[index] == 0x41)
  }
}

@Test func movingOwnedBytesPreservesItsContents() throws {
  var original = OwnedBytes(capacity: 1)
  try original.append(0x41)

  let moved = consume original

  #expect(moved.count == 1)
  let view = moved.readSpan()
  try #require(view.count == 1)
  #expect(view[0] == 0x41)
}

@Test func reservingMoreCapacityPreservesInitializedBytes() throws {
  var output = OwnedBytes(capacity: 2)
  try output.append(0x41)
  try output.append(0x42)

  output.reserveCapacity(8)

  #expect(output.capacity >= 8)
  #expect(output.count == 2)
  let view = output.readSpan()
  try #require(view.count == 2)
  #expect(view[0] == 0x41)
  #expect(view[1] == 0x42)
}

@Test func reservedCapacityCanBeUsedAcrossMultipleGrowths() throws {
  var output = OwnedBytes(capacity: 1)
  try output.append(0x41)

  output.reserveCapacity(3)
  try output.append(0x42)
  try output.append(0x43)
  output.reserveCapacity(8)
  try output.append(0x44)

  #expect(output.capacity >= 8)
  #expect(output.count == 4)
  let view = output.readSpan()
  try #require(view.count == 4)
  #expect(view[0] == 0x41)
  #expect(view[1] == 0x42)
  #expect(view[2] == 0x43)
  #expect(view[3] == 0x44)
}

@Test func reservingFromZeroCapacityAllowsAppending() throws {
  var output = OwnedBytes(capacity: 0)

  output.reserveCapacity(2)

  #expect(output.capacity >= 2)
  #expect(output.count == 0)
  try output.append(0x41)
  #expect(output.count == 1)
  let view = output.readSpan()
  try #require(view.count == 1)
  #expect(view[0] == 0x41)
}

@Test(arguments: [0, 1, 2])
func reservingExistingCapacityDoesNotShrink(minimumCapacity: Int) throws {
  var output = OwnedBytes(capacity: 2)
  try output.append(0x41)

  output.reserveCapacity(minimumCapacity)

  #expect(output.capacity == 2)
  #expect(output.count == 1)
  let view = output.readSpan()
  try #require(view.count == 1)
  #expect(view[0] == 0x41)
}
