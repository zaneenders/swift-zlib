import HeapModule

/// Builds initial Huffman code lengths without enforcing a bit-length limit.
/// Unused symbols have length zero; a single used symbol has length one.
/// Replaces `lengths`, reusing its capacity when possible.
func huffmanCodeLengths(frequencies: [Int], into lengths: inout [Int]) {
  var workspace = HuffmanWorkspace(maximumSymbols: frequencies.count)
  workspace.codeLengths(frequencies: frequencies.span, into: &lengths)
}

/// Limits a Huffman tree's depth while preserving its symbols and prefix property.
/// Replaces `lengths`, reusing its capacity when possible.
func huffmanCodeLengths(frequencies: [Int], maxBits: Int, into lengths: inout [Int]) {
  var workspace = HuffmanWorkspace(maximumSymbols: frequencies.count)
  workspace.codeLengths(frequencies: frequencies.span, maxBits: maxBits, into: &lengths)
}

/// Startup-reserved scratch shared by all three DEFLATE Huffman alphabets.
struct HuffmanWorkspace: ~Copyable {
  private let maximumSymbols: Int
  private var tree: [HuffmanNode?] = []
  private var heap: Heap<HuffmanHeapEntry>
  private var pending: [(index: Int, depth: Int)] = []
  private var counts: [Int]

  init(maximumSymbols: Int) {
    precondition(maximumSymbols >= 0)
    self.maximumSymbols = maximumSymbols
    tree.reserveCapacity(max(0, maximumSymbols * 2 - 1))
    heap = Heap(minimumCapacity: maximumSymbols)
    pending.reserveCapacity(maximumSymbols)
    counts = [Int](repeating: 0, count: maximumSymbols + 1)
  }

  /// Output capacity must be reserved by the owner to avoid growing `lengths`.
  mutating func codeLengths(
    frequencies: borrowing Span<Int>, maxBits: Int? = nil, into lengths: inout [Int]
  ) {
    precondition(frequencies.count <= maximumSymbols)
    if let maxBits { precondition((1...15).contains(maxBits), "Invalid Huffman bit-length limit") }
    precondition(heap.isEmpty && pending.isEmpty)
    tree.removeAll(keepingCapacity: true)
    for symbol in 0..<frequencies.count {
      let frequency = frequencies[symbol]
      tree.append(frequency > 0 ? HuffmanNode(frequency: frequency, symbol: symbol, left: nil, right: nil) : nil)
      if frequency > 0 { heap.insert(HuffmanHeapEntry(frequency: frequency, nodeIndex: symbol)) }
    }
    while heap.count > 1 {
      let left = heap.popMin()!.nodeIndex
      let right = heap.popMin()!.nodeIndex
      let frequency = tree[left]!.frequency + tree[right]!.frequency
      let index = tree.count
      tree.append(HuffmanNode(frequency: frequency, symbol: nil, left: left, right: right))
      heap.insert(HuffmanHeapEntry(frequency: frequency, nodeIndex: index))
    }

    lengths.removeAll(keepingCapacity: true)
    // Generic Sequence adaptation can allocate even when array capacity is reserved.
    for _ in 0..<frequencies.count { lengths.append(0) }
    guard let root = heap.popMin() else { return }
    pending.append((root.nodeIndex, 0))
    var longest = 0
    while let (index, depth) = pending.popLast() {
      let node = tree[index]!
      if let symbol = node.symbol {
        lengths[symbol] = max(depth, 1)
        longest = max(longest, lengths[symbol])
      } else {
        if let left = node.left { pending.append((left, depth + 1)) }
        if let right = node.right { pending.append((right, depth + 1)) }
      }
    }
    guard let maxBits, longest > maxBits else { return }

    for index in 0...longest { counts[index] = 0 }
    for symbol in 0..<frequencies.count where frequencies[symbol] > 0 {
      counts[lengths[symbol]] += 1
      // Heap order matches sorting by (frequency, symbol), without sort scratch.
      heap.insert(HuffmanHeapEntry(frequency: frequencies[symbol], nodeIndex: symbol))
    }
    precondition(heap.count <= (1 << maxBits), "Too many symbols for the Huffman bit-length limit")
    var bits = longest
    while bits > maxBits {
      while counts[bits] > 0 {
        var shorter = bits - 2
        while counts[shorter] == 0 { shorter -= 1 }
        // Merge the deepest siblings and split a shallower leaf, preserving
        // both the symbol count and the space occupied by the tree.
        counts[bits] -= 2
        counts[bits - 1] += 1
        counts[shorter] -= 1
        counts[shorter + 1] += 2
      }
      bits -= 1
    }
    bits = maxBits
    while bits >= 1 {
      for _ in 0..<counts[bits] { lengths[heap.popMin()!.nodeIndex] = bits }
      bits -= 1
    }
    assert(heap.isEmpty)
  }
}

/// Replaces `codes` with canonical assignments, reusing its capacity when possible.
func canonicalHuffmanCodes(lengths: [Int], into codes: inout [UInt16?]) {
  var maxLength = 0
  var counts = InlineArray<16, Int>(repeating: 0)

  for index in lengths.indices {
    let length = lengths[index]
    precondition((0...15).contains(length), "Invalid Huffman code length")
    maxLength = max(maxLength, length)
    if length > 0 { counts[length] += 1 }
  }

  var code = 0
  var nextCode = InlineArray<16, UInt16>(repeating: 0)
  for bits in 1..<(maxLength + 1) {
    code = (code + counts[bits - 1]) << 1
    precondition(code + counts[bits] <= (1 << bits), "Oversubscribed Huffman code lengths")
    nextCode[bits] = UInt16(code)
  }

  codes.removeAll(keepingCapacity: true)
  for _ in lengths.indices { codes.append(nil) }
  for symbol in lengths.indices {
    let length = lengths[symbol]
    if length > 0 {
      codes[symbol] = nextCode[length]
      nextCode[length] += 1
    }
  }
}
