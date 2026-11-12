import HeapModule

/// Builds initial Huffman code lengths without enforcing a bit-length limit.
/// Unused symbols have length zero; a single used symbol has length one.
func huffmanCodeLengths(frequencies: [Int]) -> [Int] {
  var tree = [HuffmanNode?](repeating: nil, count: frequencies.count)
  var heap = Heap<HuffmanHeapEntry>()

  for (symbol, count) in frequencies.enumerated() {
    if count > 0 {
      let node = HuffmanNode(frequency: count, symbol: symbol, left: nil, right: nil)
      tree[symbol] = node
      heap.insert(HuffmanHeapEntry(frequency: count, nodeIndex: symbol))
    }
  }

  while heap.count > 1 {
    let leftIndex = heap.popMin()!.nodeIndex
    let rightIndex = heap.popMin()!.nodeIndex
    let left = tree[leftIndex]!
    let right = tree[rightIndex]!

    let frequency = left.frequency + right.frequency
    let joined = HuffmanNode(
      frequency: frequency,
      symbol: nil,
      left: leftIndex,
      right: rightIndex)
    let index = tree.count
    tree.append(joined)
    heap.insert(HuffmanHeapEntry(frequency: frequency, nodeIndex: index))
  }

  var lengths = [Int](repeating: 0, count: frequencies.count)
  guard let root = heap.popMin() else {
    return lengths
  }
  var pending: [(index: Int, depth: Int)] = [(root.nodeIndex, 0)]

  while let (index, depth) = pending.popLast() {
    let node = tree[index]!
    if let symbol = node.symbol {
      lengths[symbol] = max(depth, 1)
    } else {
      if let left = node.left {
        pending.append((left, depth + 1))
      }
      if let right = node.right {
        pending.append((right, depth + 1))
      }
    }
  }

  return lengths
}

/// Limits a Huffman tree's depth while preserving its symbols and prefix property.
func huffmanCodeLengths(frequencies: [Int], maxBits: Int) -> [Int] {
  precondition((1...15).contains(maxBits), "Invalid Huffman bit-length limit")

  var lengths = huffmanCodeLengths(frequencies: frequencies)
  let longest = lengths.max() ?? 0
  guard longest > maxBits else {
    return lengths
  }

  let symbols = frequencies.indices.filter { frequencies[$0] > 0 }.sorted {
    (frequencies[$0], $0) < (frequencies[$1], $1)
  }
  precondition(symbols.count <= (1 << maxBits), "Too many symbols for the Huffman bit-length limit")

  var counts = [Int](repeating: 0, count: longest + 1)
  for length in lengths where length > 0 {
    counts[length] += 1
  }

  for bits in stride(from: longest, through: maxBits + 1, by: -1) {
    while counts[bits] > 0 {
      var shorter = bits - 2
      while counts[shorter] == 0 {
        shorter -= 1
      }

      // Merge the deepest sibling pair and split a shallower leaf. This keeps
      // both the number of symbols and the space occupied by the tree intact.
      counts[bits] -= 2
      counts[bits - 1] += 1
      counts[shorter] -= 1
      counts[shorter + 1] += 2
    }
  }

  var symbolIndex = 0
  for bits in stride(from: maxBits, through: 1, by: -1) {
    for _ in 0..<counts[bits] {
      lengths[symbols[symbolIndex]] = bits
      symbolIndex += 1
    }
  }
  return lengths
}

func canonicalHuffmanCodes(lengths: [Int]) -> [UInt16?] {
  precondition(lengths.allSatisfy { (0...15).contains($0) }, "Invalid Huffman code length")

  let maxLength = lengths.max() ?? 0
  var counts = [Int](repeating: 0, count: maxLength + 1)

  for length in lengths where length > 0 {
    counts[length] += 1
  }

  var code = 0
  var nextCode = [UInt16](repeating: 0, count: counts.count)
  for bits in 1..<counts.count {
    code = (code + counts[bits - 1]) << 1
    precondition(code + counts[bits] <= (1 << bits), "Oversubscribed Huffman code lengths")
    nextCode[bits] = UInt16(code)
  }

  var codes = [UInt16?](repeating: nil, count: lengths.count)
  for (symbol, length) in lengths.enumerated() where length > 0 {
    codes[symbol] = nextCode[length]
    nextCode[length] += 1
  }

  return codes
}
