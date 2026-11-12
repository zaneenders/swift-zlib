struct BlockHeader: ~Copyable {
  let blockType: BlockType
  let isFinal: Bool
}

enum BlockType {
  case stored
  case fixedHuffman
  case dynamicHuffman
}
