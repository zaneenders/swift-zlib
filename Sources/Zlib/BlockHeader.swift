struct BlockHeader: ~Copyable {
  let bType: BType
  let isLastByte: Bool
}

enum BType {
  case stored
  case fixedHuffman
  case dynamicHuffman
  case invalid
}
